#!/bin/bash
# ============================================================
# 项目级 Pgyer 配置（放在各项目的 archive-pgy-config/ 目录）
# 复制本文件为 pgy_config.sh 并填入你的值
# （pgy_config.sh 已被 .gitignore 忽略，不会进仓库）
# 也可以直接 export 为环境变量，效果相同。
# ============================================================

# 【必填】蒲公英 API 凭证
export PGY_USER_KEY="your_user_key_here"
export PGY_API_KEY="your_api_key_here"

# 【必填】控制文件路径：指向本配置文件同目录下的 PGYUploadHistory.json
#   引擎据此判断「是否上传」与「上传包信息」（versionTarget 为空 = 跳过）
CFG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PGY_HISTORY_FILE="${CFG_DIR}/PGYUploadHistory.json"

# ===== 以下均为可选 =====

# 签名 Team ID：默认自动读取 Xcode 构建期的 $DEVELOPMENT_TEAM；
# 多 team / 不稳定时在此显式指定（如 6U1A2B3C4D）
# export PGY_TEAM_ID=""

# 导出方式：development（开发/测试，默认）| ad-hoc | app-store
# export PGY_METHOD="development"

# 等待模式最长等待秒数（默认 300）
# export PGY_MAX_WAIT=300

# Debug 包拦截：auto（仅 Flutter 项目拦截，默认）| on（始终拦截）| off（不拦截）
# export PGY_DEBUG_CHECK="auto"

# 版本目标标签（显示在状态页 / 蒲公英后台，如「测试版本」「内部体验」）
# export PGY_VERSION_TARGET="测试版本"

# 默认更新说明（可用 CLI --notes 覆盖）
# export PGY_UPDATE_DESCRIPTION=""

# 【安全】目标 Bundle ID：上传前比对归档的 Bundle ID，不匹配立即拦截，
#   防止误传其他项目的安装包。强烈建议配置；留空则跳过身份校验（不拦截，
#   但失去防误传保护）。CI / AI 触发路径也支持 --bundle-id 覆盖。
# export TARGET_BUNDLE_ID="com.yourcompany.yourapp"
