#!/usr/bin/env bash
# link-skill.sh — 把 archive-pgy-uploader 子模块内的 SKILL 注册到 WorkBuddy 技能扫描目录。
#
# WorkBuddy 仅扫描：
#   - 项目级  <项目>/.workbuddy/skills/<slug>/SKILL.md
#   - 用户级  ~/.workbuddy/skills/<slug>/SKILL.md
# 不会主动扫描子模块内部，因此其他项目引入本子模块后需运行一次本脚本完成注册。
#
# 用法：
#   bash link-skill.sh                      # 注册到项目级（默认 $PWD/.workbuddy/skills/archive-pgy-uploader/）
#   bash link-skill.sh -g                   # 注册到用户级（~/.workbuddy/skills/archive-pgy-uploader/）
#   bash link-skill.sh -f                   # 目标已存在时强制覆盖
#   bash link-skill.sh --project-root <path> # 指定项目根（默认当前目录）
#
set -euo pipefail

GLOBAL=0
FORCE=0
PROJECT_ROOT="$(pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    -g|--global) GLOBAL=1; shift;;
    -f|--force) FORCE=1; shift;;
    --project-root)
      if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
        echo "错误：--project-root 需要一个路径参数" >&2
        exit 1
      fi
      PROJECT_ROOT="$2"; shift 2;;
    -h|--help)
      echo "用法: bash link-skill.sh [-g] [-f] [--project-root <path>]"
      echo "  -g               注册到用户级 ~/.workbuddy/skills/（默认项目级）"
      echo "  -f               目标已存在时强制覆盖"
      echo "  --project-root <path>  指定项目根目录（默认当前目录）"
      exit 0;;
    *) echo "未知参数: $1" >&2; exit 1;;
  esac
done

# 子模块根目录（脚本所在目录）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/skill/SKILL.md"

if [ ! -f "$SRC" ]; then
  echo "错误：找不到源 SKILL 文件: $SRC" >&2
  echo "请确认本脚本位于 archive-pgy-uploader 子模块根目录内。" >&2
  exit 1
fi

if [ "$GLOBAL" -eq 1 ]; then
  TARGET_DIR="$HOME/.workbuddy/skills/archive-pgy-uploader"
else
  TARGET_DIR="$PROJECT_ROOT/.workbuddy/skills/archive-pgy-uploader"
fi

TARGET_FILE="$TARGET_DIR/SKILL.md"

# 计算相对路径，保证 clone / 换机器后软链依然有效
if ! command -v python3 >/dev/null 2>&1; then
  echo "错误：需要 python3 来计算相对路径，请先安装。" >&2
  exit 1
fi
REL="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$SRC" "$TARGET_DIR")"

mkdir -p "$TARGET_DIR"

# 已存在处理
if [ -L "$TARGET_FILE" ]; then
  EXISTING="$(readlink "$TARGET_FILE" || true)"
  if [ "$EXISTING" = "$REL" ]; then
    echo "已注册（软链已指向相同源），无需操作: $TARGET_FILE"
    exit 0
  fi
  if [ "$FORCE" -ne 1 ]; then
    echo "目标已存在软链（指向: $EXISTING），并非本源。" >&2
    echo "如需覆盖请加 -f，或手动处理: $TARGET_FILE" >&2
    exit 1
  fi
elif [ -e "$TARGET_FILE" ]; then
  if [ "$FORCE" -ne 1 ]; then
    echo "目标已存在普通文件，如需覆盖请加 -f: $TARGET_FILE" >&2
    exit 1
  fi
fi

ln -sf "$REL" "$TARGET_FILE"
echo "已注册技能:"
echo "  目标: $TARGET_FILE"
echo "  软链: $REL"
echo "  源  : $SRC"
