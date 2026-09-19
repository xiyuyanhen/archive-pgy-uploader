#!/bin/bash
# ==============================================================================
#  sync-hosts.sh — 本机多宿主 gitlink 跟随引擎迭代（.local 名单模式）
#
#  背景：引擎被各宿主项目以 git submodule 引用，版本锚点是宿主索引里的 gitlink。
#  引擎迭代后，若不在各宿主更新 gitlink，宿主就停在旧引擎上（历史上已出现
#  xiyuScoreboard 落后 4 个 commit 的情况）。本脚本用一个「本机名单」把这件事
#  变成一条命令，并可选在引擎提交后自动执行。
#
#  名单文件（本机私有，gitignored）：<引擎>/.local/hosts.json
#    { "schema": 1, "engineRemote": "...", "hosts": [
#        { "name": "xiyuScoreboard",
#          "path": "/abs/path/to/xiyuScoreboard",
#          "submodule": "ios/Scripts/archive-pgy-uploader" } ] }
#  可用 PGY_SYNC_REGISTRY 覆盖名单路径。
#
#  同步目标（--target，默认 release）——决定「宿主该跟到哪个引擎版本」：
#    release（默认）跟「最新发布标签 v*」：标签只在**影响宿主调用行为**时才推进
#                    （判据 = STATUS.md §8.4 的升版本规则），因此文档 / 记忆类提交
#                    不会让所有宿主无谓地重新 pin。用 `--tag` 打标签。
#    local          跟「本机引擎仓 HEAD」：引擎刚提交、还没 push / 打标签也能跟上，
#                    适合引擎开发期快速联调。
#    origin         跟「origin 默认分支」：需要先 push，适合交接 / 多机 / CI。
#    （`--from-origin` 保留为 `--target origin` 的兼容别名。）
#  无论哪种目标，宿主侧都是「更新 gitlink + 本地 commit」，**不 push**（push 由人决定）。
#
#  用法：
#    bash sync-hosts.sh                    # = --check，只读报告各宿主落后情况
#    bash sync-hosts.sh --json             # 单行 JSON（供 AI/CI 解析）
#    bash sync-hosts.sh --list             # 打印本机名单
#    bash sync-hosts.sh --apply            # 同步落后宿主：更新 gitlink 并本地 commit
#                                          # （同时自动补登「半套接入」的 gitlink）
#    bash sync-hosts.sh --apply --no-commit    # 只 checkout + stage，不 commit
#    bash sync-hosts.sh --target local     # 改用本机 HEAD 为同步目标（开发期）
#    bash sync-hosts.sh --target origin    # 改用 origin 默认分支为目标
#    bash sync-hosts.sh --apply --only xiyuScoreboard,xiyu_todo_list
#    bash sync-hosts.sh --apply --dry-run  # 只打印将执行的动作
#    bash sync-hosts.sh --apply --allow-dirty  # 宿主有未提交改动时仍同步（见下）
#    bash sync-hosts.sh --apply --allow-downgrade  # 宿主 pin 比目标新时允许回落（见下）
#    bash sync-hosts.sh --add <name> <宿主路径> <子模块相对路径>
#    bash sync-hosts.sh --remove <name>
#    bash sync-hosts.sh --tag vX.Y.Z       # 判定为行为变更时，在当前 HEAD 打发布标签
#    bash sync-hosts.sh --tag vX.Y.Z --apply   # 发布 + 把各宿主推到该发布版本（推荐主路径）
#    bash sync-hosts.sh --install-hook [--auto]   # 装本机 post-commit 钩子
#                     --auto：仅在「HEAD 正好是发布标签」（= 一次发布）时自动
#                             --apply 宿主；普通提交只提示、不动宿主。
#                             不加 --auto 则始终只提示。
#    bash sync-hosts.sh --uninstall-hook
#
#  状态（hosts[].state）：
#    up-to-date            宿主 pin == 同步目标
#    outdated              pin 是目标的祖先 → --apply 更新 gitlink
#    unregistered-gitlink  半套接入：.gitmodules 已入库、目录是合法子模块 checkout，
#                          但 gitlink 未登记 → --apply 自动补登（并把版本对齐到目标）。
#                          危害静默：新克隆 update --init 不报错也不检出该子模块。
#    ahead-of-target       pin 是目标的后代（宿主已含发布版本行为）→ 良性，默认不动
#    uncommitted-gitlink   子模块已 add 但宿主从未 commit（.gitmodules+gitlink 仍在暂存区）
#    diverged / unknown-engine-commit / not-a-submodule / not-a-repo / missing
#                          需人工判断，脚本不自动处理（只在报告中给指引）
#
#  安全约束：
#    - --apply 只处理「状态 = outdated 或 unregistered-gitlink 且宿主工作区干净」的宿主；
#      其余一律跳过并说明原因。
#    - 子模块工作区有未提交改动 → 跳过该宿主（不覆盖任何人工改动）。
#    - 宿主工作区脏（未提交改动）默认也跳过；--allow-dirty 可越过该检查，因为
#      gitlink 更新走 `git add -- <子模块路径>` + `git commit -- <子模块路径>`（带 pathspec），
#      **不会**把宿主的其它改动卷进这次提交。子模块自身的脏工作区则始终拒绝。
#    - 补登 gitlink 仅对「真正的子模块 checkout」生效（判据：其 git dir 落在宿主
#      .git/modules/ 下）。vendored 副本 / 嵌套仓库不会被误补登，而是提示走 git submodule add。
#    - 宿主 pin 的 commit 比目标新（ahead-of-target）默认不动；回落需 --allow-downgrade。
#    - 引擎目录内不得出现密钥；本脚本不读、不写、不打印任何凭证。
#
#  退出码：0=全部最新或全部成功；2=存在落后 / 半套接入 / 需人工介入（仅 --check 语义）；1=执行出错。
# ==============================================================================
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${PGY_SYNC_REGISTRY:-$ENGINE_DIR/.local/hosts.json}"

MODE="check"
TARGET_SOURCE="release"   # release（默认：跟最新发布标签 v*）| local（本机 HEAD）| origin（远端默认分支）
ALLOW_DOWNGRADE=0
DO_COMMIT=1
WANT_APPLY=0
DRY_RUN=0
ALLOW_DIRTY=0
ONLY=""
QUIET=0
JSON=0
HOOK_AUTO=0
ADD_NAME=""; ADD_HOST=""; ADD_SUB=""
RM_NAME=""
TAG_NAME=""

usage() {
    # 打印文件头的注释块：从第 2 行到 `set -euo` 之前（不硬编码行号，避免改头部就错位）
    sed -n '2,/^set -euo/{/^set -euo/d;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

err() { echo "$@" >&2; }

die() {
    if [ "$JSON" = "1" ]; then
        printf '{"status":"error","engine":{"path":"%s"},"hosts":[],"error":%s}\n' \
            "$ENGINE_DIR" "$(printf '%s' "$1" | jq -Rs .)"
    else
        err "❌ $1"
    fi
    exit 1
}

say() {
    [ "$QUIET" = "1" ] && return 0
    [ "$JSON" = "1" ] && return 0
    echo "$@"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check)          MODE="check" ;;
        --apply)          MODE="apply"; WANT_APPLY=1 ;;
        --list)           MODE="list" ;;
        --json)           JSON=1 ;;
        --no-commit)      DO_COMMIT=0 ;;
        --target)         TARGET_SOURCE="${2:-}"; shift ;;
        --from-origin)    TARGET_SOURCE="origin" ;;   # 兼容别名 = --target origin
        --tag)            MODE="tag"; TAG_NAME="${2:-}"; shift ;;
        --allow-downgrade) ALLOW_DOWNGRADE=1 ;;
        --only)           ONLY="${2:-}"; shift ;;
        --dry-run)        DRY_RUN=1 ;;
        --allow-dirty)    ALLOW_DIRTY=1 ;;
        --quiet)          QUIET=1 ;;
        --add)            MODE="add"; ADD_NAME="${2:-}"; ADD_HOST="${3:-}"; ADD_SUB="${4:-}"; shift 3 ;;
        --remove)         MODE="remove"; RM_NAME="${2:-}"; shift ;;
        --install-hook)   MODE="install-hook" ;;
        --uninstall-hook) MODE="uninstall-hook" ;;
        --auto)           HOOK_AUTO=1 ;;
        -h|--help)        usage; exit 0 ;;
        *)                err "未知参数：$1"; usage >&2; exit 1 ;;
    esac
    shift
done

# --target 取值校验（放在参数解析之后，才能用 JSON 模式输出错误）
case "$TARGET_SOURCE" in
    release|local|origin) ;;
    *)
        if [ "$JSON" = "1" ]; then
            die "--target 只接受 release | local | origin（当前：${TARGET_SOURCE}）"
        fi
        err "❌ --target 只接受 release | local | origin（当前：${TARGET_SOURCE}）"
        usage >&2
        exit 1 ;;
esac

command -v jq >/dev/null 2>&1 || die "缺少 jq（硬依赖）。macOS 请执行：brew install jq"
command -v git >/dev/null 2>&1 || die "缺少 git"

ensure_registry() {
    [ -f "$REGISTRY" ] && return 0
    mkdir -p "$(dirname "$REGISTRY")"
    local remote
    remote="$(git -C "$ENGINE_DIR" remote get-url origin 2>/dev/null || true)"
    printf '{\n  "schema": 1,\n  "engineRemote": "%s",\n  "hosts": []\n}\n' "$remote" > "$REGISTRY"
    say "已创建本机名单：${REGISTRY}（当前为空，用 --add 登记项目）"
    say ""
    return 0
}

registry_names() { jq -r '.hosts[]?.name' "$REGISTRY" 2>/dev/null || true; }

# 名单中是否已有该 name。
# 用 jq 直接判定，避免 `jq | grep -q` 这种「读端提前退出 → 写端 SIGPIPE(141)」的管道：
# 在 set -o pipefail 下 141 会让条件判为「假」，重复登记反而会被放行。
registry_has() { jq -e --arg n "$1" 'any(.hosts[]?; .name == $n)' "$REGISTRY" >/dev/null 2>&1; }

# --only 是否命中某个宿主名（空 --only = 全部命中）。
# 子 shell 里做，便于用 set -f 关闭通配展开而不影响主流程。
only_matches() {
    local want="$1"
    [ -n "$ONLY" ] || return 0
    (
        set -f
        IFS=','
        for item in $ONLY; do
            [ "$item" = "$want" ] && exit 0
        done
        exit 1
    )
}

# 是否是 vX.Y.Z 形式的发布标签
tag_is_semver() {
    local v="${1#v}"
    [ -n "$v" ] || return 1
    case "$v" in *[!0-9.]*) return 1 ;; esac
    local IFS='.'
    local -a parts=($v)
    [ "${#parts[@]}" -eq 3 ] || return 1
    local p
    for p in "${parts[@]}"; do
        [ -n "$p" ] || return 1
    done
    return 0
}

# ---------- 宿主侧「子模块登记形态」判定 ----------

# 子模块路径是否已在宿主索引里登记为 gitlink（模式 160000）
gitlink_in_index() {
    git -C "$1" ls-files -s -- "$2" 2>/dev/null | awk '$1=="160000"{f=1} END{exit !f}'
}

# .gitmodules 是否声明了该路径（优先看 HEAD，其次看索引——覆盖「已 add 未 commit」）
gitmodules_declares() {
    local host="$1" sub="$2" content
    content="$(git -C "$host" show HEAD:.gitmodules 2>/dev/null || true)"
    [ -n "$content" ] || content="$(git -C "$host" show :.gitmodules 2>/dev/null || true)"
    [ -n "$content" ] || return 1
    printf '%s\n' "$content" | awk -v want="$sub" '
        /^[[:space:]]*path[[:space:]]*=/ {
            p = $0
            sub(/^[[:space:]]*path[[:space:]]*=[[:space:]]*/, "", p)
            sub(/[[:space:]]+$/, "", p)
            if (p == want) found = 1
        }
        END { exit !found }'
}

# 该目录是否是「真正的子模块 checkout」（而非随手放进去的 vendored 副本 / 嵌套仓库）。
# 判据：其 git dir 落在宿主的 .git/modules/ 下 —— 只有 git submodule add 会产生这种布局。
# 这条判据让「自动补登 gitlink」保持安全：补登一个 vendored 副本的 HEAD 没有意义
# （该 commit 通常不存在于引擎仓，补登完立刻变成 unknown-engine-commit），
# 那种情况应提示走 git submodule add，而不是悄悄写进一个错误的 gitlink。
is_submodule_checkout() {
    local host="$1" sub="$2" hgd sgd
    hgd="$(git -C "$host" rev-parse --absolute-git-dir 2>/dev/null || true)"
    sgd="$(git -C "$host/$sub" rev-parse --absolute-git-dir 2>/dev/null || true)"
    [ -n "$hgd" ] && [ -n "$sgd" ] || return 1
    case "$sgd" in
        "$hgd"/modules/*) return 0 ;;
        *) return 1 ;;
    esac
}

# 某个 commit 与同步目标的关系 → 输出 "<behind>\t<relation>"
# relation: same | behind | ahead | unknown | diverged
compare_to_target() {
    local sha="$1"
    if ! git -C "$ENGINE_DIR" cat-file -e "${sha}^{commit}" 2>/dev/null; then
        printf '%s\t%s\n' "-" "unknown"
    elif [ "$sha" = "$TARGET_SHA" ]; then
        printf '%s\t%s\n' "0" "same"
    elif git -C "$ENGINE_DIR" merge-base --is-ancestor "$sha" "$TARGET_SHA" 2>/dev/null; then
        printf '%s\t%s\n' "$(git -C "$ENGINE_DIR" rev-list --count "$sha..$TARGET_SHA")" "behind"
    elif git -C "$ENGINE_DIR" merge-base --is-ancestor "$TARGET_SHA" "$sha" 2>/dev/null; then
        printf '%s\t%s\n' "0" "ahead"
    else
        printf '%s\t%s\n' "-" "diverged"
    fi
}

cmd_list() {
    ensure_registry
    local n
    n="$(jq -r '.hosts | length' "$REGISTRY")"
    say "本机名单：${REGISTRY}（$n 个宿主）"
    say ""
    if [ "$n" = "0" ]; then
        say "（空）用 --add <name> <宿主路径> <子模块相对路径> 登记。"
        return 0
    fi
    printf '%-18s %-34s %s\n' "NAME" "SUBMODULE" "HOST PATH"
    jq -r '.hosts[] | [.name, .submodule, .path] | @tsv' "$REGISTRY" |
    while IFS=$'\t' read -r name sub path; do
        printf '%-18s %-34s %s\n' "$name" "$sub" "$path"
    done
    return 0
}

cmd_add() {
    [ -n "$ADD_NAME" ] && [ -n "$ADD_HOST" ] && [ -n "$ADD_SUB" ] ||
        die "--add 需要三个参数：<name> <宿主路径> <子模块相对路径>"
    ensure_registry
    if registry_has "$ADD_NAME"; then
        die "名单中已存在同名条目：${ADD_NAME}（如需改动请先 --remove）"
    fi
    [ -d "$ADD_HOST" ] || die "宿主路径不存在：$ADD_HOST"
    git -C "$ADD_HOST" rev-parse --git-dir >/dev/null 2>&1 || die "不是 git 仓库：$ADD_HOST"
    if ! git -C "$ADD_HOST" ls-files -s -- "$ADD_SUB" 2>/dev/null | awk '$1=="160000"{f=1} END{exit !f}'; then
        err "⚠️  $ADD_HOST 里 '$ADD_SUB' 尚不是 submodule（未登记为 gitlink）。"
        err "    请先在宿主仓库执行："
        err "      git submodule add <引擎 remote> $ADD_SUB"
    fi
    jq --arg n "$ADD_NAME" --arg p "$ADD_HOST" --arg s "$ADD_SUB" \
       '.hosts += [{name:$n, path:$p, submodule:$s}]' "$REGISTRY" > "$REGISTRY.tmp" &&
       mv "$REGISTRY.tmp" "$REGISTRY"
    say "已登记：$ADD_NAME → $ADD_HOST ($ADD_SUB)"
    return 0
}

cmd_remove() {
    [ -n "$RM_NAME" ] || die "--remove 需要 <name>"
    ensure_registry
    registry_has "$RM_NAME" || die "名单中不存在：$RM_NAME"
    jq --arg n "$RM_NAME" 'del(.hosts[] | select(.name==$n))' "$REGISTRY" > "$REGISTRY.tmp" &&
       mv "$REGISTRY.tmp" "$REGISTRY"
    say "已移除：$RM_NAME"
    return 0
}

# ---------- 发布标签（--tag） ----------
# 发布标签是各宿主 gitlink 的同步目标：只有「影响宿主调用行为」的变更才推进标签
# （判据见 STATUS.md §8.4 版本号规则 / §8.5 完成检查清单）。因此文档 / 记忆类提交不会让所有宿主无谓地重新 pin。
# 内置护栏：标签必须与本仓 STATUS.md 的 project_version 一致，否则拒绝打标——
# 把「升版本」这一步从人的自觉变成机械约束。
cmd_tag() {
    [ -n "$TAG_NAME" ] || die "--tag 需要版本号，例如：--tag v1.2.0"
    tag_is_semver "$TAG_NAME" || die "标签格式应为 vX.Y.Z（当前：${TAG_NAME}）"

    if [ -n "$(git -C "$ENGINE_DIR" status --porcelain 2>/dev/null)" ]; then
        die "引擎仓工作区不干净，请先提交再打发布标签（发布标签必须指向可复现的提交）"
    fi
    if git -C "$ENGINE_DIR" rev-parse -q --verify "refs/tags/$TAG_NAME" >/dev/null 2>&1; then
        die "标签已存在：${TAG_NAME}（发布标签不可移动；新版本请用新的版本号）"
    fi

    local pv
    pv="$(sed -n 's/^project_version:[^0-9]*\([0-9][0-9.]*\).*$/\1/p' "$ENGINE_DIR/STATUS.md" 2>/dev/null || true)"
    pv="${pv%%$'\n'*}"
    if [ -n "$pv" ] && [ "v$pv" != "$TAG_NAME" ]; then
        die "标签与 STATUS.md 的 project_version 不一致：标签 ${TAG_NAME} vs STATUS.md ${pv}
    发布标签必须对应 STATUS.md §8.4 / §8.5 的版本号：先更新 STATUS.md / changelog，再打标签。"
    fi

    local short
    short="$(git -C "$ENGINE_DIR" rev-parse --short HEAD)"
    git -C "$ENGINE_DIR" tag -a "$TAG_NAME" \
        -m "release $TAG_NAME" \
        -m "各宿主 gitlink 的同步目标（bash sync-hosts.sh --target release）。只有「影响宿主调用行为」的变更才推进本标签，判据见 STATUS.md §8.4 版本号规则。" >/dev/null

    say "已创建发布标签：${TAG_NAME} → ${short}（本地标签，未 push）"
    say ""
    say "后续步骤："
    say "  1) 推送标签（否则他人 / 新克隆看不到，见 STATUS.md OPEN-005）："
    say "         git -C \"$ENGINE_DIR\" push origin $TAG_NAME"
    if [ "$WANT_APPLY" != "1" ]; then
        say "  2) 把各宿主推到该发布版本："
        say "         bash sync-hosts.sh --apply"
        say "     （或一条命令：bash sync-hosts.sh --tag $TAG_NAME --apply）"
    fi
    return 0
}

HOOK_FILE="$ENGINE_DIR/.git/hooks/post-commit"
HOOK_MARKER="sync-hosts.sh --install-hook"
cmd_install_hook() {
    if [ -f "$HOOK_FILE" ] && ! grep -q "$HOOK_MARKER" "$HOOK_FILE"; then
        die "已存在非本工具生成的 post-commit 钩子：$HOOK_FILE
    请先人工合并或移走该文件，再重试（不覆盖既有钩子）。"
    fi
    mkdir -p "$(dirname "$HOOK_FILE")"
    {
        cat <<EOF
#!/bin/bash
# $HOOK_MARKER (auto-generated) — 引擎仓提交后跟随同步各宿主 gitlink
# 关闭方式：export PGY_SYNC_HOOK_DISABLE=1 或 bash sync-hosts.sh --uninstall-hook
[ "\${PGY_SYNC_HOOK_DISABLE:-0}" = "1" ] && exit 0
ENGINE_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/../.." && pwd)"
[ -f "\$ENGINE_DIR/sync-hosts.sh" ] || exit 0
EOF
        if [ "$HOOK_AUTO" = "1" ]; then
            # 用带引号的 heredoc：内容原样写入，不做变量展开
            cat <<'EOF'
# 自动模式：只有 HEAD 正好落在发布标签上（= 一次发布）才同步宿主。
# 普通提交不会推进发布标签，因此不会再「每提交一次就让所有宿主重新 pin」。
if git -C "$ENGINE_DIR" describe --tags --exact-match HEAD >/dev/null 2>&1; then
    bash "$ENGINE_DIR/sync-hosts.sh" --apply --quiet || true
fi
EOF
        else
            cat <<'EOF'
# 仅提示模式：只在「有宿主落后 / 需人工处理」时打印报告，不做任何改动。
EOF
        fi
        cat <<'EOF'
# 静默跑一次取退出码（0=一致，2=有落后/需人工处理，1=出错）。
# 只有退出码 2 才重跑一次打印完整报告；错误信息 die 已经写到 stderr，不必重跑。
bash "$ENGINE_DIR/sync-hosts.sh" --check --quiet
rc=$?
if [ "$rc" -eq 2 ]; then
    bash "$ENGINE_DIR/sync-hosts.sh" --check || true
fi
exit 0
EOF
    } > "$HOOK_FILE"
    chmod +x "$HOOK_FILE"
    say "已安装本机 post-commit 钩子：$HOOK_FILE"
    if [ "$HOOK_AUTO" = "1" ]; then
        say "模式：自动同步（仅在「HEAD 正好是发布标签」即发布时 --apply 宿主）"
    else
        say "模式：仅提示（有宿主落后时打印报告，不改动任何宿主）"
    fi
    return 0
}

cmd_uninstall_hook() {
    if [ ! -f "$HOOK_FILE" ]; then
        say "未安装钩子，无需卸载。"
        return 0
    fi
    grep -q "$HOOK_MARKER" "$HOOK_FILE" || die "$HOOK_FILE 不是本工具生成的，不自动删除。"
    mv "$HOOK_FILE" "$HOOK_FILE.bak"
    say "已卸载钩子（原文件备份为 $HOOK_FILE.bak）"
    return 0
}

# ---------- 目标 commit 解析 ----------
engine_head()  { git -C "$ENGINE_DIR" rev-parse HEAD; }
engine_origin_branch() {
    local b
    b="$(git -C "$ENGINE_DIR" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    [ -n "$b" ] || b="origin/master"
    printf '%s' "$b"
}

# 最新的发布标签（v*）。用 -v:refname 做语义版本排序；
# 不用 `| head -n 1`：读端提前退出会让 git 收到 SIGPIPE(141)，在 pipefail 下会误判为失败。
engine_latest_tag() {
    local t
    t="$(git -C "$ENGINE_DIR" tag --list 'v[0-9]*' --sort=-v:refname 2>/dev/null || true)"
    if [ -z "$t" ]; then
        t="$(git -C "$ENGINE_DIR" tag --list 'v[0-9]*' --sort=-creatordate 2>/dev/null || true)"
    fi
    printf '%s' "${t%%$'\n'*}"
}

case "$MODE" in
    list)           cmd_list; exit 0 ;;
    add)            cmd_add; exit 0 ;;
    remove)         cmd_remove; exit 0 ;;
    install-hook)   cmd_install_hook; exit 0 ;;
    uninstall-hook) cmd_uninstall_hook; exit 0 ;;
esac

# --tag 是「发布动作」，可单独用，也可与 --apply 组合成「发布 + 把宿主推上去」：
# 组合时先打标签，再让后续的同步流程以该新标签为目标（默认目标 release 会取到它）。
# 这是发布的主路径——post-commit 钩子只对 commit 生效，而常规顺序是「先提交、后打标签」，
# 钩子那时 HEAD 尚未带标签，因此钩子只能作为兜底（见 --install-hook）。
if [ -n "$TAG_NAME" ]; then
    cmd_tag
    if [ "$WANT_APPLY" != "1" ]; then
        exit 0
    fi
    MODE="apply"
    say ""
fi

ensure_registry

HEAD_SHA="$(engine_head)"
ENGINE_BRANCH="$(git -C "$ENGINE_DIR" rev-parse --abbrev-ref HEAD)"
ORIGIN_BRANCH=""
RELEASE_TAG=""

case "$TARGET_SOURCE" in
    release)
        RELEASE_TAG="$(engine_latest_tag)"
        if [ -z "$RELEASE_TAG" ]; then
            die "引擎仓尚无发布标签（v*），无法按发布版本同步。
    发布标签是宿主 gitlink 的同步目标（只有影响宿主调用行为的变更才推进）。
    建立第一个发布标签：  bash sync-hosts.sh --tag vX.Y.Z
    临时改用其它目标：    --target local（跟本机 HEAD）或 --target origin（跟远端分支）"
        fi
        TARGET_SHA="$(git -C "$ENGINE_DIR" rev-parse --verify --quiet "${RELEASE_TAG}^{commit}" 2>/dev/null || true)"
        [ -n "$TARGET_SHA" ] || die "无法解析发布标签 ${RELEASE_TAG} 指向的 commit"
        TARGET_DESC="发布标签 ${RELEASE_TAG}"
        ;;
    origin)
        ORIGIN_BRANCH="$(engine_origin_branch)"
        TARGET_SHA="$(git -C "$ENGINE_DIR" rev-parse "$ORIGIN_BRANCH" 2>/dev/null || true)"
        [ -n "$TARGET_SHA" ] || die "无法解析 ${ORIGIN_BRANCH}（引擎仓是否已 push / 有远端？）"
        TARGET_DESC="远端 ${ORIGIN_BRANCH}"
        ;;
    *)
        TARGET_SHA="$HEAD_SHA"
        TARGET_DESC="本机 HEAD"
        ;;
esac
TARGET_SHORT="$(printf '%.7s' "$TARGET_SHA")"
HEAD_SHORT="$(printf '%.7s' "$HEAD_SHA")"

# --apply 时用于把目标 commit 取进子模块的 ref：
# 发布标签走 tag ref（不会在子模块里留下本地标签），其余走分支。
if [ "$TARGET_SOURCE" = "release" ]; then
    SYNC_FETCH_REF="refs/tags/$RELEASE_TAG"
else
    SYNC_FETCH_REF="$ENGINE_BRANCH"
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pgy_sync.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ROWS="$WORK/rows.tsv"
: > "$ROWS"

# 逐宿主采集状态 → rows.tsv
# 列：name, host_path, submodule, pinned_short, behind, state, dirty(Y/N/S), action
while IFS=$'\t' read -r name hpath sub; do
    [ -n "$name" ] || continue
    only_matches "$name" || continue

    state=""; pinned=""; behind=""; dirty="N"; action="-"
    if [ ! -d "$hpath" ]; then
        state="missing"
    elif ! git -C "$hpath" rev-parse --git-dir >/dev/null 2>&1; then
        state="not-a-repo"
    elif gitlink_in_index "$hpath" "$sub"; then
        # 正常形态：gitlink 已在索引里
        pinned="$(git -C "$hpath" ls-tree HEAD -- "$sub" 2>/dev/null | awk '{print $3}')"
        if [ -z "$pinned" ]; then
            # gitlink 只在索引里（子模块已 add 但宿主从未 commit）→ 用索引里的 sha 仍可报告落后量
            pinned="$(git -C "$hpath" ls-files -s -- "$sub" 2>/dev/null | awk '$1=="160000"{print $2}')"
            state="uncommitted-gitlink"
        fi
    elif gitmodules_declares "$hpath" "$sub" && [ -d "$hpath/$sub" ] &&
         is_submodule_checkout "$hpath" "$sub"; then
        # 半套接入：.gitmodules 已入库 + 目录是合法的子模块 checkout，但 gitlink 未登记。
        # 危害是**静默**的（实测）：新克隆后 `.gitmodules` 有声明、但 git 不认识该路径，
        # `git submodule update --init` **不报错也不检出**（退出码 0），子模块目录根本不出现
        # ——直到构建时才发现引擎脚本缺失。而本地 `git status` 只把该目录显示为未跟踪。
        # → 可被 --apply 自动补登。
        pinned="$(git -C "$hpath/$sub" rev-parse HEAD 2>/dev/null || true)"
        state="unregistered-gitlink"
    else
        state="not-a-submodule"
    fi

    # 统一算与同步目标的关系（state 已被强制时只补 behind，不改状态名）
    if [ -n "$pinned" ]; then
        IFS=$'\t' read -r behind relation < <(compare_to_target "$pinned")
        if [ -z "$state" ]; then
            case "$relation" in
                same)    state="up-to-date" ;;
                behind)  state="outdated" ;;
                ahead)   state="ahead-of-target" ;;
                unknown) state="unknown-engine-commit" ;;
                *)       state="diverged" ;;
            esac
        fi
    fi

    case "$state" in
        missing|not-a-repo|not-a-submodule) : ;;
        *)
            if [ -n "$(git -C "$hpath" status --porcelain 2>/dev/null | awk -v s="$sub" 'substr($0,1,2)!="??"{p=$2; if(p!=s) print}')" ]; then
                dirty="Y"
            fi
            if [ -n "$(git -C "$hpath/$sub" status --porcelain 2>/dev/null || true)" ]; then
                dirty="S"
            fi ;;
    esac

    # 注意：所有列都必须非空。tab 属 IFS 空白字符，bash 的 `read` 会把**连续 tab 折叠成一个**
    # （与 jq 的 split("\t") 行为不同）——一旦某列写成空串，下面 apply 循环读回时整行会左移，
    # action / state 全部串位。故空值一律写占位符 `-`。
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$hpath" "$sub" "$(printf '%.7s' "${pinned:--}")" "${behind:--}" "$state" "$dirty" "$action" >> "$ROWS"
done < <(jq -r '.hosts[]? | [.name, .path, .submodule] | @tsv' "$REGISTRY")

TOTAL=0; OUTDATED=0; AHEAD=0; UNREG=0; ATTENTION=0
while IFS=$'\t' read -r _ _ _ _ _ st _ _; do
    TOTAL=$((TOTAL + 1))
    if [ "$st" = "outdated" ]; then
        OUTDATED=$((OUTDATED + 1))
    elif [ "$st" = "ahead-of-target" ]; then
        # 「比目标新」是良性状态（宿主已含发布版本行为），不计入需人工处理
        AHEAD=$((AHEAD + 1))
    elif [ "$st" = "unregistered-gitlink" ]; then
        # 半套接入：--apply 可自动补登，但仍属「需要动作」（新克隆会失败）
        UNREG=$((UNREG + 1))
    elif [ "$st" != "up-to-date" ]; then
        ATTENTION=$((ATTENTION + 1))
    fi
done < "$ROWS"

# --apply 的执行前置检查：返回空 = 可执行；返回非空 = 跳过原因（ACTION 文案），并已向 stderr 说明
precheck_actionable() {
    local name="$1" dirty="$2"
    if [ "$dirty" = "S" ]; then
        err "⚠️  ${name}：子模块工作区有未提交改动，跳过（不覆盖人工改动）"
        printf '%s' "skip:子模块有改动"; return 0
    fi
    if [ "$dirty" = "Y" ] && [ "$ALLOW_DIRTY" = "0" ]; then
        err "⚠️  ${name}：宿主工作区有未提交改动，跳过（如需越过：--allow-dirty）"
        printf '%s' "skip:宿主工作区不干净"; return 0
    fi
    if [ "$ENGINE_BRANCH" = "HEAD" ] && [ "$TARGET_SOURCE" = "local" ]; then
        err "⚠️  ${name}：引擎仓处于 detached HEAD，请先切回分支或用 --target origin"
        printf '%s' "skip:引擎处于-detached-HEAD"; return 0
    fi
    printf ''
}

# ---------- --apply ----------
APPLY_FAILED=0
if [ "$MODE" = "apply" ] && [ "$TOTAL" -gt 0 ]; then
    : > "$WORK/rows.new"
    while IFS=$'\t' read -r name hpath sub pinned behind state dirty action; do
        # 只是决定「走哪条分支」，state 列本身保持真实值
        eff_state="$state"
        if [ "$state" = "ahead-of-target" ] && [ "$ALLOW_DOWNGRADE" = "1" ]; then
            eff_state="outdated"   # 显式允许回落
        fi
        case "$eff_state" in
            up-to-date)
                action="skip:已最新" ;;
            ahead-of-target)
                action="skip:比目标新"
                err "ℹ️  ${name}：固定的 commit 比目标（${TARGET_DESC}）新，默认不动；如需回落：--allow-downgrade" ;;
            outdated)
                guard="$(precheck_actionable "$name" "$dirty")"
                if [ -n "$guard" ]; then
                    action="$guard"
                elif [ "$DRY_RUN" = "1" ]; then
                    action="dry-run"
                    say "[DRY-RUN] $name: ${pinned:-?} → $TARGET_SHORT  (git -C $hpath/$sub fetch + checkout --detach; git -C $hpath add $sub$([ "$DO_COMMIT" = "1" ] && echo ' + commit'))"
                else
                    if git -C "$hpath/$sub" fetch --quiet "$ENGINE_DIR" "$SYNC_FETCH_REF" 2>/dev/null &&
                       git -C "$hpath/$sub" cat-file -e "$TARGET_SHA^{commit}" 2>/dev/null &&
                       git -C "$hpath/$sub" checkout --quiet --detach "$TARGET_SHA" 2>/dev/null &&
                       git -C "$hpath" add -- "$sub" 2>/dev/null; then
                        if [ "$DO_COMMIT" = "1" ]; then
                            if git -C "$hpath" commit --quiet \
                               -m "chore(submodule): 跟随引擎迭代 → $TARGET_SHORT" -- "$sub"; then
                                action="synced"
                                say "✅ ${name}：gitlink 已更新为 ${TARGET_SHORT}（本地 commit，未 push）"
                            else
                                action="error:commit-失败"
                                APPLY_FAILED=1
                                err "❌ ${name}：gitlink 已 stage 但 commit 失败"
                            fi
                        else
                            action="staged"
                            say "✅ ${name}：已 checkout + stage（--no-commit，未提交）"
                        fi
                    else
                        action="error:git-操作失败"
                        APPLY_FAILED=1
                        err "❌ ${name}：fetch/checkout 失败（引擎 commit 是否存在于该子模块？）"
                    fi
                fi
                ;;
            unregistered-gitlink)
                # 半套接入：.gitmodules 已入库 + 目录是合法子模块 checkout，但 gitlink 未登记。
                # 本地 `git status` 只把它显示为未跟踪，看不出问题；而新克隆执行
                # `git submodule update --init` 会失败（.gitmodules 指向 git 不认识的路径）。
                # 修法 = 补登 gitlink（`git add` 对嵌仓库即写模式 160000），顺带对齐到目标版本。
                guard="$(precheck_actionable "$name" "$dirty")"
                if [ -n "$guard" ]; then
                    action="$guard"
                else
                    reg_cur="$(git -C "$hpath/$sub" rev-parse HEAD 2>/dev/null || true)"
                    IFS=$'\t' read -r _reg_behind reg_rel < <(compare_to_target "${reg_cur:-}")
                    case "$reg_rel" in
                        behind|same) reg_want="$TARGET_SHA" ;;
                        ahead)
                            # 宿主（子模块 checkout）已含目标版本的行为 → 默认保持不动
                            if [ "$ALLOW_DOWNGRADE" = "1" ]; then reg_want="$TARGET_SHA"; else reg_want="$reg_cur"; fi ;;
                        *)
                            # unknown / diverged：先完成登记（这才是本状态的核心缺陷），版本关系另行提示
                            reg_want="$reg_cur" ;;
                    esac
                    reg_short="$(printf '%.7s' "$reg_want")"
                    reg_cur_short="$(printf '%.7s' "$reg_cur")"
                    # .gitmodules 若还不在 HEAD（只在暂存区），必须一并纳入本次提交
                    reg_paths=("$sub")
                    git -C "$hpath" cat-file -e HEAD:.gitmodules 2>/dev/null || reg_paths+=(".gitmodules")
                    if [ "$DRY_RUN" = "1" ]; then
                        action="dry-run"
                        say "[DRY-RUN] ${name}: 补登 gitlink ${reg_cur_short} → ${reg_short}  (git -C $hpath add -- ${reg_paths[*]}$([ "$DO_COMMIT" = "1" ] && echo ' + commit'))"
                    else
                        reg_ok=1
                        if [ "$reg_want" != "$reg_cur" ]; then
                            reg_ok=0
                            git -C "$hpath/$sub" fetch --quiet "$ENGINE_DIR" "$SYNC_FETCH_REF" 2>/dev/null &&
                            git -C "$hpath/$sub" cat-file -e "$reg_want^{commit}" 2>/dev/null &&
                            git -C "$hpath/$sub" checkout --quiet --detach "$reg_want" 2>/dev/null && reg_ok=1
                        fi
                        if [ "$reg_ok" = "1" ] &&
                           git -C "$hpath" add -- "${reg_paths[@]}" 2>/dev/null &&
                           [ -n "$(git -C "$hpath" ls-files -s -- "$sub" | awk '$1=="160000"{print $2}')" ]; then
                            if [ "$DO_COMMIT" = "1" ]; then
                                if git -C "$hpath" commit --quiet \
                                   -m "fix(submodule): 补登引擎子模块 gitlink → $reg_short" -- "${reg_paths[@]}"; then
                                    action="registered"
                                    say "✅ ${name}：已补登 gitlink → ${reg_short}（本地 commit，未 push）"
                                else
                                    action="error:commit-失败"
                                    APPLY_FAILED=1
                                    err "❌ ${name}：gitlink 已 stage 但 commit 失败"
                                fi
                            else
                                action="registered-staged"
                                say "✅ ${name}：已补登 + stage（--no-commit，未提交）"
                            fi
                        else
                            action="error:补登失败"
                            APPLY_FAILED=1
                            err "❌ ${name}：补登 gitlink 失败（检查子模块 checkout / .gitmodules / 版本可达性）"
                        fi
                    fi
                    case "$reg_rel" in
                        behind|same) : ;;
                        *) err "ℹ️  ${name}：已按子模块当前 HEAD 补登；其与目标的版本关系为 ${reg_rel}，下次 --check 仍会提示人工处理" ;;
                    esac
                fi
                ;;
            *)
                action="skip:$state" ;;
        esac
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$name" "$hpath" "$sub" "$pinned" "$behind" "$state" "$dirty" "$action" >> "$WORK/rows.new"
    done < "$ROWS"
    cp "$WORK/rows.new" "$ROWS"
fi

# ---------- 输出 ----------
if [ "$JSON" = "1" ]; then
    if [ "$APPLY_FAILED" -gt 0 ]; then
        ST="error"
    elif [ "$MODE" = "check" ] && [ "$OUTDATED" -gt 0 ]; then
        ST="outdated"
    elif [ "$MODE" = "check" ] && [ "$UNREG" -gt 0 ]; then
        # 「半套接入」可由 --apply 修复，与 outdated 同属「可自动处理」，但语义不同故单列
        ST="unregistered"
    elif [ "$MODE" = "check" ] && [ "$ATTENTION" -gt 0 ]; then
        ST="attention"
    else
        ST="ok"
    fi
    jq -n \
        --arg status "$ST" \
        --arg epath "$ENGINE_DIR" \
        --arg head "$HEAD_SHA" \
        --arg target "$TARGET_SHA" \
        --arg tshort "$TARGET_SHORT" \
        --arg source "$TARGET_SOURCE" \
        --arg tag "${RELEASE_TAG:-}" \
        --argjson total "$TOTAL" \
        --argjson outdated "$OUTDATED" \
        --argjson ahead "$AHEAD" \
        --argjson unregistered "$UNREG" \
        --argjson attention "$ATTENTION" \
        --argjson hosts "$(jq -R -s '
            split("\n") | map(select(length>0) | split("\t") |
            {name:.[0], path:.[1], submodule:.[2], pinned:.[3],
             behind:(if (.[4] | test("^[0-9]+$")) then (.[4]|tonumber) else null end),
             state:.[5], dirty:.[6], action:.[7]})' "$ROWS")" \
        '{status:$status,
          engine:{path:$epath, head:$head, target:$target, target_short:$tshort,
                  source:$source, release_tag:(if $tag=="" then null else $tag end)},
          summary:{total:$total, outdated:$outdated, unregistered:$unregistered,
                   ahead_of_target:$ahead, attention:$attention},
          hosts:$hosts, error:null}'
else
    say "引擎：$ENGINE_DIR"
    say "目标：${TARGET_SHORT}（${TARGET_DESC}）"
    if [ "$TARGET_SOURCE" = "release" ] && [ "$HEAD_SHA" != "$TARGET_SHA" ]; then
        say "      （引擎本机 HEAD 为 ${HEAD_SHORT}，领先发布标签；未打标签的提交不会同步给宿主）"
    fi
    say ""
    if [ "$TOTAL" -eq 0 ]; then
        say "名单为空。用 --add <name> <宿主路径> <子模块相对路径> 登记项目，或 --list 查看。"
    else
        printf '%-18s %-9s %-7s %-18s %-6s %s\n' "NAME" "PINNED" "BEHIND" "STATE" "DIRTY" "ACTION"
        awk -F'\t' '{
            d=$7; if (d=="Y") d="host"; else if (d=="S") d="sub"; else d="-";
            printf "%-18s %-9s %-7s %-18s %-6s %s\n", $1, $4, $5, $6, d, $8
        }' "$ROWS"
        say ""
        # 「比目标新」是良性状态，单独列出（不会被 --apply 改动）
        if [ "$AHEAD" -gt 0 ]; then
            awk -F'\t' '$6=="ahead-of-target" {print $1"\t"$4}' "$ROWS" |
            while IFS=$'\t' read -r n p; do
                say "ℹ️  ${n}：固定的 ${p} 比目标（${TARGET_DESC}）新，尚未推进到该处 → 默认不动，回落需 --allow-downgrade"
            done
        fi
        # 「半套接入」可被 --apply 自动补登，单独列出（它的本地表现只是「未跟踪目录」，极易漏看）。
        # 仅 check 模式打印：apply 模式下这些行要么已被补登（再提示即为过时信息），
        # 要么因工作区不干净被跳过（原因已由 stderr 说明 + ACTION 列可见）。
        if [ "$MODE" = "check" ] && [ "$UNREG" -gt 0 ]; then
            awk -F'\t' '$6=="unregistered-gitlink" {print $1"\t"$4}' "$ROWS" |
            while IFS=$'\t' read -r n p; do
                say "⚠️  ${n}：.gitmodules 已入库但 gitlink 未登记（本地看似正常；新克隆会**静默**缺少该子模块，update --init 不报错也不检出）→ ${p}；执行 --apply 可自动补登"
            done
        fi
        # 除「已最新 / 落后 / 比目标新 / 半套接入」之外的异常状态给出可执行提示（这些状态不会被 --apply 自动处理）
        awk -F'\t' '$6!="up-to-date" && $6!="outdated" && $6!="ahead-of-target" && $6!="unregistered-gitlink" {print $1"\t"$6}' "$ROWS" |
        while IFS=$'\t' read -r n st; do
            case "$st" in
                missing)               say "⚠️  ${n}：宿主路径不存在（磁盘未挂载 / 项目已移动）→ 核对该条目的 path" ;;
                not-a-repo)            say "⚠️  ${n}：该路径不是 git 仓库 → 核定 path 是否写错" ;;
                not-a-submodule)       say "⚠️  ${n}：该路径尚未登记为 submodule → 参照 xiyuWebBrowser 的收敛做法执行 git submodule add" ;;
                uncommitted-gitlink)   say "⚠️  ${n}：子模块已 add 但宿主从未 commit（.gitmodules + gitlink 仍在暂存区）→ 请先在宿主仓完成这次提交" ;;
                unknown-engine-commit) say "⚠️  ${n}：宿主固定的 commit 不在本机引擎仓（引擎仓落后于该宿主？）→ 先在引擎仓 git fetch/pull" ;;
                diverged)              say "⚠️  ${n}：宿主固定的 commit 不是当前目标的祖先（已分叉）→ 需人工判断，脚本不自动处理" ;;
            esac
        done
        say ""
        if [ "$MODE" = "check" ]; then
            if [ "$OUTDATED" -gt 0 ] || [ "$UNREG" -gt 0 ]; then
                cnt_parts=""
                [ "$OUTDATED" -gt 0 ] && cnt_parts="${OUTDATED} 个落后"
                [ "$UNREG" -gt 0 ] && cnt_parts="${cnt_parts:+${cnt_parts}、}${UNREG} 个半套接入"
                say "结论：${cnt_parts}（共 $TOTAL 个宿主），执行 --apply 即可处理（宿主侧本地 commit，不 push）。"
            elif [ "$ATTENTION" -gt 0 ]; then
                say "结论：无可自动处理的项，但有 $ATTENTION 个宿主需人工处理（见上方提示）。"
            elif [ "$AHEAD" -gt 0 ]; then
                say "结论：$AHEAD 个宿主比目标（${TARGET_DESC}）新，属良性（默认不动；回落需 --allow-downgrade）。"
            else
                say "结论：检查了 $TOTAL 个宿主，均与目标（${TARGET_DESC}）一致。"
            fi
        fi
    fi
fi

if [ "$APPLY_FAILED" -gt 0 ]; then exit 1; fi
if [ "$MODE" = "check" ] && { [ "$OUTDATED" -gt 0 ] || [ "$UNREG" -gt 0 ] || [ "$ATTENTION" -gt 0 ]; }; then exit 2; fi
exit 0
