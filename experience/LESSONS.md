# 执行经验条目（累积式，禁止删除已验证内容）

> 最后更新：2026-09-19 | 当前项目版本：1.0.0

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

## 条目写作格式

```markdown
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
