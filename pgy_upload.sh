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
HISTORY_PARSE_ERROR=0

# ============ 日志 ============
# 注意：echo 到 stderr（>&2），避免在 $(...) 捕获时污染函数返回值
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg" >&2
}

# ============ 命令行参数 ============
UPLOAD_MODE=0
PGY_JSON=0
ARCHIVE_ARG=""
# 由主进程传入的路径（后台上传模式时复用，不基于子进程 $$ 重新生成）
INHERITED_MONITOR_HTML=""
INHERITED_LOG_FILE=""
# 目标 Bundle ID（用于校验找到的归档是否属于当前项目，防止上传其他 APP 的包）
TARGET_BUNDLE_ID=""
# find_xcarchive 的返回值（避免命令替换子 shell 导致全局标志位丢失）
FOUND_ARCHIVE=""
FIND_ALL_REJECTED_BUNDLE=0
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
        --bundle-id)     CLI_BUNDLE_ID="$2"; shift 2;;             # 目标 Bundle ID（归档身份校验，source 配置后应用以覆盖配置默认值）
        --json)         PGY_JSON=1; shift;;                           # 结构化 JSON 输出（供 AI 工具解析）
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

# CLI 覆盖配置默认值：确保命令行 --bundle-id 优先级高于配置文件，
# 也高于外部环境可能注入的 TARGET_BUNDLE_ID（如某些 shell 沙箱注入的错误值）。
# 配置文件本身已无条件赋值（项目身份真相源），此处仅在显式传参时覆盖。
if [ -n "$CLI_BUNDLE_ID" ]; then
    TARGET_BUNDLE_ID="$CLI_BUNDLE_ID"
fi

# ============ 依赖检查 ============
if ! command -v jq &> /dev/null; then
    echo "[ERROR] 未找到 jq，请先安装: brew install jq" >&2
    exit 1
fi

# ============ 读取 PGYUploadHistory.json（可选的项目级控制文件） ============
load_history() {
    [ -f "$PGY_HISTORY_FILE" ] || { log INFO "未找到 PGYUploadHistory.json（可选控制文件），跳过历史控制"; return 0; }
    if ! jq empty "$PGY_HISTORY_FILE" 2>/dev/null; then
        log ERROR "PGYUploadHistory.json 格式错误（非合法 JSON），已忽略"
        # 标记：history 文件存在但解析失败，prepare_upload 中据此决定是否阻断上传
        HISTORY_PARSE_ERROR=1
        return 0
    fi
    local vt ver des
    vt=$(jq -r '.[0].versionTarget // empty' "$PGY_HISTORY_FILE" 2>/dev/null)
    ver=$(jq -r '.[0].version // empty' "$PGY_HISTORY_FILE" 2>/dev/null)
    des=$(jq -r '.[0].updateDes // empty' "$PGY_HISTORY_FILE" 2>/dev/null)
    log INFO "PGYUploadHistory.json: versionTarget='${vt:-<空>}' version='${ver:-<空>}' updateDes='${des:-<空>}'"
    if [ -z "$vt" ]; then
        # history 未提供 versionTarget：仅当命令行也未指定 --target 时才跳过上传。
        # 这样 AI 工具触发时显式传 --target 即可绕过空 history 正常上传。
        if [ -z "$PGY_VERSION_TARGET" ]; then
            SKIP_UPLOAD=1
        fi
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
        RESULT_STATUS="skipped"; STAGE="success"
        finish 0
    fi
    # history 文件存在但 JSON 格式错误 → 关键变量（版本目标/描述）全部缺失
    # 若此时 PGY_VERSION_TARGET 仍未被其他途径设置，阻断上传并给出明确提示
    if [ "$HISTORY_PARSE_ERROR" = "1" ] && [ -z "$PGY_VERSION_TARGET" ]; then
        log ERROR "PGYUploadHistory.json 格式错误且无其他版本目标来源，终止上传"
        STAGE="error"; STAGE_ICON="❌"; STAGE_TITLE="配置文件格式错误"
        STAGE_DETAIL="PGYUploadHistory.json 不是合法的 JSON 格式。<br>请检查文件末尾是否有多余字符（如 <code>=</code>），修复后重新 Archive。<br><small>原始错误：jq 无法解析该文件</small>"
        render_monitor; open "$MONITOR_HTML" 2>/dev/null || true
        finish 1
    fi
    if [ -z "$PGY_USER_KEY" ] || [ -z "$PGY_API_KEY" ]; then
        echo "[ERROR] 未配置 Pgyer 凭证。请在 pgy_config.sh 中设置 PGY_USER_KEY / PGY_API_KEY，或导出为环境变量。" >&2
        # 凭证缺失 → 上传无法进行，但 Archive 已成功，不阻塞 Build
        STAGE="error"; STAGE_ICON="❌"; STAGE_TITLE="上传失败"
        STAGE_DETAIL="未配置蒲公英凭证（PGY_USER_KEY / PGY_API_KEY）。<br>请在 pgy_config.sh 中配置（位于项目配置目录 / \$HOME / 子模块目录，或用 --config 指定路径）。"
        render_monitor; open "$MONITOR_HTML" 2>/dev/null || true
        finish 1
    fi
}

# ============ 结构化结果输出（--json 模式，供 AI 工具解析） ============
RESULT_STATUS=""   # success | error | skipped（优先于 STAGE 推导）
emit_result_json() {
    local status="$RESULT_STATUS"
    [ -z "$status" ] && { [ "$STAGE" = "success" ] && status="success" || status="error"; }
    python3 - "$status" "$ERROR_MSG" "$FINAL_VERSION" "$PGY_VERSION_TARGET" \
        "$PGY_UPDATE_DESCRIPTION" "$DOWNLOAD_URL" "$ARCHIVE_ARG" "${ipa_path:-}" \
        "$LOG_FILE" "$MONITOR_HTML" <<'PYEOF'
import json, sys
status, err, ver, vtarget, udes, dl, arch, ipa, logf, mon = sys.argv[1:11]
dl_url = ("https://www.pgyer.com/" + dl) if dl else None
print(json.dumps({
    "status": status,
    "version": ver or None,
    "versionTarget": vtarget or None,
    "updateDescription": udes or None,
    "downloadUrl": dl_url,
    "archivePath": arch or None,
    "ipaPath": ipa or None,
    "logPath": logf or None,
    "monitorPath": mon or None,
    "error": (err or None) if status != "success" else None,
}, ensure_ascii=False))
PYEOF
}
# 统一收口：JSON 模式打印结果并按 code 退出；非 JSON（Xcode）场景永远 exit 0 不阻塞 Build
finish() {
    local code=$1
    if [ "$PGY_JSON" = "1" ]; then
        emit_result_json
        exit "$code"
    fi
    exit 0
}

# ============ 清理 ============
# 同时清理 copy 方案产生的临时归档副本（仅匹配 $TMPDIR/pgy_archive_*.xcarchive，绝不触碰真实 Xcode 归档）
trap 'rm -rf "$PGY_CLEANUP" 2>/dev/null || true; case "$ARCHIVE_ARG" in *"/pgy_archive_"*.xcarchive) rm -rf "$ARCHIVE_ARG" 2>/dev/null || true;; esac' EXIT

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
  <div class="info-item"><span class="label">描述</span><span class="value">$UPDATE_DESCRIPTION</span></div>
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
<div class="info-grid">
  <div class="info-item"><span class="label">版本号</span><span class="value">$FINAL_VERSION</span></div>
  <div class="info-item"><span class="label">版本目标</span><span class="value">$PGY_VERSION_TARGET</span></div>
  <div class="info-item"><span class="label">更新描述</span><span class="value">$UPDATE_DESCRIPTION</span></div>
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
                render_monitor; log ERROR "归档中无 .app"; finish 1
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
            render_monitor; finish 1;;
    esac

    # ── Bundle ID 身份校验（防止上传其他项目的包；--_upload 直接传 --archive 时也生效）──
    if [ -n "$TARGET_BUNDLE_ID" ] && [ -n "$app_dir" ] && [ -f "$app_dir/Info.plist" ]; then
        local actual_bid
        actual_bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_dir/Info.plist" 2>/dev/null || true)
        if [ "$actual_bid" != "$TARGET_BUNDLE_ID" ]; then
            STAGE="error"
            ERROR_MSG="Bundle ID 校验失败：期望 <code>$TARGET_BUNDLE_ID</code>，实际 <code>$actual_bid</code>。<br>已拦截上传，避免误传其他项目的安装包。"
            render_monitor; log ERROR "Bundle ID 不匹配 ($actual_bid != $TARGET_BUNDLE_ID)"
            finish 1
        fi
    fi

    # 版本探测
    if [ -z "$FINAL_VERSION" ] && [ -n "$app_dir" ]; then
        detect_version "$app_dir" || true   # 失败不阻断（set -e 下需 ||true），后续统一 finish
    fi
    if [ -z "$FINAL_VERSION" ]; then
        STAGE="error"; ERROR_MSG="无法获取版本号，请用 --version 指定或检查 Info.plist"
        render_monitor; log ERROR "版本号获取失败"; finish 1
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
        render_monitor; log ERROR "Debug 模式拦截"; finish 1
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
            -quiet >>"$LOG_FILE" 2>&1 &
        local pid=$!; local el=0
        while kill -0 "$pid" 2>/dev/null; do
            sleep 1; el=$((el+1))
            STAGE_DETAIL="导出中...（已耗时 ${el} 秒，通常 60-120 秒）"; render_monitor
        done
        if ! wait "$pid"; then
            STAGE="error"; ERROR_MSG="xcodebuild -exportArchive 失败，详见日志"
            render_monitor; rm -rf "$exp_dir"; finish 1
        fi
        ipa_path=$(find "$exp_dir" -name "*.ipa" -type f 2>/dev/null | head -1)
        if [ -z "$ipa_path" ] || [ ! -f "$ipa_path" ]; then
            STAGE="error"; ERROR_MSG="导出完成但未找到 .ipa 文件"
            render_monitor; rm -rf "$exp_dir"; finish 1
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
        render_monitor; finish 1
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
        -F "buildUpdateDescription=$PGY_UPDATE_DESCRIPTION" \
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
    log INFO "[查找] ARCHIVE_DIR='$ARCHIVE_DIR' HOME='$HOME' grace=${PGY_ARCHIVE_GRACE}s TARGET_BUNDLE_ID='${TARGET_BUNDLE_ID:-<未设置>}'"

    # ── 收集候选列表（三策略合并去重）──
    local candidates=()
    if [ -d "$ARCHIVE_DIR" ]; then
        # 策略 1：find -mmin（时间窗口内）
        local s1
        s1=$(find "$ARCHIVE_DIR" \
            -name "*.xcarchive" -type d -mmin "-$((PGY_ARCHIVE_GRACE / 60))" 2>/dev/null \
            | sort) || true
        if [ -n "$s1" ]; then
            while IFS= read -r line; do [ -n "$line" ] && candidates+=("$line"); done <<< "$s1"
        fi
        log INFO "[查找] 策略1(find -mmin) 找到 ${#candidates[@]} 个候选"

        # 策略 2：ls -1t 全量最新（覆盖 find 被沙箱限制的情况）
        local s2
        s2=$(ls -1dt "$ARCHIVE_DIR"/*/*.xcarchive 2>/dev/null) || true
        if [ -n "$s2" ]; then
            while IFS= read -r line; do
                [ -n "$line" ] && ! [[ " ${candidates[*]} " =~ " ${line} " ]] && candidates+=("$line")
            done <<< "$s2"
        fi
        log INFO "[查找] 策略2(ls-1t) 后共 ${#candidates[@]} 个候选"

        # 策略 3：当日目录 glob
        if [ ${#candidates[@]} -eq 0 ]; then
            local today_dir
            today_dir=$(date +%Y-%m-%d)
            if [ -d "$ARCHIVE_DIR/$today_dir" ]; then
                local s3
                s3=$(ls -1dt "$ARCHIVE_DIR/$today_dir"/*.xcarchive 2>/dev/null) || true
                if [ -n "$s3" ]; then
                    while IFS= read -r line; do [ -n "$line" ] && candidates+=("$line"); done <<< "$s3"
                fi
            fi
            log INFO "[查找] 策略3(当日目录) 后共 ${#candidates[@]} 个候选"
        fi
    fi

    if [ ${#candidates[@]} -eq 0 ]; then
        log INFO "[查找] 所有策略均未找到归档"
        return 0
    fi

    # ── 逐个验证候选（含项目身份校验）──
    # found_any_valid: 是否至少找到一个含 .app 的有效归档（用于区分"还没生成"与"生成了但都不是我们的"）
    # FIND_ALL_REJECTED_BUNDLE: 找到有效归档但全部被 Bundle ID 校验拒绝（疑似配置错误）→ 主循环据此快速失败
    local found_any_valid=0
    FOUND_ARCHIVE=""
    FIND_ALL_REJECTED_BUNDLE=0
    for cand in "${candidates[@]}"; do
        log INFO "[查找] 验证候选: '$cand'"

        # 基本存在性检查
        if [ ! -d "$cand" ]; then
            log INFO "[查找] 跳过：路径不存在"
            continue
        fi
        if [ ! -d "$cand/Products/Applications" ]; then
            log INFO "[查找] 跳过：缺少 Products/Applications"
            continue
        fi

        # 检查 .app 存在
        shopt -s nullglob
        local apps=("$cand/Products/Applications"/*.app)
        shopt -u nullglob
        if [ ${#apps[@]} -eq 0 ]; then
            log INFO "[查找] 跳过：Products/Applications 下无 .app"
            continue
        fi
        found_any_valid=1

        # ── 项目身份校验（核心安全检查）──
        if [ -n "$TARGET_BUNDLE_ID" ]; then
            local matched=0
            for app in "${apps[@]}"; do
                local app_bid
                app_bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Info.plist" 2>/dev/null) || true
                if [ "$app_bid" = "$TARGET_BUNDLE_ID" ]; then
                    matched=1
                    break
                fi
            done
            if [ "$matched" -ne 1 ]; then
                local first_app_bids=""
                for app in "${apps[@]}"; do
                    local bid
                    bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Info.plist" 2>/dev/null) || true
                    first_app_bids="${first_app_bids}${bid} "
                done
                log INFO "[查找] ⚠️ 跳过：Bundle ID 不匹配（期望 '${TARGET_BUNDLE_ID}'，实际: ${first_app_bids:-<无法读取>}）— 可能是其他项目的归档"
                if [ "$found_any_valid" -eq 1 ]; then
                    FIND_ALL_REJECTED_BUNDLE=1
                fi
                continue
            fi
            log INFO "[查找] ✅ Bundle ID 匹配: '$TARGET_BUNDLE_ID'"
        else
            log INFO "[查找] ⚠️ 未设置 TARGET_BUNDLE_ID，跳过身份校验（建议通过 --bundle-id 或配置文件指定）"
        fi

        # 通过所有校验 → 写入全局变量返回（避免命令替换子 shell 导致标志位丢失）
        FOUND_ARCHIVE="$cand"
        return 0
    done

    # 所有候选均未通过校验
    log INFO "[查找] ${#candidates[@]} 个候选全部未通过校验（可能都不是当前项目的归档）"
    return 0
}

# 归档身份校验失败（找到有效归档但 Bundle ID 全部不匹配）→ 快速失败
# 避免一直重试直到超时，也避免任何误传其他 APP 安装包的可能
#
# ⚠️ 重要：本脚本是 runOnlyForDeploymentPostprocessing=1 的 Run Script，
#   在 Archive 成功后才执行。上传失败不应导致 Xcode 报 "Build Failed"，
#   因此所有"上传相关失败"统一 exit 0，错误通过监控页传达。
bundle_id_fatal() {
    log ERROR "找到的归档 Bundle ID 均与 TARGET_BUNDLE_ID 不匹配，疑似配置错误。终止上传以避免误传其他项目的安装包。"
    STAGE="error"; STAGE_ICON="❌"; STAGE_TITLE="归档身份校验失败"
    STAGE_DETAIL="找到的归档 Bundle ID 与配置的 TARGET_BUNDLE_ID 均不匹配。<br>请检查 pgy_config.sh 中的 TARGET_BUNDLE_ID 是否正确（当前期望: ${TARGET_BUNDLE_ID}）。<br><small>已拒绝上传，避免误传其他 APP 的安装包。</small>"
    render_monitor
    open "$MONITOR_HTML" 2>/dev/null || true
    exit 0
}

# ============ 主入口（非 UPLOAD_MODE 时执行） ============
# UPLOAD_MODE=1 时跳过此段，直接进入下方的 --_upload 处理块
if [ "$UPLOAD_MODE" != "1" ]; then
SRC_ARCHIVE=""
if [ -n "$ARCHIVE_ARG" ] && [ -e "$ARCHIVE_ARG" ]; then
    # --archive 传了有效路径（PostAction 下 Xcode 注入 $ARCHIVE_PATH，或手动指定）
    SRC_ARCHIVE="$ARCHIVE_ARG"
elif [ -n "$ARCHIVE_PATH" ] && [ -e "$ARCHIVE_PATH" ]; then
    SRC_ARCHIVE="$ARCHIVE_PATH"
fi

# 若拿到 Xcode 提供的归档路径：先 copy 到固定临时路径再做后续处理。
# 这样后台上传进程持有独立副本，不受 Xcode 后续移动/清理归档目录影响，
# 也避免 Run Script 直接依赖归档目录的 IO 时序。
ARCHIVE_INPUT=""
if [ -n "$SRC_ARCHIVE" ]; then
    FIXED_TMP="$TMPDIR/pgy_archive_$$.xcarchive"
    rm -rf "$FIXED_TMP" 2>/dev/null
    if cp -R "$SRC_ARCHIVE" "$FIXED_TMP" 2>/dev/null; then
        ARCHIVE_INPUT="$FIXED_TMP"
        log INFO "使用 Xcode 提供的归档路径: $SRC_ARCHIVE → 已复制至临时路径 $FIXED_TMP"
    else
        ARCHIVE_INPUT="$SRC_ARCHIVE"
        log WARN "复制归档至临时路径失败，直接使用原路径: $SRC_ARCHIVE"
    fi
fi

# runOnlyForDeploymentPostprocessing=1 → 本脚本在 Archive 完成后才执行。
# 因此 .xcarchive 通常已存在：先多策略直接发现；失败则主进程内短轮询重试（兜底 IO 延迟）。
# 不再使用后台 nohup --_wait 子进程（旧实现缺失对应处理块，会递归 fork 且永不推进），
# 超时即给出明确错误，而不是永久卡在「等待 Xcode Archive 完成」页。
if [ -z "$ARCHIVE_INPUT" ]; then
    log INFO "未收到有效的 archive 路径（--archive='${ARCHIVE_ARG:-<未传>}' ARCHIVE_PATH='${ARCHIVE_PATH:-<未设置>}'），启动多策略查找..."
    find_xcarchive; ARCHIVE_INPUT="$FOUND_ARCHIVE"
    # 找到归档但 Bundle ID 全不匹配（配置错误）→ 立即失败，不重试、不误传
    if [ "$FIND_ALL_REJECTED_BUNDLE" = "1" ]; then
        bundle_id_fatal
    fi
    waited=0
    while [ -z "$ARCHIVE_INPUT" ] && [ "$waited" -lt "$PGY_MAX_WAIT" ]; do
        sleep 5
        waited=$((waited + 5))
        log INFO "轮询重试发现归档（已等待 ${waited}s / ${PGY_MAX_WAIT}s）..."
        find_xcarchive; ARCHIVE_INPUT="$FOUND_ARCHIVE"
        if [ "$FIND_ALL_REJECTED_BUNDLE" = "1" ]; then
            bundle_id_fatal
        fi
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
        ${TARGET_BUNDLE_ID:+--bundle-id "$TARGET_BUNDLE_ID"} \
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
    exit 0   # 上传失败不阻塞 Build（Archive 已成功，这只是后处理脚本）
fi   # ← 结束 if [ -n "$ARCHIVE_INPUT" ]
fi   # ← 结束 UPLOAD_MODE != 1 守护（主入口段）

# ============ --_upload 后台上传入口 ============
# 由主进程通过 nohup 调用，独立执行完整导出+上传流程。
# UPLOAD_MODE 标志在参数解析时设置（--_upload 参数已被正常消费）。
if [ "$UPLOAD_MODE" = "1" ]; then
    log INFO "====== 后台上传进程启动 ======"
    log INFO "后台上传: MONITOR_HTML='$MONITOR_HTML' LOG_FILE='$LOG_FILE' ARCHIVE_ARG='$ARCHIVE_ARG'"
    # 安全网：若收到 --monitor-path 但文件尚不存在（调用方未初始渲染），自动补一个
    if [ -n "$MONITOR_HTML" ] && [ ! -f "$MONITOR_HTML" ]; then
        STAGE="waiting"; STAGE_ICON="⏳"; STAGE_TITLE="准备上传"; STAGE_DETAIL="正在启动后台上传..."
        render_monitor
        open "$MONITOR_HTML" 2>/dev/null || true
    fi
    # 确认 archive 路径
    if [ -z "$ARCHIVE_ARG" ] || [ ! -e "$ARCHIVE_ARG" ]; then
        log ERROR "后台上传: 无效的 archive 路径 '${ARCHIVE_ARG:-<空>}'"
        STAGE="error"; STAGE_ICON="❌"; STAGE_TITLE="上传失败"
        STAGE_DETAIL="后台上传进程收到无效 archive 路径"
        render_monitor; exit 0
    fi
    # 执行完整流程
    prepare_upload
    process_archive "$ARCHIVE_ARG"
    # 临时归档副本的清理由全局 EXIT trap 统一处理（覆盖成功与失败路径）
    log INFO "====== 后台上传进程结束 ======"
    finish 0
fi
