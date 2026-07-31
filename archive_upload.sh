#!/bin/bash
# ==============================================================================
#  archive_upload.sh — 统一 CLI 入口：Archive（xcodebuild）→ 导出 IPA → 上传蒲公英
#
#  设计目的：让 AI 工具（WorkBuddy / Claude Code / Cursor / CI）能用一条命令
#            准确触发「Archive 并上传蒲公英」，无需手动点 Xcode GUI。
#
#  行为：
#    1. 前置检查（xcodebuild / scheme / 蒲公英凭证）
#    2. 若未传入 --archive，则自动执行 `xcodebuild archive` 生成 .xcarchive
#       （全自动，零 GUI 依赖）；传入 --archive 则跳过此步
#    3. 同步调用 pgy_upload.sh（--_upload --json），由它完成导出+上传
#    4. 将 pgy_upload.sh 的 JSON 结果原样输出到 stdout，并透传退出码
#
#  输出约定（供 AI 解析）：
#    - stdout：仅 pgy_upload.sh 的结构化 JSON 一行（archive 失败时本脚本也输出 JSON）
#    - xcodebuild / 中间日志全部走 stderr，不污染 stdout
#    - 退出码：0=成功(success)或按设计跳过(skipped)，1=任意失败(error)
#
#  前置条件：
#    - macOS + Xcode 命令行工具（xcodebuild 可用）
#    - 有效的签名配置（development 证书 + 自动签名，或 provisioning profile）
#    - ios/Scripts/archive-pgy-config/pgy_config.sh 已配置蒲公英凭证（gitignored）
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"            # ios/ 目录
CONFIG="${IOS_DIR}/Scripts/archive-pgy-config/pgy_config.sh"

# ---- 默认参数（可被命令行覆盖）----
PGY_TARGET=""
PGY_VERSION=""
PGY_NOTES=""
PGY_METHOD="development"
PGY_BUNDLE_ID=""
ARCHIVE_ARG=""
DRY_RUN=0
WORKSPACE="$IOS_DIR/Runner.xcworkspace"
SCHEME="Runner"
CONFIGURATION="Release"

# ---- 参数解析 ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)       PGY_TARGET="$2"; shift 2;;
        --version)      PGY_VERSION="$2"; shift 2;;
        --notes)        PGY_NOTES="$2"; shift 2;;
        --method)       PGY_METHOD="$2"; shift 2;;
        --bundle-id)    PGY_BUNDLE_ID="$2"; shift 2;;
        --config)       CONFIG="$2"; shift 2;;
        --archive)      ARCHIVE_ARG="$2"; shift 2;;
        --workspace)    WORKSPACE="$2"; shift 2;;
        --scheme)       SCHEME="$2"; shift 2;;
        --configuration) CONFIGURATION="$2"; shift 2;;
        --dry-run)      DRY_RUN=1; shift;;
        -h|--help)
            sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0;;
        *) echo "未知参数: $1" >&2; exit 1;;
    esac
done

# ---- 加载配置（拿蒲公英凭证 + 默认 Bundle ID）----
if [ -f "$CONFIG" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG"
fi
# 未显式传 --bundle-id 时，使用 config 中的默认目标 Bundle ID
[ -z "$PGY_BUNDLE_ID" ] && PGY_BUNDLE_ID="${TARGET_BUNDLE_ID:-}"

emit_json() {
    # 失败时由本脚本直接输出 JSON，保持 AI 接口一致
    local msg="$1"
    python3 - "$msg" <<'PYEOF'
import json, sys
print(json.dumps({"status": "error", "error": sys.argv[1]}, ensure_ascii=False))
PYEOF
}

# ---- 前置检查 ----
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "ERROR: xcodebuild 未找到，请安装 Xcode 命令行工具（xcode-select --install）。" >&2
    emit_json "xcodebuild 未安装"
    exit 1
fi
if [ ! -f "$CONFIG" ]; then
    echo "ERROR: 蒲公英配置文件不存在: $CONFIG" >&2
    emit_json "蒲公英配置文件缺失: $CONFIG"
    exit 1
fi
if [ -z "${PGY_USER_KEY:-}" ] || [ -z "${PGY_API_KEY:-}" ]; then
    echo "ERROR: 未配置蒲公英凭证（PGY_USER_KEY / PGY_API_KEY）。" >&2
    emit_json "蒲公英凭证未配置"
    exit 1
fi
if [ -z "$PGY_BUNDLE_ID" ]; then
    echo "ERROR: 未指定目标 Bundle ID（--bundle-id 或 config 中的 TARGET_BUNDLE_ID）。" >&2
    emit_json "目标 Bundle ID 未指定"
    exit 1
fi

# ---- 决定归档来源 ----
ARCHIVE_PATH=""
if [ -n "$ARCHIVE_ARG" ] && [ -e "$ARCHIVE_ARG" ]; then
    ARCHIVE_PATH="$ARCHIVE_ARG"
    echo "[archive_upload] 使用传入的归档: $ARCHIVE_PATH" >&2
else
    if [ "$DRY_RUN" = "1" ]; then
        echo "[DRY-RUN] 将执行: xcodebuild archive -workspace $WORKSPACE -scheme $SCHEME -configuration $CONFIGURATION -archivePath <tmp>/Runner.xcarchive"
        echo '{"status":"skipped","error":"dry-run 模式，未执行归档"}'
        exit 0
    fi
    ARCHIVE_TMP="$(mktemp -d)"
    ARCHIVE_PATH="$ARCHIVE_TMP/Runner.xcarchive"
    echo "[archive_upload] 开始 xcodebuild archive（自动生成 .xcarchive）..." >&2
    if ! xcodebuild archive \
            -workspace "$WORKSPACE" \
            -scheme "$SCHEME" \
            -configuration "$CONFIGURATION" \
            -archivePath "$ARCHIVE_PATH" \
            -allowProvisioningUpdates \
            -quiet >&2; then
        echo "ERROR: xcodebuild archive 失败，详见上方 Xcode 输出。" >&2
        emit_json "xcodebuild archive 失败（请检查签名/证书配置）"
        exit 1
    fi
    echo "[archive_upload] 归档生成成功: $ARCHIVE_PATH" >&2
fi

# ---- 调用 pgy_upload.sh（同步，--_upload + --json）----
PGY_ARGS=(--_upload --archive "$ARCHIVE_PATH" --json --config "$CONFIG")
[ -n "$PGY_TARGET" ]    && PGY_ARGS+=(--target "$PGY_TARGET")
[ -n "$PGY_VERSION" ]   && PGY_ARGS+=(--version "$PGY_VERSION")
[ -n "$PGY_NOTES" ]     && PGY_ARGS+=(--notes "$PGY_NOTES")
[ -n "$PGY_METHOD" ]    && PGY_ARGS+=(--method "$PGY_METHOD")
[ -n "$PGY_BUNDLE_ID" ] && PGY_ARGS+=(--bundle-id "$PGY_BUNDLE_ID")

# 直接执行（同步）；pgy_upload.sh 的 --json 输出到 stdout，退出码为其结果
bash "$SCRIPT_DIR/pgy_upload.sh" "${PGY_ARGS[@]}"
