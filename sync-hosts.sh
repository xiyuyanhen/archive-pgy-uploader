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
#  同步语义（重要）：
#    - 默认跟随「本机引擎仓当前 HEAD」→ 引擎本地刚提交、还没 push 也能让宿主跟上
#      （适合单人本机快节奏迭代）。
#    - `--from-origin` 跟随 origin 的默认分支 → 需要先把引擎 commit push 出去
#      （适合交接 / 多机 / CI，可复现性优先）。
#    无论哪种，宿主侧都是「更新 gitlink + 本地 commit」，**不 push**（push 由人决定）。
#
#  用法：
#    bash sync-hosts.sh                    # = --check，只读报告各宿主落后情况
#    bash sync-hosts.sh --json             # 单行 JSON（供 AI/CI 解析）
#    bash sync-hosts.sh --list             # 打印本机名单
#    bash sync-hosts.sh --apply            # 同步落后宿主：更新 gitlink 并本地 commit
#    bash sync-hosts.sh --apply --no-commit    # 只 checkout + stage，不 commit
#    bash sync-hosts.sh --apply --from-origin  # 目标取 origin 默认分支
#    bash sync-hosts.sh --apply --only xiyuScoreboard,xiyu_todo_list
#    bash sync-hosts.sh --apply --dry-run  # 只打印将执行的动作
#    bash sync-hosts.sh --apply --allow-dirty  # 宿主有未提交改动时仍同步（见下）
#    bash sync-hosts.sh --add <name> <宿主路径> <子模块相对路径>
#    bash sync-hosts.sh --remove <name>
#    bash sync-hosts.sh --install-hook [--auto]   # 装本机 post-commit 钩子
#    bash sync-hosts.sh --uninstall-hook
#
#  安全约束：
#    - --apply 只处理「状态=outdated 且宿主工作区干净」的宿主；其余一律跳过并说明原因。
#    - 子模块工作区有未提交改动 → 跳过该宿主（不覆盖任何人工改动）。
#    - 宿主工作区脏（未提交改动）默认也跳过；--allow-dirty 可越过该检查，因为
#      gitlink 更新走 `git add -- <子模块路径>` + `git commit -- <子模块路径>`（带 pathspec），
#      **不会**把宿主的其它改动卷进这次提交。子模块自身的脏工作区则始终拒绝。
#    - 引擎目录内不得出现密钥；本脚本不读、不写、不打印任何凭证。
#
#  退出码：0=全部最新或全部成功；2=存在落后/需人工介入（仅 --check 语义）；1=执行出错。
# ==============================================================================
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${PGY_SYNC_REGISTRY:-$ENGINE_DIR/.local/hosts.json}"

MODE="check"
TARGET_SOURCE="local"
DO_COMMIT=1
DRY_RUN=0
ALLOW_DIRTY=0
ONLY=""
QUIET=0
JSON=0
HOOK_AUTO=0
ADD_NAME=""; ADD_HOST=""; ADD_SUB=""
RM_NAME=""

usage() {
    sed -n '2,60p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
        --apply)          MODE="apply" ;;
        --list)           MODE="list" ;;
        --json)           JSON=1 ;;
        --no-commit)      DO_COMMIT=0 ;;
        --from-origin)    TARGET_SOURCE="origin" ;;
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
    if registry_names | grep -qx "$ADD_NAME"; then
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
    registry_names | grep -qx "$RM_NAME" || die "名单中不存在：$RM_NAME"
    jq --arg n "$RM_NAME" 'del(.hosts[] | select(.name==$n))' "$REGISTRY" > "$REGISTRY.tmp" &&
       mv "$REGISTRY.tmp" "$REGISTRY"
    say "已移除：$RM_NAME"
    return 0
}

HOOK_FILE="$ENGINE_DIR/.git/hooks/post-commit"
HOOK_MARKER="sync-hosts.sh --install-hook"

cmd_install_hook() {
    if [ -f "$HOOK_FILE" ] && ! grep -q "$HOOK_MARKER" "$HOOK_FILE"; then
        die "已存在非本工具生成的 post-commit 钩子：$HOOK_FILE
    请先人工合并或移走该文件，再重试（不覆盖既有钩子）。"
    fi
    local mode_line="bash \"\$ENGINE_DIR/sync-hosts.sh\" --check --quiet"
    if [ "$HOOK_AUTO" = "1" ]; then
        mode_line="bash \"\$ENGINE_DIR/sync-hosts.sh\" --apply --quiet"
    fi
    mkdir -p "$(dirname "$HOOK_FILE")"
    cat > "$HOOK_FILE" <<EOF
#!/bin/bash
# $HOOK_MARKER (auto-generated) — 引擎仓提交后跟随同步各宿主 gitlink
# 关闭方式：export PGY_SYNC_HOOK_DISABLE=1 或 bash sync-hosts.sh --uninstall-hook
[ "\${PGY_SYNC_HOOK_DISABLE:-0}" = "1" ] && exit 0
ENGINE_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/../.." && pwd)"
[ -f "\$ENGINE_DIR/sync-hosts.sh" ] || exit 0
$mode_line || true
exit 0
EOF
    chmod +x "$HOOK_FILE"
    say "已安装本机 post-commit 钩子：$HOOK_FILE"
    if [ "$HOOK_AUTO" = "1" ]; then
        say "模式：自动同步（--apply；仅同步「工作区干净且落后」的宿主）"
    else
        say "模式：仅提示（落后时打印报告，不改动任何宿主）"
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

case "$MODE" in
    list)           cmd_list; exit 0 ;;
    add)            cmd_add; exit 0 ;;
    remove)         cmd_remove; exit 0 ;;
    install-hook)   cmd_install_hook; exit 0 ;;
    uninstall-hook) cmd_uninstall_hook; exit 0 ;;
esac

ensure_registry

HEAD_SHA="$(engine_head)"
ENGINE_BRANCH="$(git -C "$ENGINE_DIR" rev-parse --abbrev-ref HEAD)"
if [ "$TARGET_SOURCE" = "origin" ]; then
    ORIGIN_BRANCH="$(engine_origin_branch)"
    TARGET_SHA="$(git -C "$ENGINE_DIR" rev-parse "$ORIGIN_BRANCH" 2>/dev/null || true)"
    [ -n "$TARGET_SHA" ] || die "无法解析 ${ORIGIN_BRANCH}（引擎仓是否已 push / 有远端？）"
else
    TARGET_SHA="$HEAD_SHA"
fi
TARGET_SHORT="$(printf '%.7s' "$TARGET_SHA")"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pgy_sync.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ROWS="$WORK/rows.tsv"
: > "$ROWS"

# 逐宿主采集状态 → rows.tsv
# 列：name, host_path, submodule, pinned_short, behind, state, dirty(Y/N/S), action
while IFS=$'\t' read -r name hpath sub; do
    [ -n "$name" ] || continue
    if [ -n "$ONLY" ]; then
        printf '%s' "$ONLY" | tr ',' '\n' | grep -qx "$name" || continue
    fi

    state=""; pinned=""; behind=""; dirty="N"; action="-"
    if [ ! -d "$hpath" ]; then
        state="missing"
    elif ! git -C "$hpath" rev-parse --git-dir >/dev/null 2>&1; then
        state="not-a-repo"
    elif ! git -C "$hpath" ls-files -s -- "$sub" 2>/dev/null | awk '$1=="160000"{f=1} END{exit !f}'; then
        state="not-a-submodule"
    else
        pinned="$(git -C "$hpath" ls-tree HEAD -- "$sub" 2>/dev/null | awk '{print $3}')"
        if [ -z "$pinned" ]; then
            # gitlink 只在索引里（子模块已 add 但宿主从未 commit）→ 用索引里的 sha 仍可报告落后量
            pinned="$(git -C "$hpath" ls-files -s -- "$sub" 2>/dev/null | awk '$1=="160000"{print $2}')"
            state="uncommitted-gitlink"
        fi
        if ! git -C "$ENGINE_DIR" cat-file -e "$pinned^{commit}" 2>/dev/null; then
            [ -n "$state" ] || state="unknown-engine-commit"
        elif git -C "$ENGINE_DIR" merge-base --is-ancestor "$pinned" "$TARGET_SHA" 2>/dev/null; then
            behind="$(git -C "$ENGINE_DIR" rev-list --count "$pinned..$TARGET_SHA")"
            if [ -z "$state" ]; then
                if [ "$behind" = "0" ]; then state="up-to-date"; else state="outdated"; fi
            fi
        else
            [ -n "$state" ] || state="diverged"
        fi
        if [ -n "$(git -C "$hpath" status --porcelain 2>/dev/null | awk -v s="$sub" 'substr($0,1,2)!="??"{p=$2; if(p!=s) print}')" ]; then
            dirty="Y"
        fi
        if [ -n "$(git -C "$hpath/$sub" status --porcelain 2>/dev/null || true)" ]; then
            dirty="S"
        fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$hpath" "$sub" "$(printf '%.7s' "${pinned:-}")" "${behind:--}" "$state" "$dirty" "$action" >> "$ROWS"
done < <(jq -r '.hosts[]? | [.name, .path, .submodule] | @tsv' "$REGISTRY")

TOTAL=0; OUTDATED=0; ATTENTION=0
while IFS=$'\t' read -r _ _ _ _ _ st _ _; do
    TOTAL=$((TOTAL + 1))
    if [ "$st" = "outdated" ]; then
        OUTDATED=$((OUTDATED + 1))
    elif [ "$st" != "up-to-date" ]; then
        ATTENTION=$((ATTENTION + 1))
    fi
done < "$ROWS"

# ---------- --apply ----------
APPLY_FAILED=0
if [ "$MODE" = "apply" ] && [ "$OUTDATED" -gt 0 ]; then
    : > "$WORK/rows.new"
    while IFS=$'\t' read -r name hpath sub pinned behind state dirty action; do
        case "$state" in
            up-to-date)
                action="skip:已最新" ;;
            outdated)
                if [ "$dirty" = "S" ]; then
                    action="skip:子模块有改动"
                    err "⚠️  ${name}：子模块工作区有未提交改动，跳过（不覆盖人工改动）"
                elif [ "$dirty" = "Y" ] && [ "$ALLOW_DIRTY" = "0" ]; then
                    action="skip:宿主工作区不干净"
                    err "⚠️  ${name}：宿主工作区有未提交改动，跳过（如需越过：--allow-dirty）"
                elif [ "$ENGINE_BRANCH" = "HEAD" ] && [ "$TARGET_SOURCE" = "local" ]; then
                    action="skip:引擎处于-detached-HEAD"
                    err "⚠️  ${name}：引擎仓处于 detached HEAD，请先切回分支或用 --from-origin"
                elif [ "$DRY_RUN" = "1" ]; then
                    action="dry-run"
                    say "[DRY-RUN] $name: ${pinned:-?} → $TARGET_SHORT  (git -C $hpath/$sub fetch + checkout --detach; git -C $hpath add $sub$([ "$DO_COMMIT" = "1" ] && echo ' + commit'))"
                else
                    if git -C "$hpath/$sub" fetch --quiet "$ENGINE_DIR" "$ENGINE_BRANCH" 2>/dev/null &&
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
        --arg source "$TARGET_SOURCE" \
        --argjson hosts "$(jq -R -s '
            split("\n") | map(select(length>0) | split("\t") |
            {name:.[0], path:.[1], submodule:.[2], pinned:.[3],
             behind:(if (.[4] | test("^[0-9]+$")) then (.[4]|tonumber) else null end),
             state:.[5], dirty:.[6], action:.[7]})' "$ROWS")" \
        '{status:$status,
          engine:{path:$epath, head:$head, target:$target, source:$source},
          hosts:$hosts, error:null}'
else
    say "引擎：$ENGINE_DIR"
    say "目标：${TARGET_SHORT}（来源：$([ "$TARGET_SOURCE" = "origin" ] && echo "远端 $(engine_origin_branch)" || echo "本机 HEAD")）"
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
        # 非「已最新/落后」的异常状态给出可执行提示（这些状态不会被 --apply 自动处理）
        awk -F'\t' '$6!="up-to-date" && $6!="outdated" {print $1"\t"$6}' "$ROWS" |
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
            if [ "$OUTDATED" -gt 0 ]; then
                say "结论：$OUTDATED/$TOTAL 个宿主落后于引擎，执行 --apply 即可同步（宿主侧本地 commit，不 push）。"
            elif [ "$ATTENTION" -gt 0 ]; then
                say "结论：无落后项，但有 $ATTENTION 个宿主需人工处理（见上方提示）。"
            else
                say "结论：检查了 $TOTAL 个宿主，均与引擎一致。"
            fi
        fi
    fi
fi

if [ "$APPLY_FAILED" -gt 0 ]; then exit 1; fi
if [ "$MODE" = "check" ] && { [ "$OUTDATED" -gt 0 ] || [ "$ATTENTION" -gt 0 ]; }; then exit 2; fi
exit 0
