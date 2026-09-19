# 执行经验条目（累积式，禁止删除已验证内容）

> 最后更新：2026-09-19 | 当前项目版本：1.3.0

> 条目格式见文末「条目写作格式」。L-001 ~ L-004 为**基线建立时回填**的历史经验
> （依据：仓库 git 提交历史 + 项目工作记忆 `.workbuddy/memory/2026-08-0{6,7,8}.md`），
> 关联执行记录见 `execution-log.json` 中的 `run-20260919-lessons-backfill`。

---

## L-001 — Xcode 不会热加载外部手改的共享 `.xcscheme`，Post-actions 会静默不执行

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` |
| **引入版本** | 1.0.0 |
| **关联执行** | `run-20260919-lessons-backfill`（原始事件：`xiyu_todo_list` 接入排查，2026-08-08） |
| **场景** | 用文本/脚本把 ArchiveAction PostActions 注入 `ios/Runner.xcodeproj/xcshareddata/xcschemes/*.xcscheme`，随后在 Xcode GUI 里 `Product → Archive` |

**问题**：Archive 正常完成，但**不触发上传**，且 `$TMPDIR` 下**没有任何 `pgy_upload_*.log`**。
容易误判为"引擎坏了 / 密钥配错 / 路径写错"，进而去改脚本（方向完全错误）。

**根因**：Xcode 在启动时读取 scheme 到内存，**不监听文件变化**。外部改动的共享 scheme 只在
"完全退出 Xcode 并重新打开项目"后才被加载。用户测试时 Xcode 仍持有旧的内存方案（无 Post-actions），
因此脚本从未被启动——**没有日志本身就是最关键的证据**（脚本一旦启动必写日志）。

**解法**：三条路，按推荐度排序——
1. **首选：走 CLI 入口** `bash <引擎目录>/archive_upload.sh --target "测试版本"`。
   它自己执行 `xcodebuild archive` 再上传，**完全不依赖 Xcode GUI 的 scheme 缓存**，是最干净的规避路径。
2. 在 Xcode `Edit Scheme → Archive → + → New Run Script Phase` **手动**添加 Post-actions（手动加的一定生效）。
3. 若坚持用文本注入：注入后**完全退出 Xcode 再重开项目**，并在 `Edit Scheme → Archive` 里确认脚本已出现。

**保留的既有经验**：本条目补充而非替代 `STATUS.md` §5.2「Xcode `$ARCHIVE_PATH` 仅 Post-actions 注入」的约束；
两者叠加解释了「误接 Build Phase + scheme 未重载」这两类"不上传"故障的区分方式（前者有日志，后者无日志）。

---

## L-002 — `set -e` 下函数以 `&&` 链结尾会误杀调用方，函数必须显式 `return 0`

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` |
| **引入版本** | 1.0.0 |
| **关联执行** | `run-20260919-lessons-backfill`（原始修复：commit `6c805cf`） |
| **场景** | `pgy_upload.sh`（`set -e`）中的 `load_history()` 末行为 `[ -z "$VAR" ] && VAR="$X"` 形式的三连串 |

**问题**：当变量已被 `--notes` / config / 环境变量**预置为非空**时，末行 `[ -z ... ]` 求值为 false，
整个函数返回 **1**；在 `set -e` 下调用方 `prepare_upload` 随之返回 1 并**直接中止脚本**。
外在表现极具误导性：**`--_upload` worker 静默退出，既不导出也不报错**。

**根因**：`set -e` 会把"函数返回非 0"当作失败；而 shell 函数的返回值就是**最后一条命令的退出码**。
用 `&&` 短链做"条件赋值"时，条件不成立即返回 1 —— 这是隐式的失败信号。

**解法**：在函数体末尾**显式 `return 0`**，把"条件赋值"与"函数成功性"解耦：

```bash
load_history() {
    ...
    [ -z "$PGY_VERSION_TARGET" ] && PGY_VERSION_TARGET="$vt"
    [ -z "$PGY_VERSION_OVERRIDE" ] && PGY_VERSION_OVERRIDE="$ver"
    [ -z "$PGY_UPDATE_DESCRIPTION" ] && PGY_UPDATE_DESCRIPTION="$des"
    return 0   # ← 必须显式：消除 set -e 误杀
}
```

**排查提示**：这类故障的典型症状是"**没有日志文件**"与"**有日志但停在某一步**"的区分——
本条的 worker 静默退出属于后者（主进程已启动，日志存在但内容戛然而止）。
另注意：日志归属靠 **IPA 名 / Bundle ID** 判断（`xiyu_scoreboard.ipa` = Scoreboard，`xiyu_todolist.ipa` = todo_list），
**勿混淆**（曾因混淆浪费一轮排查）。

**保留的既有经验**：无替代关系；本条为新增的编码约束。

---

## L-003 — CLI 自动化的双触发防护：用进程树祖先判定，而非环境变量继承

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` |
| **引入版本** | 1.0.0 |
| **关联执行** | `run-20260919-lessons-backfill`（原始修复：commit `6576a6f`，兜底见 `0c5152a`） |
| **场景** | 用 `archive_upload.sh` 做 CLI/CI 自动化时（它内部会执行 `xcodebuild archive`） |

**问题**：`xcodebuild archive` **本身就会触发 Xcode 的 Post-actions**，也就是 `pgy_upload.sh` 的主进程模式。
若不加防护，同一次归档会被"Post-actions 主进程"和"`archive_upload.sh` 拉起的 `--_upload` worker"**各上传一次**（双上传、抢同一归档）。

**根因**：两条触发路径都会跑起来，且早期方案依赖 `PGY_SKIP_POSTACTION` 环境变量向子进程传递"我是 CLI 驱动"的信号——
但 Xcode 触发的 Post-actions **不继承**该 shell 的环境变量，信号丢了，防护失效。

**解法**：改用**进程树硬判定**——主进程启动后回溯祖先进程，
若某个祖先的可执行文件 basename 为 `xcodebuild`，即判定本次归档由 CLI 驱动 → 主进程直接 `exit 0`，
上传交由 `archive_upload.sh` 拉起的 `--_upload` worker 完成；
GUI Archive 的祖先是 `Xcode.app`（无 `xcodebuild` 进程），则正常 fork worker 上传。

**健壮性要点（易错处）**：比对的是祖先**命令行首个 token 的 basename**，而**不是整行子串**——
否则命令行参数里恰好出现 `xcodebuild` 字样就会误判。
`PGY_SKIP_POSTACTION` 仅作兜底保留，不再是主机制。

**保留的既有经验**：本条替代了"依赖环境变量继承"的旧方案（旧机制降级为兜底），
旧方案描述仍保留在 `archive_upload.sh` 与 `README.md` 中作为历史上下文。

---

## L-004 — 更新说明的"双来源"取决于入口：`--notes` 只在 CLI 路径生效

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` |
| **引入版本** | 1.0.0 |
| **关联执行** | `run-20260919-lessons-backfill`（原始澄清：commit `6d3f476`；相关修复：`0c5152a`） |
| **场景** | 想修改蒲公英上显示的"更新说明"（`updateDescription` / `buildUpdateDescription`） |

**问题**：改了 `--notes` 却对上传结果毫无影响，让人以为参数没被解析。

**根因**：两个入口传入的参数集合不同——
- **Xcode Post-actions 入口**：Xcode 只注入 `$ARCHIVE_PATH`，脚本实际只收到 `--config --archive`，
  **`--notes` 根本没被传入**，所以更新说明恒取自 `PGYUploadHistory.json` 的 `[0].updateDes`；
- **CLI / 手动入口**：`archive_upload.sh --notes "..."` 或 `pgy_upload.sh --notes "..."` 才会覆盖。

**解法**：按入口选手段——
- 走 Xcode Post-actions → **改 `PGYUploadHistory.json` 的 `[0].updateDes`**，然后重新 Archive；
- 走 CLI → 用 `--notes` 覆盖。

**保留的既有经验**：本条与 `STATUS.md` §4.1 的取值优先级表互为补充——优先级表说明"谁覆盖谁"，
本条说明"**该入口有没有拿到那个参数**"，后者才是踩坑的直接原因。

---

## L-005 — `bash -n a.sh b.sh` 只检查第一个文件，会给出"假通过"的语法校验

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` |
| **引入版本** | 1.0.0 |
| **关联执行** | `run-20260919-governance-baseline`（本会话实测复现） |
| **场景** | 在变更脚本后做"语法校验"以确认没写坏，尤其是要一次性校验多个脚本时 |

**问题**：写了 `bash -n pgy_upload.sh archive_upload.sh link-skill.sh`，命令**退出码 0、无任何输出**，
看起来"三个脚本都通过了"。实际上其中若有语法错误也不会被发现——**校验形同虚设**，
还可能被写进变更记录的"验证方式"里，让后来者以为已验过。

**根因**：`bash -n` 的语义是"读取**一个**脚本文件并做语法检查，其余参数成为该脚本的 `$1 $2 ...`"。
所以后续文件被当作**位置参数**而非待检查文件，自然不参与检查，且因为第一个文件没问题，退出码为 0。

**解法**：逐文件调用，任一失败即中断：

```bash
for f in pgy_upload.sh archive_upload.sh link-skill.sh; do
    bash -n "$f" || exit 1
done
```

或等价的链式写法：`bash -n a.sh && bash -n b.sh && bash -n c.sh`。

**实测证据**（本会话复现）：

```bash
printf 'echo ok\n' > good.sh
printf 'if [ 1 = 1 ]; then\n' > broken.sh      # 故意缺 fi

bash -n good.sh broken.sh   # → exit 0（假通过，未检出 broken.sh 的错误）
bash -n broken.sh           # → exit 2 + 报错「未预期的文件结束符」
```

**推广**：同类"多文件只认第一个"的命令还有 `sh -n`；校验多个 shell 脚本应统一走循环。
**保留的既有经验**：无替代关系；本条为新增的校验方法约束。

---

## L-006 — `read` 遇到 EOF 会**清空**它赋值的变量，「while read 循环结束后再用这些变量」必然拿到空值

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` |
| **引入版本** | 1.1.0 |
| **关联执行** | `run-20260919-hosts-sync-and-browser-consolidation`（本会话实测复现） |
| **场景** | 用 `while IFS=$'\t' read -r a b c; do ...; done < <(...)` 逐行处理数据，循环里把值写进文件，**循环之后再引用 `$c`**（例如在另一个循环里拼路径、拼提示） |

**问题**：循环里读到的值是对的（写进文件的每行都正确），但循环结束后 `$c` 是**空字符串**。
症状极具误导性：数据文件内容完全正确，却在「循环外用到的那个变量」上凭空丢了值——
本会话第一版 `sync-hosts.sh` 就因此在干跑提示里打出了 `.../xiyuScoreboard/ fetch`（子模块路径缺失），
看起来像"变量名写错/函数作用域问题"，实际是**循环变量的生命周期**问题。

**根因**：`read` 在**读到 EOF（返回非零）时会把它的目标变量置为空串**。
循环自然结束的那一次 `read` 正是读到 EOF 的那一次，于是循环退出来后这些变量都已被清空。
注意：这与 bash 版本无关（本机 bash 5.3.15 与系统 bash 3.2.57 **表现一致**），也不是子 shell 问题
（循环体内用普通赋值设置的计数器**不会**被清空——这恰恰是排除"子 shell"猜想的判别依据）。

**解法**：循环外需要的数据，要么在循环内就**落盘/落变量**，要么在循环内用**普通赋值**搬运。
本项目的落地做法：把每个宿主的全部字段写成一张 TSV（`rows.tsv`），后续所有阶段都从这个文件重读，
不再依赖任何"上一个循环残留的变量"。

```bash
# ✗ 错：循环外出去了，$sub 已是空串
while IFS=$'\t' read -r name hpath sub; do
    printf '%s\n' ... >> "$ROWS"
done < <(jq -r ... )
while IFS=$'\t' read -r name hpath x; do
    git -C "$hpath/$sub" ...      # $sub 为 ""
done < "$ROWS"

# ✓ 对：需要什么就自己读进来
while IFS=$'\t' read -r name hpath sub; do
    git -C "$hpath/$sub" ...
done < "$ROWS"
```

**实测证据**（本会话复现）：

```bash
printf 'x\ty\tSUB1\n' > /tmp/rt.txt

# A) 循环体 break（不触发 EOF 读取）→ 变量保留
while IFS=$'\t' read -r a b c; do break; done < /tmp/rt.txt
echo "c=[$c]"        # → c=[SUB1]

# B) 循环自然结束（末次 read 读到 EOF）→ 变量被清空
while IFS=$'\t' read -r a b c; do :; done < /tmp/rt.txt
echo "c=[$c]"        # → c=[]

# C) 机制直证：成功读取后，再来一次立即 EOF 的 read，变量立刻被清空
while IFS=$'\t' read -r a b c; do break; done < /tmp/rt.txt
echo "c=[$c]"                      # → c=[SUB1]
read -r a b c < /dev/null || true
echo "c=[$c]"                      # → c=[]（被 EOF 清空）

# D) 对照：普通赋值不受影响（用于排除"子 shell"误判）
n=0; while IFS=$'\t' read -r a b c; do n=$((n+1)); done < /tmp/rt.txt
echo "n=$n"                        # → n=1（保留）
```

**推广**：同类"循环结束即失效"的还有 `while read` 配合 `break`/`return` 提前退出后再引用变量的场景；
需要跨阶段传递的数据一律走文件或显式赋值。

**保留的既有经验**：无替代关系；本条与 L-002（函数返回值陷阱）同属"shell 隐式语义导致的静默丢数据"家族。

---

## L-007 — jq 的 `tonumber?` 在失败时产生 **empty**（不是 null），会让整条记录被 `map` 静默丢弃

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` |
| **引入版本** | 1.1.0 |
| **关联执行** | `run-20260919-hosts-sync-and-browser-consolidation`（本会话实测复现） |
| **场景** | 用 `jq -R -s` 把 TSV 转成 JSON 数组时，对可能非数字的字段做类型转换，如 `behind:(.[3]|tonumber?)` |

**问题**：转出来的 JSON **条目数比输入少**，且**不报错、不警告**。
本会话第一版 `sync-hosts.sh --json` 输出 3 个宿主里的 2 个，被丢掉的恰好是字段值为 `-`（非数字）的那条。
"少一条又不报错"是最危险的一类 bug——下游（AI/CI）会以为世界只有两个宿主。

**根因**：jq 的 `EXP?`（`try EXP`）在出错时产生 **`empty`**，而不是 `null`。
当对象字面量中的某个字段取值是 `empty` 时，**整个对象表达式也变成 `empty`**，
于是 `map(...)` 就把这条记录当"没有输出"丢掉了。

**解法**：不要让失败路径产生 `empty`。显式判定再转换，或用 `//` 兜底为 `null`：

```jq
# ✗ 危险：失败 → empty → 整条记录消失
{name:.[0], behind:(.[3]|tonumber?)}

# ✓ 显式判定
{name:.[0], behind:(if (.[3] | test("^[0-9]+$")) then (.[3]|tonumber) else null end)}

# ✓ 或利用 // 会把 empty 视为"无有效值"而取右值
{name:.[0], behind:((.[3]|tonumber?) // null)}
```

**落地约束**：凡"TSV/行文本 → JSON"的转换，验证方式里必须**断言条目数**，
例如 `jq -e '.hosts | length == <期望值>'`——只校验"JSON 合法"是抓不到本条的。

**保留的既有经验**：无替代关系；本条与 L-006 同属"静默丢数据"家族，且都靠"断言条数/对比输入输出数量"才能暴露。

---

## L-008 — XcodeGen 工程的 `project.pbxproj` 与 `project.yml` 可能早已不同步：改 spec 后**不要盲目** `xcodegen generate`

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` |
| **引入版本** | 1.1.0 |
| **关联执行** | `run-20260919-hosts-sync-and-browser-consolidation`（本会话在 `xiyuWebBrowser` 实测） |
| **场景** | 需要修改 XcodeGen 工程（`project.yml`）里的某个 Build Phase / 设置，按"spec 是唯一真相源"的直觉执行 `xcodegen generate` 就地重生成 |

**问题**：重生成会**顺带抹掉** `project.yml` 里没写、但 `pbxproj` 里真实存在的手工设置。
本会话实测 `xiyuWebBrowser`：`xcodegen generate`（2.46.0）除了目标改动外，还产生了三处无关改动——
1. `DEVELOPMENT_TEAM = T9P67M8S4K` → **`""`**（Xcode 里设过的签名 Team 被清空，直接破坏签名能力）；
2. `LD_RUNPATH_SEARCH_PATHS` 由数组形式被改写为空格连接的单串（语义近似但仍属噪声改动）；
3. 产物引用的 `explicitFileType` → `lastKnownFileType`（xcodegen 版本差异）。

**根因**：`pbxproj` 是**生成物**，但历史上有人直接在 Xcode GUI 里改过设置（如 Development Team），
这些改动**不会回写** `project.yml`。于是 spec 与生成物之间已经漂移，
"重新生成"等于用 spec（较旧/较薄）覆盖生成物（较新/较厚）→ 丢失 GUI 侧设置。

**解法**：改 XcodeGen 工程前先做一次"无害探测"——

```bash
# 1) 先看 spec 与现有生成物的真实差距（不改动工作区）
xcodegen generate --spec project.yml --project /tmp/xcodegen-check
#    ⚠️ 注意：换输出目录会让 group 的 path 变成相对路径（如 ../../Users/...），
#       比对这些差异时要能识别出这类"生成位置造成的假差异"

# 2) 差距里出现签名/Team/搜索路径等既有设置 → 判定为"spec 与 pbxproj 已不同步"

# 3) 若本轮只需改一处，改用"就地替换"最小化风险：还原 pbxproj 后，
#    只替换目标那一段（例如某个 Build Phase 的 shellScript 行），并复核差异行数
plutil -lint <工程>.xcodeproj/project.pbxproj   # 结构仍合法
git diff --numstat <工程>.xcodeproj/project.pbxproj   # 期望：极小（本项目实测 1 增 1 删）
```

同时**必须**在宿主侧登记这个"spec ↔ pbxproj 不同步"的事实，否则下一个人重生成时会踩同一颗雷。

**推广**：任何"声明式 spec + 生成物入库"的组合（XcodeGen / Tuist / 各类 codegen）都有这个风险。
判据很简单：**生成物是否被人手工编辑过**——若 `git log` 显示生成物有非生成来源的改动，就不能盲目重生成。

**保留的既有经验**：无替代关系；本条是宿主工程侧的坑，与 `OPEN-001`（Xcode 不热加载共享 scheme）同属
"改宿主 Xcode 接线前必须先验证"的范畴（`STATUS.md` §6.2 / §7）。

---

## 条目写作格式

```markdown
## L-009 — `set -o pipefail` 下 `A | grep -q` 这类「读端提前退出」的管道会让条件**反向判假**

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` |
| **引入版本** | 1.2.0 |
| **关联执行** | `run-20260919-release-tag-sync-target`（`sync-hosts.sh` 名单重复检查） |
| **场景** | 用 `jq … \| grep -qx "$name"` / `… \| head -n 1` 之类管道在 `if` 里做判断，脚本开了 `set -euo pipefail` |

**问题**：读端在命中后立即退出（`grep -q`、`head -n 1`）会关闭管道读端，写端进程随即收到 `SIGPIPE`
并以 **141** 退出。`set -o pipefail` 取最右侧非零退出码 → **整条管道判为非零** →
`if …; then` 走到 else 分支。后果是**逻辑反向**：

```bash
# 想拒绝重复登记，实际会把重复项放行（141 被当成「没找到」）
if registry_names | grep -qx "$ADD_NAME"; then die "已存在"; fi
```

本会话实测：`sync-hosts.sh` 的 `--add` 重复检查与 `--remove` 存在性检查都写作这种管道。
当前名单只有 3 条（输出远小于 64KB 管道缓冲），写端先跑完、不触发 SIGPIPE，
所以**症状被数据量掩盖**——属潜在缺陷，不是已复现故障。

**解法**：把判断移进被调工具本身，或用纯 bash，彻底不产生管道。

```bash
registry_has() { jq -e --arg n "$1" 'any(.hosts[]?; .name == $n)' "$REGISTRY" >/dev/null 2>&1; }
# 取「第一行」也别用 head：
t="$(git tag --list 'v[0-9]*' --sort=-v:refname)"; first="${t%%$'\n'*}"
```

**推广**：在 `pipefail` 脚本里，凡是「写端是多行输出、读端可能提前退出」的管道都要警惕。
安全的读端是**会读完输入**的（`grep` 不带 `-q`、`awk`、`while read`）；`-q` / `-m1` / `head` / `wc -l`（部分场景）
都可能提前退出。判据：**这条管道在输入变大时，行为会不会变**——会变，就是隐患。

---

## L-010 — git 钩子没有 `post-tag`：**「提交」与「打标签」是两个事件**，发布流程不能只靠钩子

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` |
| **引入版本** | 1.2.0 |
| **关联执行** | `run-20260919-release-tag-sync-target` |
| **场景** | 想用 `post-commit` 钩子实现「打了发布标签就自动把下游仓库推到该版本」 |

**问题**：git 只有 `post-commit` / `post-checkout` / `post-merge` / `post-rewrite` / `pre-push` 等，
**没有 `post-tag`**。而发版的常规顺序是「先 `git commit`，再 `git tag`」——
`git tag` 只是新建一个 ref，**不产生 commit**，因此 `post-commit` 根本不会因打标签而触发。
本会话第一版钩子就写成「HEAD 落在发布标签上就 apply」：逻辑自洽，但**在常规顺序下永远不触发**，
只有「先打标签、再提交」这种非常规路径才会命中——等于形同虚设。

**解法**：把「发布」做成**显式命令**，钩子降级为兜底。

```bash
bash sync-hosts.sh --tag v1.2.0 --apply    # 主路径：一条命令完成「打标签 + 推下游」
# post-commit 钩子只覆盖「提交时 HEAD 已带标签」的非常规路径，作兜底
```

**推广**：设计基于 git 钩子的自动化前，先确认**钩子存在**且**触发时机与业务事件对齐**。
「打标签」「推送」「分支创建」都不产生 commit，`post-commit` 一律不触发；
需要在这些事件上挂钩时，只能靠显式命令、或 `pre-push` / CI 这类切入点。

---

## L-011 — `$VAR` 紧跟 CJK 字符时，**bash ≥ 5.2** 会把多字节字符吞进变量名（bash 3.2 反而正常）——并订正本项目先前的错误归因

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` |
| **引入版本** | 1.2.0（订正 1.1.0 的归因） |
| **关联执行** | `run-20260919-release-tag-sync-target`（本轮新增静态检查后扫出） |
| **场景** | 脚本里写 `echo "提示（指向: $VAR），其余"` / `ERROR_MSG="…: $VAR（仅支持 …）"` 这类「变量后紧跟全角字符」的文案 |

**事实（字节级实测，同一脚本分别用两个解释器跑）**：

```bash
# 脚本内容：V=abc; printf 'A:[%s]\n' "$V）tail"
/bin/bash      →  A:[abc\357\274\211tail]      # 3.2.57：正确，变量在 CJK 前结束
/opt/homebrew/bin/bash → A:[\274\211tail]       # 5.3.15：abc 整个消失，且 ） 的首字节 357 被吃掉
LC_ALL=C /opt/homebrew/bin/bash → A:[abc\357\274\211tail]   # 显式 C locale 时不触发
```

**根因**：bash **5.2 起**变量名解析支持多字节字符，于是 `$V）` 被当作 **一个** 变量名
（`V` + `）` 的首字节），该变量未定义 → 展开为空；被吞掉的首字节还让后续字节错位，
所以输出会同时出现「值消失」与「乱码」。locale 是开关：显式 `LC_ALL=C` 正常；
而本机 `LANG="" LC_CTYPE=C`（locale 实际未设置）这种形态下 5.3 **仍会**触发。

**订正先前归因**：本项目此前把它记成「**bash 3.2** 在多字节字符前会吞掉变量名」
（见 `experience/execution-log.json` 的 `run-20260919-hosts-sync-and-browser-consolidation` → findings）。
实测**恰好相反**：3.2.57 正确、5.3.15 出错。修法（紧跟 CJK 一律写 `${VAR}`）不变，
但**归因会影响排障方向**——若按「3.2 有 bug」去找，会完全找不到问题（因为 shebang 指向的 3.2 本来就正常）。

**解法**：变量后紧跟非 ASCII 一律写 `${VAR}`；并用静态检查兜底：

```bash
python3 - <<'PY'
import re, pathlib
pat = re.compile(r'\$([A-Za-z_][A-Za-z0-9_]*)(?=[^\x00-\x7f])')
for f in ['sync-hosts.sh','link-skill.sh','archive_upload.sh','pgy_upload.sh']:
    for i, line in enumerate(pathlib.Path(f).read_text().splitlines(), 1):
        if line.lstrip().startswith('#'):   # 注释里的 $VAR 不会展开，可忽略
            continue
        if pat.search(line):
            print(f"{f}:{i} {line.strip()[:80]}")
PY
```

本轮即由此扫出并修掉两处**真实**缺陷（均为文案，不影响控制流）：
`link-skill.sh:76`（软链冲突提示会丢掉路径）、`pgy_upload.sh:422`（不支持的输入类型报错会丢掉输入路径）。
`pgy_upload.sh:37/568/751` 的命中都在注释里，无害。

**推广**：
1. macOS 上「同一个脚本」可能被**两个不同大版本**的 bash 执行——`./x.sh`（走 shebang `/bin/bash` = 3.2.57）
   与 `bash x.sh`（走 PATH 首位的 Homebrew bash 5.x）。**语言特性差异必须双解释器各跑一遍**，
   只测一个解释器得到的「通过」是不可靠的。
2. 这类缺陷只影响**文案**、不影响控制流，因此最难被发现——测试断言返回码与产物都不会报警，
   只有人读到「半截错误信息」时才会察觉。静态检查比等着发现更划算。

---

## L-012 — `IFS=$'\t'` 下 bash 的 `read` 会**折叠连续 tab**（jq 的 `split("\t")` 不会）→ 空列会让整行串位

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` |
| **引入版本** | 1.3.0（缺陷实际存在于 1.1.0–1.2.0） |
| **关联执行** | `run-20260919-unregistered-gitlink-apply` |
| **场景** | 脚本用 TSV 作为「循环之间的数据通道」：`printf '%s\t%s\t…'` 写文件 → 另一个 `while IFS=$'\t' read -r a b c …` 读回 |

**事实**：`pin` 为空时那一段写成连续两个 `\t`，读回时**后面所有列左移一格**：

```bash
bash -c 'IFS=$'"'"'\t'"'"' read -r a b c <<< $'"'"'\tX\tY'"'"'; printf "[%s][%s][%s]\n" "$a" "$b" "$c"'
# → [][X][Y]      ← 看似正常
printf 'A\t\tC\n' > /tmp/t.tsv
bash -c 'IFS=$'"'"'\t'"'"' read -r p q r < /tmp/t.tsv; printf "p=[%s] q=[%s] r=[%s]\n" "$p" "$q" "$r"'
# → p=[A] q=[C] r=[]      ← 空列被吞，C 落到 q，r 为空；整行左移
```

**根因**：tab 属于 **IFS 空白字符（IFS whitespace）**。POSIX 规定：*空白* 类 IFS 字符的连续序列
被当作**单个**分隔符，且首尾会被忽略；非空白分隔符（如 `:`）才保留空字段。
**这与 `jq` 的 `split("\t")` 不同**——jq 会保留空字段，所以同一份数据用 jq 解析是正确的、
用 bash `read` 解析却串位，两边对不上时会以为「文件写错了」。

**为什么难发现**：它只在**某些行**触发（该列恰好为空的行），而且症状出现在**下游的无关列**上——
本项目里的表现是 `state` 变成 `N`（其实是 dirty 列的值）、ACTION 变成 `skip:N`（dirty 的值被当成 state），
并被原样写进 JSON。只有当夹具里出现「pinned 为空」的宿主（`missing` / `not-a-submodule`）时才暴露。

**解法**：TSV 的每一列都必须非空——空值写占位符：

```bash
printf '%s\t%s\t%s\t%s\t…\n' \
    "$name" "$sub" "$pinned_short" "${behind:--}" …
#                                        ^^^^^^^^ 空值一律落到 '-'，绝不留空列
```

**推广**：
1. 以 TSV 作进程内数据通道时，把「所有字段非空」当作**不变量**，在写入处集中保证（而不是在读取处逐列容错）。
   并在写入处留注释说明**为什么**不能有空列——否则后人很容易把它「简化」回 `"$x"`。
2. 跨工具比对同一份数据时，若结果不一致，先怀疑**各解析器的空白/空字段语义**，而不是先怀疑数据本身。
   本仓库的对照记忆：`bash read` 折叠 tab，`awk -F'\t'` 与 `jq split("\t")` 保留空字段。
3. 与 L-006 同族：`read` 的边界行为（EOF 清空变量、IFS 空白折叠）都违反直觉，涉及 `read` 的代码要单独测。

---

## L-013 — `.gitmodules` 已入库但 gitlink 未登记 → 新克隆**静默**缺少该子模块（`update --init` 退出码仍为 0）

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` |
| **引入版本** | 1.3.0（检测与自动补登） |
| **关联执行** | `run-20260919-unregistered-gitlink-apply` |
| **场景** | 宿主仓库接入子模块时「登记只做了一半」：`.gitmodules` 进了 HEAD，gitlink 却没进索引/HEAD |

**形成方式**（本机真实发生过一次）：把 `.gitmodules` 单独 commit，或 `git rm --cached <子模块>` 之后没有重新 `git add`。
此时 `git submodule status` 输出**为空**（git 根本不认为存在这个子模块），
而目录仍在磁盘上、是合法的子模块 checkout（git dir 在宿主 `.git/modules/<name>` 下）。

**本地表现与真实危害（实测对比）**：

| 状态 | 本地 `git status` | 新克隆后 `git submodule status` | 子模块目录 | `submodule update --init` 退出码 |
| --- | --- | --- | --- | --- |
| 半套接入（未修） | 该目录显示为 **`??` 未跟踪** | **空** | **不存在** | **0（不报错、也不检出）** |
| 已补登 | 正常 | `<sha> sub (vX.Y.Z)` | 存在 | 0 |

**关键**：它不是「报错」而是**静默什么都不做**——CI / 新同事 `clone` 后一切「成功」，
直到构建时才发现引擎脚本缺失（`No such file or directory: …/pgy_upload.sh`）。
排查方向极易跑偏到「构建配置」而不是「登记不完整」。

**识别**：`git -C <宿主> ls-files -s -- <子模块路径> | awk '$1=="160000"'` 为空，
但 `git show HEAD:.gitmodules` 里有该 path，且目录是合法 checkout。
**与「vendored 副本」区分**（这决定了能不能自动修）：只有 git dir **落在宿主 `.git/modules/` 下**的，
才是「登记不完整」；随手放进去的独立 clone / 嵌套仓库补登它的 HEAD 没有意义
（该 commit 通常不在上游仓，补登完立刻变 `unknown-engine-commit`，反而制造「已登记」的假象）。

**解法**：补登 = `git -C <宿主> add -- <子模块路径>`（`git add` 对嵌仓库即写模式 `160000`）+ commit；
若 `.gitmodules` 也还没进 HEAD，把它一起纳入同一次 pathspec commit。
`sync-hosts.sh` 已把该状态实现为 `unregistered-gitlink` 并由 `--apply` 自动处理。

**推广**：判断「子模块接入是否完整」时，**看索引模式（`160000`）而不是看磁盘目录是否存在**。
目录在、文件在，都可能是假象；唯一可靠的是 gitlink 是否被登记。

---

## L-014 — 判定「远端没有 X」之前必须先看**退出码**：`2>/dev/null` 会把「命令失败」伪装成「空结果」

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` |
| **引入版本** | 无（方法论校准，2026-09-19 记入） |
| **关联执行** | `run-20260919-remote-tag-verification-calibration` |
| **场景** | 用一条查询命令的**空输出**去证明「远端不存在某物」（标签 / 分支 / 记录），且把 stderr 丢掉了 |

**事实（本机实测）**：本轮曾用

```bash
git ls-remote --tags origin 2>/dev/null | awk -F/ '{print $NF}' | grep -v '\^{}'
```

得到**空**输出，据此对使用者的结论是「远端一个标签都没有」。实际情况：

```bash
git ls-remote --tags origin
# 退出码 = 128
# stderr: fatal: could not read Username for 'https://codeup.aliyun.com': Device not configured
```

即**查询本身失败了**——sandbox 内 `credential.helper=osxkeychain` 无法解锁钥匙串、也没有交互终端
可提示输入。空输出是「没查成」，不是「没有」。

**判据（必须三个一起看）**：

| 退出码 | stdout | 结论 |
| --- | --- | --- |
| `0` | 有 `refs/tags/v*` | 标签**已 push** |
| `0` | **空** | 标签**确实不存在** ← 只有这一行才能下「没有」的结论 |
| `≠0` | 空 | **无法判定**（查询失败），必须排查原因，禁止当成「没有」 |

**为什么危险**：这是「失败被误读成判断依据」的典型——它让结论**反向**（把「没查到」说成「确认没有」），
而且**看起来证据充分**（命令跑了、输出为空、没有报错可见）。本仓已有同族条目：
L-009（`pipefail` 下 `grep -q` 让条件反向判假）。两者都是「工具层行为把失败/成功翻译错了」。

**另外：本地无法反推远端标签状态。** `git push` 会更新远程**跟踪引用**（`refs/remotes/origin/<branch>`，
reflog 里显示为 `update by push`），但 **push 标签不会产生任何本地引用**。
所以「分支推没推」可以本地查（`git rev-list --count origin/<branch>..HEAD` + reflog），
「标签推没推」**只能查远端**。本机沙箱查不了 → 这类结论必须交回有凭证的终端。

**解法**：

```bash
# 1) 判定性查询：不丢 stderr，先判退出码
if ! out="$(git ls-remote --tags origin 2>err.txt)"; then
    echo "查询失败，无法判定：$(cat err.txt)"; exit 1
fi
[ -n "$out" ] || echo "远端确实没有任何标签"

# 2) 使用者自查（有凭证的终端）
cd ~/xiyuyanhen/workProject/archive-pgy-uploader
git ls-remote --tags origin; echo "rc=$?"       # 看 rc 与是否出现 refs/tags/v1.1.0 等
```

**推广**：
1. **判定性**命令（用来下结论的）**一律不许 `2>/dev/null`**；`2>/dev/null` 只允许用在
   「失败有明确无害默认值」的地方（例如 `git rev-parse --quiet x 2>/dev/null || true` 取可选值）。
2. 见到「空结果」先问一句：**这是「查到了、为空」，还是「没查成」？** 两者必须由退出码区分。
3. 沙箱 / 非交互环境的凭证限制要**在写结论前**就想清楚——但要区分「**无法访问**」与「**无法核实**」：
   - **公开**远端（如 GitHub 公开仓）**可以**匿名查询：实测 `git ls-remote https://github.com/git/git 'refs/tags/v2.43.0'`
     返回 `rc=0` 并取到真实 tag SHA，**无需任何凭证**（直连与经镜像均可）。
   - **私有**远端会拿到 `HTTP 401` → git 转而索要用户名 → 无可用 helper / 无交互终端 → **退出码 128**。
     本机 codeup 的 `info/refs` 实测正是 **HTTP 401**（即**网络是通的**，纯粹缺凭证）。
   - 因此准确表述是「**本机沙箱无法核实私有远端的任何状态**」；本条初稿写的
     「沙箱无法核实任何远端状态」是**过度概括**，现予订正。
   - 凡结论依赖**私有**远端的查询，必须声明「未能核实」并交回有凭证的终端执行。
4. 本仓 `sync-hosts.sh` 已核实**不依赖网络**（无 `ls-remote` / `fetch origin`；`--apply` 只从本地
   `$ENGINE_DIR` 取对象），故不受此条影响。反过来说：**工具也不会替你确认标签是否已 push**（`OPEN-005`）。
5. **本机全局 `url.*.insteadOf` 会悄悄改写 URL，且 `insteadOf` 同样作用于 push**（只有 `pushInsteadOf`
   才专门区分推送）。本机实测：`https://github.com/foo/bar.git` 的 `get-url` 与 `get-url --push`
   **都**变成 `https://ghfast.top/https://github.com/foo/bar.git`。凡涉及「远端地址」的判断
   （尤其安全判断：凭证会发给谁），必须用 `git remote get-url --push <remote>` 看**实际生效的 URL**，
   而不是看 `git remote -v` 里存的字面值。

---

## L-NNN — <一句话标题>

| 字段 | 值 |
| --- | --- |
| **状态** | `verified` \| `fallback` \| `pending` \| `deprecated` |
| **引入版本** | 1.0.0 |
| **关联执行** | `run-YYYYMMDD-<slug>` |
| **场景** | <什么情况下会遇到> |

**问题**：<现象 + 影响>

**根因**：<为什么会这样>

**解法**：<具体怎么做，给出可复现的命令/步骤>

**保留的既有经验**：<本条目补充而非替代哪些条目；若替代，注明被替代条的 `superseded_by`>
```
