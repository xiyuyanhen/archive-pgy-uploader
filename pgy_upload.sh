#!/bin/bash
#
# pgy_upload.sh — 通用 Xcode Archive → 蒲公英 自动上传工具
# 适用：任意 iOS 项目（原生 / Flutter / RN / Unity），只要产出 .xcarchive
#
# 运行模式：
#   Xcode Run Script（runOnlyForDeploymentPostprocessing=1）：
#     脚本在 Archive 完成后自动执行。如果 $ARCHIVE_PATH 可用则直接处理；
#     否则采用多策略自动发现已创建的 .xcarchive。
#   手动 / CI：
#     pgy_upload.sh --archive /path/to/xxx.xcarchive
#     pgy_upload.sh --archive /path/to/xxx.ipa --version 1.2.3 --notes "修复BUG"
#
# 凭证：项目级 pgy_config.sh（--config 指定，已 gitignore）或环境变量 PGY_USER_KEY / PGY_API_KEY
#   本脚本为「共享引擎」，自身不含任何项目密钥与路径；
#   项目专属配置（密钥 + 是否上传 + 上传包信息）放在各自项目的 archive-pgy-config/ 目录。
# 控制文件：PGYUploadHistory.json（由 pgy_config.sh 的 PGY_HISTORY_FILE 指向），
#   .[0].versionTarget 为空 = 跳过上传；非空则带 version/versionTarget/updateDes 上传。
# 实时状态：自动打开一个本地 HTML 监控页，随进度刷新（等待→导出→上传→结果）。
#
set -e

# ============ 基础路径 ============
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$$"
MONITOR_HTML="${TMPDIR:-/tmp}/pgy_monitor_${TS}.html"
LOG_FILE="${TMPDIR:-/tmp}/pgy_upload_${TS}.log"

# ============ 可配置项（可被 pgy_config.sh / 环境变量覆盖） ============
PGY_METHOD="${PGY_METHOD:-development}"          # development | ad-hoc | app-store
PGY_MAX_WAIT="${PGY_MAX_WAIT:-300}"              # 等待模式最长秒数
PGY_DEBUG_CHECK="${PGY_DEBUG_CHECK:-auto}"       # auto | on | off（仅 Flutter 项目拦截 Debug）
PGY_VERSION_TARGET="${PGY_VERSION_TARGET:-}"     # 版本目标标签（如「测试版本」）
PGY_UPDATE_DESCRIPTION="${PGY_UPDATE_DESCRIPTION:-}" # 默认更新说明
PGY_VERSION_OVERRIDE="${PGY_VERSION:-}"         # 显式版本号（--version）
CONFIG_FILE="${PGY_CONFIG:-}"
PGY_TEAM_ID="${PGY_TEAM_ID:-${DEVELOPMENT_TEAM:-}}"   # 签名 team（自动读 Xcode $DEVELOPMENT_TEAM，可用 PGY_TEAM_ID 覆盖）
PGY_HISTORY_FILE="${PGY_HISTORY_FILE:-}"   # 由项目 pgy_config.sh 的 PGY_HISTORY_FILE 指定（不再兜底 SCRIPT_DIR）

# ============ 内部状态（供监控页使用） ============
STAGE=""; STAGE_ICON=""; STAGE_TITLE=""; STAGE_DETAIL=""
ERROR_MSG=""; DOWNLOAD_URL=""; QR_B64=""
FINAL_VERSION=""; PGY_CLEANUP=""
SKIP_UPLOAD=0

# ============ 日志 ============
# 注意：echo 到 stderr（>&2），避免在 $(...) 捕获时污染函数返回值
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg" >&2
}

# ============ 命令行参数 ============
UPLOAD_MODE=0
ARCHIVE_ARG=""
# 由主进程传入的路径（后台上传模式时复用，不基于子进程 $$ 重新生成）
INHERITED_MONITOR_HTML=""
INHERITED_LOG_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive)       ARCHIVE_ARG="$2"; shift 2;;
        --version)       PGY_VERSION_OVERRIDE="$2"; shift 2;;
        --notes)         PGY_UPDATE_DESCRIPTION="$2"; shift 2;;
        --target)        PGY_VERSION_TARGET="$2"; shift 2;;
        --method)        PGY_METHOD="$2"; shift 2;;
        --_upload)       UPLOAD_MODE=1; shift;;
        --config)        CONFIG_FILE="$2"; shift 2;;
        --history)       PGY_HISTORY_FILE="$2"; shift 2;;
        --monitor-path)  INHERITED_MONITOR_HTML="$2"; shift 2;;   # 主进程传入的监控页路径
        --log-path)      INHERITED_LOG_FILE="$2"; shift 2;;      # 主进程传入的日志路径
        -h|--help) awk 'NR==1 && /^#!\//{next} /^#/{sub(/^#\ ?/,""); print; next} {exit}' "$0"; exit 0;;
        *) echo "未知参数: $1" >&2; exit 1;;
    esac
done

# 后台上传模式：复用主进程的文件路径（避免子进程 $$ 不同导致写到新文件）
if [ -n "$INHERITED_MONITOR_HTML" ]; then
    MONITOR_HTML="$INHERITED_MONITOR_HTML"
fi
if [ -n "$INHERITED_LOG_FILE" ]; then
    LOG_FILE="$INHERITED_LOG_FILE"
fi

# ============ 加载配置 ============
load_config() {
    local candidates=()
    [ -n "$CONFIG_FILE" ] && candidates+=("$CONFIG_FILE")
    candidates+=("$SCRIPT_DIR/pgy_config.sh" "$HOME/.pgy_config.sh" "./pgy_config.sh")
    for cf in "${candidates[@]}"; do
        if [ -f "$cf" ]; then
            # shellcheck disable=SC1090
            source "$cf"
            break
        fi
    done
}
load_config

# ============ 依赖检查 ============
if ! command -v jq &> /dev/null; then
    echo "[ERROR] 未找到 jq，请先安装: brew install jq" >&2
    exit 1
fi

# ============ 读取 PGYUploadHistory.json（可选的项目级控制文件） ============
load_history() {
    [ -f "$PGY_HISTORY_FILE" ] || { log INFO "未找到 PGYUploadHistory.json（可选控制文件），跳过历史控制"; return 0; }
    if ! jq empty "$PGY_HISTORY_FILE" 2>/dev/null; then
        log ERROR "PGYUploadHistory.json 格式错误，已忽略"
        return 0
    fi
    local vt ver des
    vt=$(jq -r '.[0].versionTarget // empty' "$PGY_HISTORY_FILE" 2>/dev/null)
    ver=$(jq -r '.[0].version // empty' "$PGY_HISTORY_FILE" 2>/dev/null)
    des=$(jq -r '.[0].updateDes // empty' "$PGY_HISTORY_FILE" 2>/dev/null)
    log INFO "PGYUploadHistory.json: versionTarget='${vt:-<空>}' version='${ver:-<空>}' updateDes='${des:-<空>}'"
    if [ -z "$vt" ]; then
        SKIP_UPLOAD=1
        return 0
    fi
    [ -z "$PGY_VERSION_TARGET" ] && PGY_VERSION_TARGET="$vt"
    [ -z "$PGY_VERSION_OVERRIDE" ] && PGY_VERSION_OVERRIDE="$ver"
    [ -z "$PGY_UPDATE_DESCRIPTION" ] && PGY_UPDATE_DESCRIPTION="$des"
}
# ============ 上传前准备：读取控制文件 + 校验凭证 ============
prepare_upload() {
    load_history
    if [ "$SKIP_UPLOAD" = "1" ]; then
        log INFO "versionTarget 为空，跳过上传（由 PGYUploadHistory.json 控制）"
        exit 0
    fi
    if [ -z "$PGY_USER_KEY" ] || [ -z "$PGY_API_KEY" ]; then
        echo "[ERROR] 未配置 Pgyer 凭证。请在 pgy_config.sh 中设置 PGY_USER_KEY / PGY_API_KEY，或导出为环境变量。" >&2
        exit 1
    fi
}

# ============ 清理 ============
trap 'rm -rf "$PGY_CLEANUP" 2>/dev/null || true' EXIT

# ============ 实时监控页渲染 ============
render_monitor() {
    local refresh_meta="" body_content="" page_title="蒲公英上传"
    case "$STAGE" in
        waiting)
            refresh_meta='<meta http-equiv="refresh" content="2">'
            page_title="⏳ 等待 Archive..."
            body_content=$(cat <<ENDWAIT
<div class="spinner"></div>
<div class="stage-title">$STAGE_ICON $STAGE_TITLE</div>
<div class="stage-detail">$STAGE_DETAIL</div>
<div class="progress-bar"><div class="progress-fill waiting-pulse"></div></div>
<div class="info-grid">
  <div class="info-item"><span class="label">版本号</span><span class="value">$FINAL_VERSION</span></div>
  <div class="info-item"><span class="label">版本目标</span><span class="value">$PGY_VERSION_TARGET</span></div>
</div>
ENDWAIT
            );;
        exporting)
            refresh_meta='<meta http-equiv="refresh" content="2">'
            page_title="📦 导出 IPA..."
            body_content=$(cat <<ENDEXP
<div class="spinner"></div>
<div class="stage-title">$STAGE_ICON $STAGE_TITLE</div>
<div class="stage-detail">$STAGE_DETAIL</div>
<div class="progress-bar"><div class="progress-fill exporting-pulse"></div></div>
<div class="info-grid">
  <div class="info-item"><span class="label">版本号</span><span class="value">$FINAL_VERSION</span></div>
  <div class="info-item"><span class="label">版本目标</span><span class="value">$PGY_VERSION_TARGET</span></div>
</div>
<p class="hint">💡 此步骤通常需要 1-2 分钟，请耐心等待</p>
ENDEXP
            );;
        uploading)
            refresh_meta='<meta http-equiv="refresh" content="2">'
            page_title="☁️ 上传中..."
            body_content=$(cat <<ENDUP
<div class="spinner"></div>
<div class="stage-title">$STAGE_ICON $STAGE_TITLE</div>
<div class="stage-detail">$STAGE_DETAIL</div>
<div class="progress-bar"><div class="progress-fill uploading-pulse"></div></div>
<div class="info-grid">
  <div class="info-item"><span class="label">版本号</span><span class="value">$FINAL_VERSION</span></div>
  <div class="info-item"><span class="label">版本目标</span><span class="value">$PGY_VERSION_TARGET</span></div>
  <div class="info-item"><span class="label">描述</span><span class="value">$UPDATE_DESCRIPTION</span></div>
</div>
ENDUP
            );;
        success)
            page_title="✅ 上传成功"
            body_content=$(cat <<ENDOK
<div class="stage-title success-title">✅ 上传成功</div>
<img class="qr-img" src="data:image/png;base64,$QR_B64" alt="扫码下载"/>
<div class="result-info">
  <div class="result-row"><b>版本号：</b>$FINAL_VERSION</div>
  <div class="result-row"><b>版本目标：</b>$PGY_VERSION_TARGET</div>
  <div class="result-row"><b>更新描述：</b>$UPDATE_DESCRIPTION</div>
</div>
<a class="download-link" id="dl" href="https://www.pgyer.com/$DOWNLOAD_URL" target="_blank">https://www.pgyer.com/$DOWNLOAD_URL</a>
<button class="copy-btn" onclick="doCopy()">复制下载链接</button>
<script>
function doCopy(){
  var t=document.getElementById('dl').textContent;
  if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(t)}
  else{var ta=document.createElement('textarea');ta.value=t;document.body.appendChild(ta);ta.select();document.execCommand('copy');document.body.removeChild(ta)}
  var b=document.querySelector('.copy-btn');b.textContent='已复制!';setTimeout(function(){b.textContent='复制下载链接'},1500)
}
</script>
ENDOK
            );;
        error)
            page_title="❌ 上传失败"
            body_content=$(cat <<ENDERR
<div class="stage-title error-title">❌ 上传失败</div>
<div class="error-box"><div class="error-msg">$ERROR_MSG</div></div>
<button class="log-btn" onclick="window.location.href='file://$LOG_FILE'">📋 查看详细日志</button>
<p class="hint">💡 请检查网络连接或蒲公英账号配置</p>
ENDERR
            );;
    esac

    cat > "$MONITOR_HTML" <<HTMLEOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${page_title}</title>
$refresh_meta
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#1a1a1a;color:#e0e0e0;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display','PingFang SC','Helvetica Neue',sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;padding:20px}
.card{background:#252525;border-radius:20px;padding:40px 36px;max-width:440px;width:100%;box-shadow:0 12px 48px rgba(0,0,0,.5);text-align:center}
.spinner{width:44px;height:44px;margin:0 auto 20px;border:4px solid #333;border-top-color:#4caf50;border-radius:50%;animation:spin .8s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
.stage-title{font-size:22px;font-weight:700;margin-bottom:10px;color:#e0e0e0}
.stage-detail{font-size:14px;color:#888;margin-bottom:20px;line-height:1.5}
.progress-bar{height:4px;background:#333;border-radius:2px;margin-bottom:24px;overflow:hidden}
.progress-fill{height:100%;border-radius:2px;transition:width .3s}
.waiting-pulse{width:30%;background:#ffa726;animation:pulse 1.5s ease-in-out infinite}
.exporting-pulse{width:60%;background:#42a5f5;animation:pulse 1.5s ease-in-out infinite}
.uploading-pulse{width:80%;background:#ab47bc;animation:pulse 1.5s ease-in-out infinite}
@keyframes pulse{0%,100%{opacity:.5}50%{opacity:1}}
.info-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;text-align:left;margin-bottom:8px}
.info-item{background:#1e1e1e;border-radius:10px;padding:12px 14px}
.info-item .label{display:block;font-size:11px;color:#666;margin-bottom:4px;text-transform:uppercase;letter-spacing:.5px}
.info-item .value{font-size:14px;color:#ccc;font-weight:500}
.hint{font-size:12px;color:#555;margin-top:16px}
.success-title{color:#4caf50!important;font-size:24px;margin-bottom:24px}
.qr-img{width:220px;height:220px;border-radius:14px;margin:20px auto;background:#fff;padding:10px;display:block}
.result-info{text-align:left;margin:20px 0}
.result-row{font-size:14px;color:#bbb;line-height:1.8}
.result-row b{color:#ddd}
.download-link{display:block;word-break:break-all;color:#64b5f6;font-size:13px;margin:18px 0 14px;text-decoration:none}
.download-link:hover{text-decoration:underline}
.copy-btn{display:inline-block;padding:12px 28px;border-radius:10px;font-size:15px;font-weight:600;background:#4caf50;color:#fff;border:none;cursor:pointer;transition:background .2s}
.copy-btn:hover{background:#43a047}
.error-title{color:#ef5350!important;font-size:24px;margin-bottom:20px}
.error-box{background:rgba(239,83,80,.1);border:1px solid rgba(239,83,80,.3);border-radius:12px;padding:18px 20px;margin-bottom:20px;text-align:left}
.error-msg{font-size:14px;color:#ef5350;line-height:1.6;word-break:break-word}
.log-btn{display:inline-block;padding:10px 24px;border-radius:10px;font-size:14px;background:#333;color:#aaa;border:1px solid #444;cursor:pointer;margin-bottom:8px}
.log-btn:hover{background:#3a3a3a;color:#ddd}
</style>
</head>
<body>
<div class="card">
$body_content
</div>
</body>
</html>
HTMLEOF
}

# ============ 版本号探测 ============
detect_version() {
    local app_dir="$1"
    [ -n "$PGY_VERSION_OVERRIDE" ] && { FINAL_VERSION="$PGY_VERSION_OVERRIDE"; return 0; }
    local plist="$app_dir/Info.plist"
    [ -f "$plist" ] || return 1
    local sv bn
    sv=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$plist" 2>/dev/null || true)
    bn=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$plist" 2>/dev/null || true)
    [ -n "$sv" ] && { FINAL_VERSION="$sv${bn:+.$bn}"; return 0; }
    return 1
}

# ============ Debug 包拦截（仅 Flutter） ============
check_debug() {
    [ "$PGY_DEBUG_CHECK" = "off" ] && return 0
    local app_dir="$1"
    local flutter_fw="$app_dir/Frameworks/Flutter.framework/Flutter"
    [ -f "$flutter_fw" ] || return 0   # 非 Flutter 项目直接通过
    if strings "$flutter_fw" 2>/dev/null | grep -q "FlutterDebug"; then
        return 1
    fi
    local app_fw="$app_dir/Frameworks/App.framework/App"
    if [ -f "$app_fw" ] && strings "$app_fw" 2>/dev/null | grep -qi "debug.*mode\|kDartIsolateFlags.*enable-asserts"; then
        return 1
    fi
    return 0
}

# ============ 主流程：导出 + 上传 ============
process_archive() {
    local archive="$1"
    local xcarchive="" app_dir="" ipa_path=""

    case "$archive" in
        *.xcarchive)
            xcarchive="$archive"
            app_dir=$(find "$xcarchive/Products/Applications" -name "*.app" -maxdepth 1 -type d 2>/dev/null | head -1)
            if [ -z "$app_dir" ]; then
                STAGE="error"; ERROR_MSG="归档中未找到 .app（请确认主应用已正确嵌入）"
                render_monitor; log ERROR "归档中无 .app"; exit 1
            fi
            ;;
        *.app)
            app_dir="$archive"
            ;;
        *.ipa)
            ipa_path="$archive"
            local tmp; tmp=$(mktemp -d)
            unzip -q -o "$ipa_path" -d "$tmp" 2>/dev/null || true
            app_dir=$(find "$tmp/Payload" -name "*.app" -maxdepth 1 -type d 2>/dev/null | head -1)
            PGY_CLEANUP="$tmp"
            ;;
        *)
            STAGE="error"; ERROR_MSG="不支持的输入类型: $archive（仅支持 .xcarchive / .app / .ipa）"
            render_monitor; exit 1;;
    esac

    # 版本探测
    [ -z "$FINAL_VERSION" ] && [ -n "$app_dir" ] && detect_version "$app_dir"
    if [ -z "$FINAL_VERSION" ]; then
        STAGE="error"; ERROR_MSG="无法获取版本号，请用 --version 指定或检查 Info.plist"
        render_monitor; log ERROR "版本号获取失败"; exit 1
    fi

    # 构造更新描述：$version $versionTarget 换行 $updateDes
    local raw_des="$PGY_UPDATE_DESCRIPTION"
    PGY_UPDATE_DESCRIPTION="${FINAL_VERSION}${PGY_VERSION_TARGET:+ $PGY_VERSION_TARGET}"
    if [ -n "$raw_des" ]; then
        PGY_UPDATE_DESCRIPTION="${PGY_UPDATE_DESCRIPTION}"$'\n'"${raw_des}"
    fi
    # 监控页用 HTML（换行转 <br> 才能显示断行）
    UPDATE_DESCRIPTION="${PGY_UPDATE_DESCRIPTION//$'\n'/<br>}"
    log INFO "更新描述: '$PGY_UPDATE_DESCRIPTION'"

    # Debug 拦截（仅 Flutter）
    if [ -n "$app_dir" ] && ! check_debug "$app_dir"; then
        STAGE="error"
        ERROR_MSG="检测到 Debug / Profile 模式构建，已拦截上传。<br>iOS 14+ 无法从主屏幕启动 Debug 包。<br>请使用 Product → Archive（Release）构建。"
        render_monitor; log ERROR "Debug 模式拦截"; exit 1
    fi

    # 导出 IPA
    if [ -n "$xcarchive" ]; then
        STAGE="exporting"; STAGE_ICON="📦"; STAGE_TITLE="正在导出 IPA 包"
        STAGE_DETAIL="使用 xcodebuild -exportArchive（与 Distribute App 同款流程）..."; render_monitor

        local exp_dir; exp_dir=$(mktemp -d)
        local exp_opt="$exp_dir/exportOptions.plist"
        local team_key=""
        [ -n "$PGY_TEAM_ID" ] && team_key=$'\n    <key>teamID</key><string>'"$PGY_TEAM_ID"'</string>'
        cat > "$exp_opt" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>$PGY_METHOD</string>$team_key
    <key>signingStyle</key><string>automatic</string>
    <key>stripSwiftSymbols</key><true/>
    <key>uploadBitcode</key><false/>
    <key>uploadSymbols</key><true/>
</dict>
</plist>
EOF
        xcodebuild -exportArchive \
            -archivePath "$xcarchive" \
            -exportPath "$exp_dir" \
            -exportOptionsPlist "$exp_opt" \
            -allowProvisioningUpdates \
            -quiet 2>>"$LOG_FILE" &
        local pid=$!; local el=0
        while kill -0 "$pid" 2>/dev/null; do
            sleep 1; el=$((el+1))
            STAGE_DETAIL="导出中...（已耗时 ${el} 秒，通常 60-120 秒）"; render_monitor
        done
        if ! wait "$pid"; then
            STAGE="error"; ERROR_MSG="xcodebuild -exportArchive 失败，详见日志"
            render_monitor; rm -rf "$exp_dir"; exit 1
        fi
        ipa_path=$(find "$exp_dir" -name "*.ipa" -type f 2>/dev/null | head -1)
        if [ -z "$ipa_path" ] || [ ! -f "$ipa_path" ]; then
            STAGE="error"; ERROR_MSG="导出完成但未找到 .ipa 文件"
            render_monitor; rm -rf "$exp_dir"; exit 1
        fi
        PGY_CLEANUP="$exp_dir"
        log INFO "IPA 导出成功: $ipa_path ($(du -sh "$ipa_path" | cut -f1))"
    elif [ -n "$app_dir" ] && [ -z "$ipa_path" ]; then
        STAGE="exporting"; STAGE_ICON="📦"; STAGE_TITLE="正在打包 IPA"
        STAGE_DETAIL="从 .app 生成 IPA..."; render_monitor
        local wd; wd=$(mktemp -d); mkdir -p "$wd/Payload"
        ditto "$app_dir" "$wd/Payload/$(basename "$app_dir")"
        ipa_path="$wd/$(basename "$app_dir" .app).ipa"
        ( cd "$wd" && zip -r -q -y -X "$ipa_path" Payload )
        PGY_CLEANUP="$wd"
    fi

    if [ -z "$ipa_path" ] || [ ! -f "$ipa_path" ]; then
        STAGE="error"; ERROR_MSG="未获得可上传的 IPA 文件"
        render_monitor; exit 1
    fi

    # 上传
    STAGE="uploading"; STAGE_ICON="☁️"; STAGE_TITLE="正在上传到蒲公英"
    STAGE_DETAIL="IPA 大小: $(du -sh "$ipa_path" | cut -f1)"; render_monitor
    log INFO "开始上传到蒲公英..."

    local resp
    resp=$(curl -s --connect-timeout 30 --max-time 600 \
        -F "file=@$ipa_path" \
        -F "uKey=$PGY_USER_KEY" \
        -F "_api_key=$PGY_API_KEY" \
        -F "updateDescription=$PGY_UPDATE_DESCRIPTION" \
        -F "buildUpdateDescription=$PGY_VERSION_TARGET" \
        -F "buildVersion=$FINAL_VERSION" \
        https://www.pgyer.com/apiv2/app/upload 2>>"$LOG_FILE")

    local code dl qrlink
    code=$(echo "$resp" | jq -r '.code // empty' 2>/dev/null)
    dl=$(echo "$resp" | jq -r '.data.buildShortcutUrl // empty' 2>/dev/null)
    qrlink=$(echo "$resp" | jq -r '.data.buildQRCodeURL // empty' 2>/dev/null)

    if [ "$code" = "0" ] && [ -n "$dl" ]; then
        STAGE="success"; DOWNLOAD_URL="$dl"
        local qf="${TMPDIR:-/tmp}/pgy_qr_${TS}.png"; QR_B64=""
        if curl -sL --max-time 30 -o "$qf" "$qrlink" 2>/dev/null && [ -s "$qf" ]; then
            QR_B64=$(base64 -i "$qf" 2>/dev/null | tr -d '\n')
        fi
        rm -f "$qf" 2>/dev/null || true
        render_monitor
        log INFO "🎉 上传成功: https://www.pgyer.com/$dl"
    else
        local msg; msg=$(echo "$resp" | jq -r '.message // "未知错误（可能网络问题或 API 参数错误）"' 2>/dev/null)
        STAGE="error"; ERROR_MSG="${msg}<br><br><small>$(date '+%H:%M:%S')</small>"
        render_monitor
        log ERROR "上传失败: $msg"
    fi
}

# ═══════════════════════════════════════════════════════════════
#  多策略归档查找器
# ═══════════════════════════════════════════════════════════════
#
# 关键时序事实：
#   runOnlyForDeploymentPostprocessing=1 意味着本脚本在 Archive **完成后**才执行。
#   .xcarchive 已经存在于磁盘上。我们不需要"等待模式"——需要的是可靠地找到它。
#
# Xcode 不保证设置 $ARCHIVE_PATH（尤其 Flutter 项目），且 Run Script 的 sandbox 可能
# 限制 find 的文件系统访问。因此采用多策略回退查找。
#
PGY_ARCHIVE_GRACE="${PGY_ARCHIVE_GRACE:-1800}"
ARCHIVE_DIR="${HOME:-/Users/zuzhuli}/Library/Developer/Xcode/Archives"

find_xcarchive() {
    local cand=""
    log INFO "[查找] ARCHIVE_DIR='$ARCHIVE_DIR' HOME='$HOME' grace=${PGY_ARCHIVE_GRACE}s"

    # ── 策略 1：find -mmin（时间窗口内）──
    if [ -d "$ARCHIVE_DIR" ]; then
        cand=$(find "$ARCHIVE_DIR" \
            -name "*.xcarchive" -type d -mmin "-$((PGY_ARCHIVE_GRACE / 60))" 2>/dev/null \
            | sort | tail -1) || true
    fi
    log INFO "[查找] 策略1(find -mmin): cand='${cand:-<无>}'"

    # ── 策略 2：ls -1t 取最新（不限时间，覆盖 find 被沙箱限制）──
    if [ -z "$cand" ] && [ -d "$ARCHIVE_DIR" ]; then
        # Xcode archive 按日期组织：YYYY-MM-DD/name.xcarchive
        cand=$(ls -1dt "$ARCHIVE_DIR"/*/*.xcarchive 2>/dev/null | head -1) || true
    fi
    log INFO "[查找] 策略2(ls -1t): cand='${cand:-<无>}'"

    # ── 策略 3：glob 当日目录──
    if [ -z "$cand" ] && [ -d "$ARCHIVE_DIR" ]; then
        local today_dir
        today_dir=$(date +%Y-%m-%d)
        if [ -d "$ARCHIVE_DIR/$today_dir" ]; then
            cand=$(ls -1dt "$ARCHIVE_DIR/$today_dir"/*.xcarchive 2>/dev/null | head -1) || true
        fi
    fi
    log INFO "[查找] 策略3(当日目录): cand='${cand:-<无>}'"

    # ── 验证候选结果（用 glob 而非 find：find 在 Xcode sandbox 下可能被限制）──
    if [ -n "$cand" ] && [ -d "$cand" ]; then
        if [ -d "$cand/Products/Applications" ]; then
            local app_count=0
            shopt -s nullglob
            local apps=("$cand/Products/Applications"/*.app)
            app_count=${#apps[@]}
            shopt -u nullglob
            if [ "$app_count" -ge 1 ]; then
                echo "$cand"
                return 0
            fi
            log INFO "[查找] 候选存在但 Products/Applications 无 .app（app_count=$app_count），跳过"
        else
            log INFO "[查找] 候选缺少 Products/Applications: '$cand'"
        fi
    elif [ -n "$cand" ]; then
        log INFO "[查找] 候选路径无效: '$cand'"
    fi

    return 0
}

# ============ 主入口（非 UPLOAD_MODE 时执行） ============
# UPLOAD_MODE=1 时跳过此段，直接进入下方的 --_upload 处理块
if [ "$UPLOAD_MODE" != "1" ]; then
ARCHIVE_INPUT=""
if [ -n "$ARCHIVE_ARG" ] && [ -e "$ARCHIVE_ARG" ]; then
    # --archive 传了有效路径 → 直接模式
    ARCHIVE_INPUT="$ARCHIVE_ARG"
elif [ -n "$ARCHIVE_PATH" ] && [ -e "$ARCHIVE_PATH" ]; then
    # 环境变量 $ARCHIVE_PATH 有效 → 直接模式
    ARCHIVE_INPUT="$ARCHIVE_PATH"
fi

# runOnlyForDeploymentPostprocessing=1 → 本脚本在 Archive 完成后才执行。
# 因此 .xcarchive 通常已存在：先多策略直接发现；失败则主进程内短轮询重试（兜底 IO 延迟）。
# 不再使用后台 nohup --_wait 子进程（旧实现缺失对应处理块，会递归 fork 且永不推进），
# 超时即给出明确错误，而不是永久卡在「等待 Xcode Archive 完成」页。
if [ -z "$ARCHIVE_INPUT" ]; then
    log INFO "未收到有效的 archive 路径（--archive='${ARCHIVE_ARG:-<未传>}' ARCHIVE_PATH='${ARCHIVE_PATH:-<未设置>}'），启动多策略查找..."
    ARCHIVE_INPUT=$(find_xcarchive) || true
    waited=0
    while [ -z "$ARCHIVE_INPUT" ] && [ "$waited" -lt "$PGY_MAX_WAIT" ]; do
        sleep 5
        waited=$((waited + 5))
        log INFO "轮询重试发现归档（已等待 ${waited}s / ${PGY_MAX_WAIT}s）..."
        ARCHIVE_INPUT=$(find_xcarchive) || true
    done
fi

if [ -n "$ARCHIVE_INPUT" ]; then
    # 归档已找到 → 渲染初始监控页，fork 后台上传进程后立即退出
    # 这样 Run Script 阶段秒退，Xcode Archive 立即完成（弹出成功弹窗），
    # 导出 IPA + 上传蒲公英在后台独立执行，通过监控页跟踪进度。
    log INFO "使用 archive: $ARCHIVE_INPUT → fork 后台上传"
    STAGE="waiting"; STAGE_ICON="⏳"; STAGE_TITLE="准备上传"; STAGE_DETAIL="正在启动后台上传..."
    render_monitor
    open "$MONITOR_HTML" 2>/dev/null || true
    # 使用 nohup 后台执行，彻底脱离主进程（Xcode Run Script 退出后子进程继续运行）
    # 关键：传入主进程的 MONITOR_HTML 和 LOG_FILE 路径，子进程复用（否则子进程 $$ 不同会写到新文件，浏览器看不到更新）
    SELF_PATH="$SCRIPT_DIR/$(basename "$0")"
    nohup bash "$SELF_PATH" \
        --_upload \
        --archive "$ARCHIVE_INPUT" \
        --config "${CONFIG_FILE:-}" \
        --monitor-path "$MONITOR_HTML" \
        --log-path "$LOG_FILE" \
        ${PGY_VERSION_OVERRIDE:+--version "$PGY_VERSION_OVERRIDE"} \
        ${PGY_VERSION_TARGET:+--target "$PGY_VERSION_TARGET"} \
        ${PGY_UPDATE_DESCRIPTION:+--notes "$PGY_UPDATE_DESCRIPTION"} \
        ${PGY_METHOD:+--method "$PGY_METHOD"} \
        ${PGY_HISTORY_FILE:+--history "$PGY_HISTORY_FILE"} \
        >> "$LOG_FILE" 2>&1 &
    BG_PID=$!
    log INFO "后台上传进程已启动 (PID=$BG_PID)，Run Script 即将退出"
    exit 0
else
    # 所有策略 + 重试均未找到 → 明确报错，避免永久卡在「等待」页
    log ERROR "在 ${PGY_MAX_WAIT}s 内未能通过任何策略找到 .xcarchive（ARCHIVE_DIR='$ARCHIVE_DIR'）。请确认 Xcode 已成功 Archive，或手动指定 --archive 路径。"
    STAGE="error"; STAGE_ICON="❌"; STAGE_TITLE="未找到归档"
    STAGE_DETAIL="在 ${PGY_MAX_WAIT}s 内未能发现 .xcarchive。<br>请确认 Xcode 已成功 Archive，或在 Run Script 中显式传入 --archive 路径。<br><small>ARCHIVE_DIR=$ARCHIVE_DIR</small>"
    render_monitor
    open "$MONITOR_HTML" 2>/dev/null || true
    exit 1
fi   # ← 结束 if [ -n "$ARCHIVE_INPUT" ]
fi   # ← 结束 UPLOAD_MODE != 1 守护（主入口段）

# ============ --_upload 后台上传入口 ============
# 由主进程通过 nohup 调用，独立执行完整导出+上传流程。
# UPLOAD_MODE 标志在参数解析时设置（--_upload 参数已被正常消费）。
if [ "$UPLOAD_MODE" = "1" ]; then
    log INFO "====== 后台上传进程启动 ======"
    log INFO "后台上传: MONITOR_HTML='$MONITOR_HTML' LOG_FILE='$LOG_FILE' ARCHIVE_ARG='$ARCHIVE_ARG'"
    # 确认 archive 路径
    if [ -z "$ARCHIVE_ARG" ] || [ ! -e "$ARCHIVE_ARG" ]; then
        log ERROR "后台上传: 无效的 archive 路径 '${ARCHIVE_ARG:-<空>}'"
        STAGE="error"; STAGE_ICON="❌"; STAGE_TITLE="上传失败"
        STAGE_DETAIL="后台上传进程收到无效 archive 路径"
        render_monitor; exit 1
    fi
    # 执行完整流程
    prepare_upload
    process_archive "$ARCHIVE_ARG"
    log INFO "====== 后台上传进程结束 ======"
    exit 0
fi
