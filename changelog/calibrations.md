# 校准记录（calibrations）

> 本文件是 `STATUS.md` 校准记录（原 §9）的**单点真相**，从 `STATUS.md` 迁出（CR-012，2026-09-20）。
> 原因：校准事件随项目迭代无界增长，嵌在 `STATUS.md` 里会让「实现真相主文档」越来越重，
> 且违反本体系自身的「单点真相 + 指针」原则（L-011 / L-015）。
> **每次校准**（STATUS.md 与实现不一致 → 先校准）在本文**追加**一个 `### 9.N` 小节；
> `STATUS.md` §9 只留指针。与 `STATUS.md`（实现真相）、`changelog/CHANGES.md`（变更流水）、
> `experience/LESSONS.md`（经验）配合。

## 9.1 2026-09-19 首次基线（建立本文件时）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | 仓库现状核对 | 与 README / `skill/SKILL.md` 记述一致；无 TODO/FIXME 残留 | 据实登记 §2 能力表（C1–C10），未纳入"不做"范围的缺口登记为 `OPEN-003` / `OPEN-004` |
| 2 | 治理基线建立 | 由 `xiyu-project-governance` 脚手架生成 | 记 CR-001，版本记 1.0.0（现状快照语义见 STATUS §1） |
| 3 | `skill/SKILL.md` 编码缺陷 | 第 13 行含 2 个 UTF-8 替换字符（U+FFFD）：`测试\ufffd\ufffd员`，应为 `测试人员`；经 `git show HEAD:skill/SKILL.md` 确认**该乱码自 HEAD 起即存在**（历史遗留，非本次引入） | 记 CR-002 校准修正（不改运行行为，无版本变更） |
| 4 | `.gitignore` 凭证规则缺口 | 原文件仅忽略 `pgy_config.sh` / `*.log` / `.DS_Store`，缺 `.env*` 规则 | 在保留既有规则前提下追加 `.env*`（保留 `!.env.example`）与编辑器目录，纳入 CR-001 影响范围 |
| 5 | 工作区未提交改动 | 基线建立时存在上一会话遗留：`.workbuddy/memory/2026-08-0{6,7}.md` 追加、`skill/SKILL.md` 新增「Xcode GUI Archive Post-actions」章节 | 未回滚（属有效文档产出），随 CR-002 同批提交并在条目中注明 |
| 6 | 全局 gitignore 陷阱 | 本机 `~/.gitignore_global` 含 `.gitignore` 一行 | 本项目 `.gitignore` **已在版本控制内**（`git ls-files` 可见），故 `git check-ignore` 不命中、规则正常入库，无需处理 |

## 9.2 2026-09-19 v1.1.0 校准（多宿主接入收敛）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | 三宿主接入状态核查 | `xiyuScoreboard` = submodule（落后引擎 HEAD 4 个 commit）；`xiyu_todo_list` = submodule 但 gitlink 仅在索引（宿主从未 commit，落后 3 个）；`xiyuWebBrowser` = 文件复制且已漂移（缺治理目录、`skill/SKILL.md` 与引擎不一致） | 收敛 `xiyuWebBrowser` 为 submodule（CR-003）；另两处落后/未提交由 `sync-hosts.sh` 体检输出呈现，交由使用者决定何时同步（本轮未执行真实 `--apply`） |
| 2 | `xiyuWebBrowser` 副本内含真实密钥 | `pgy-archive-uploader/pgy_config.sh` 的 `PGY_USER_KEY` / `PGY_API_KEY` 已填实（长度 32、非占位符），但该文件被副本 `.gitignore` 忽略、**未入库**（无泄漏） | 记为**结构缺口**而非安全事故：把凭证与控制文件移出引擎目录到兄弟目录 `pgy-archive-config/`，并对 `pgy_config.sh` `chmod 600` |
| 3 | 引擎仓 `.git/hooks/` 目录不存在 | git 仓库允许没有 hooks 目录；直接写钩子文件会 `No such file or directory` | `sync-hosts.sh --install-hook` 改为先 `mkdir -p "$(dirname "$HOOK_FILE")"`；纳入经验条目 |
| 4 | `project.yml` ↔ `project.pbxproj` 不同步 | 就地 `xcodegen generate`（2.46.0）除目标改动外还会清空 `DEVELOPMENT_TEAM`、改写 `LD_RUNPATH_SEARCH_PATHS` | 本轮**不重生成**，改为就地替换 pbxproj 中目标 `shellScript` 段（实测差异 1 增 1 删）；沉淀为 L-008 并在 STATUS §6.2 警示 |
| 5 | 文档债 `OPEN-003` / `OPEN-004` | 与本版新增能力直接相关（新增入口同样硬依赖 `jq`；README 文件树还要再加一项） | 随 CR-004 一并关闭，见 STATUS §7「已关闭条目」 |
| 6 | 引擎 HEAD 未 push origin | `origin/master` 停在 `155046c`，本机 HEAD 为 `6fadcb2` | 不自动 push（push 由使用者主导）；在 CR-003 与 `changelog/v1.1.0.md` 中显式标注 `OPEN-005` 的影响面 |
| 7 | §4.1 输入契约示例含**真实 Bundle ID** | `TARGET_BUNDLE_ID=com.xiyu.browser` 出现在示例单元格，违反本仓 §2.2「不得写入真实 Bundle ID（示例一律用占位符）」；系基线建立时未剥离 | 校准修正为 `com.example.app`（仅文档，不改运行行为；同时纳入 CR-004 的影响范围） |

## 9.3 2026-09-19 v1.2.0 校准（同步目标改为发布标签驱动）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | 同步目标语义（使用者拍板） | v1.1.0 的默认目标是**本机 HEAD**，即「每提交一次就推进各宿主 pin」。实测两个**纯文档/记忆**提交（`6fadcb2`、`c6c32b4`）各引发一轮 3 宿主 gitlink 更新；上一轮为避免此副作用，记忆文件**故意未提交** | 默认目标改为 `release`（最新发布标签 `v*`），只有影响宿主调用行为的变更才推进标签；`local` / `origin` 保留为开发期与交接期逃生口 |
| 2 | 仓库**没有任何 git tag** | 新默认一上线会立刻不可用（无标签可跟）。CHANGELOG 原已声明 `v1.0.0` 是「治理基线快照，不是发布版本」 | 补打 `v1.1.0`（指向 `0734932`，第一个影响行为的发布；**不给 `v1.0.0` 打标签**，保持历史诚实）；并把「版本号 ↔ 发布标签」的绑定与判据写入 STATUS §1 与 §8.4 |
| 3 | 钩子语义与新默认**互相矛盾** | 原 `--auto` = 「每次提交后 `--apply`」；且**常规顺序是「先提交、后打标签」，而 `post-commit` 只对 commit 生效 → 钩子永远赶不上发布**（HEAD 在 commit 时尚未带标签） | ① 钩子改为「仅当 HEAD 正好是发布标签时才 `--apply`」，定位为**兜底**；② 发布主路径改为 `--tag vX.Y.Z --apply`（打标签 + 推宿主，一条命令）；③ `--tag` 单独使用时打印后续两步命令 |
| 4 | 状态机缺一个状态 | 原二值（`up-to-date` / `outdated`）无法表达「宿主 pin 是目标的**后代**」——当时 3 个宿主 pin 在 `c6c32b4`、而 v1.1.0 标签在 `0734932`，会被误判为 `diverged` | 扩为四值，新增 `ahead-of-target` 并定义为**良性**（宿主已含发布版本行为）：不计入「需人工处理」、`--check` 不因此返回 `2`；回落需显式 `--allow-downgrade` |
| 5 | 钩子的 `--check --quiet` 与文档记述不符 | 钩子注释写「落后时打印报告」，但 `--quiet` 会把报告一起吞掉，实际什么都不打印 | 改为「静默跑取退出码，仅当 `rc=2` 时重跑一次打印完整报告」；`rc=1`（出错）的 `die` 信息本就写在 stderr，不重复打印 |
| 6 | `jq … \| grep -q` 在 `set -o pipefail` 下的隐患 | 读端（`grep -q`）命中即退出 → 写端 `jq` 收 `SIGPIPE`(141) → pipefail 使条件判为「假」。名单重复登记检查会**反向放行**（当前 3 条数据量下不会触发，属潜在缺陷） | 改为 `jq -e 'any(...)'` 内联判定，去掉管道；`--only` 的字符串匹配也改为纯 bash 循环（顺带支持多值与空格容错） |

## 9.4 2026-09-19 校准（CR-006：全角字符吞变量名 + bash 版本归因订正）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | 静态检查扫出两处**真实**缺陷 | `link-skill.sh:76`（软链冲突提示会丢路径）、`pgy_upload.sh:422`（不支持的输入类型报错会丢输入路径）。均为**文案**，不影响控制流 | 改为 `${VAR}`（各 1 行）；记 CR-006（无版本变更）。`pgy_upload.sh:37/568/751` 的同类命中都在注释里，不展开、无需改 |
| 2 | **归因订正**（重要） | 本项目此前记为「**bash 3.2** 在多字节字符前会吞掉变量名」（`execution-log.json` → run-20260919-hosts-sync-and-browser-consolidation）。字节级实测**恰好相反**：`/bin/bash` 3.2.57 正确输出 `[abc\357\274\211tail]`，`/opt/homebrew/bin/bash` 5.3.15 输出 `[\274\211tail]`（值消失 + 字节错位）。根因是 **bash ≥ 5.2 的变量名解析支持多字节字符**；显式 `LC_ALL=C` 不触发，而本机 `LANG="" LC_CTYPE=C` 形态下 5.3 仍触发 | 新增 L-011 记录正确机制与订正说明；在 CR-006 中显式标注「修法不变、归因反转」，避免后人按错方向排障 |
| 3 | **验证盲区**：单解释器验证 | 本项目脚本 shebang 为 `/bin/bash`（3.2.57），但此前一律用 `bash xxx.sh` 验证（PATH 首位 = Homebrew bash 5.x）。两个大版本语言特性不同 | 自本版起，逐文件语法与关键行为**双解释器各跑一遍**（3.2 + 5.x）；已写入 L-011 推广段。`sync-hosts.sh --check` 在两者下输出与退出码一致（已实测） |

## 9.5 2026-09-19 v1.3.0 校准（`unregistered-gitlink` 补登 + tab 折叠串列）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | `unregistered-gitlink` 的危害描述失准 | 实现初稿把后果写成「`git submodule update --init` 会失败（硬故障）」。实测**不是失败**：该命令**退出码 0、不报错、也不检出**，克隆里子模块目录根本不出现 → 属**静默**失效（对构建的破坏更晚、更难查） | 订正脚本头部注释、状态采集处注释与 `--check` 提示文案；并把 A/B 实测表写入 STATUS §3.3 |
| 2 | **`--apply` 存在 tab 折叠导致的整行串列**（既有缺陷，被新状态照出） | rows.tsv 用 `\t` 分隔；`pinned` 为空时写出连续两个 `\t`，而 **tab 属 IFS 空白字符 → bash 的 `read` 把连续分隔符折叠成一个**（jq 的 `split("\t")` 不折叠，故二者行为不同）。结果：`--apply` 循环里其后所有列左移一格 → `state` 变 `N`、ACTION 变 `skip:<dirty值>`，并原样写入 JSON `hosts[]` | 所有列一律写非空占位符（`${pinned:--}`），并在该 printf 上方加注释说明「为何不能有空列」；实测 `not-a-submodule` 宿主在修复前后 ACTION 由 `skip:N` 变为 `skip:not-a-submodule` |
| 3 | 自动补登的**安全边界** | 若不加限制，`git add` 会把「随手放进目录的 vendored 副本 / 嵌套仓库」也补登成 gitlink——而该 commit 通常不在引擎仓，补登完立刻是 `unknown-engine-commit`，制造假象 | 新增 `is_submodule_checkout()`：仅当子模块的 git dir 落在宿主 `.git/modules/` 下才认定可补登；否则维持 `not-a-submodule` 并提示走 `git submodule add`。反向对照夹具（vendored 副本）已实测不被登记 |
| 4 | `uncommitted-gitlink` 是否也自动提交 | 该状态是「人已 `git add`、只差 commit」，可能正处于人工编辑中间态 | **刻意不自动处理**，维持人工提示（不猜测人的意图） |
| 5 | 发布后对使用者陈述「远端一个标签都没有」 | **错误结论**：依据是 `git ls-remote --tags origin 2>/dev/null` 的空输出，而该命令实际**退出码 128**（`could not read Username` —— sandbox 内 keychain 不可用且无交互终端）。**空输出是「查询失败」而非「结果为无」**，结论方向相反且未经核实 | 记 CR-008（无版本变更）；新增 L-014 固化判据「`rc=0 且空` 才等于确实没有」；同步订正记忆中的该条陈述；并澄清「push 分支会更新远程跟踪引用（可本地反推）、**push 标签不产生任何本地引用（只能查远端）**」。脚本已核实不依赖网络，故不受影响 |

## 9.6 2026-09-19 校准（CR-008：远端标签状态的判定依据）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | 「远端没有标签」的结论未经核实 | 该结论由**查询失败**（`ls-remote` rc=128）的空输出推出，属「把失败误读成判断依据」（同族：L-009）。它让结论**反向**，且**看起来证据充分**（命令跑了、输出为空、无可见报错） | 订正记忆中的陈述为「**无法判定**，需使用者在有凭证的终端核实」；新增 L-014 记录判据与推广（判定性命令禁止 `2>/dev/null`） |
| 2 | 提交是否已 push | **是**：`origin/master == HEAD == 9d3aa18`，且 reflog 最新一条为 `9d3aa18 refs/remotes/origin/master@{0}: update by push`。此前记忆里「领先 1 个提交」已过期 | 更新记忆为「已 push」；并在 L-014 中记录「分支状态可本地反推、标签状态不可」 |
| 3 | 脚本是否受同类风险影响 | **否**：已核实 `sync-hosts.sh` 无 `ls-remote` / `fetch origin`，`--apply` 只从本地 `$ENGINE_DIR` 取对象，全程离线可用 | 无需改动；但须明确「工具也不会替你确认标签是否已 push」（`OPEN-005`） |

## 9.7 2026-09-19 校准（CR-009：远端可核实性的实测边界 + 本机全局 URL 重写）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | L-014 的「沙箱无法核实**任何**远端状态」是过度概括 | 实测：**公开**远端可**匿名**查询——`git ls-remote https://github.com/git/git 'refs/tags/v2.43.0'` 返回 `rc=0` 与真实 tag SHA（直连与经镜像结果一致）。故准确表述是「无法核实**私有**远端的任何状态」 | 订正 L-014 第 3 条（区分「无法访问」与「无法核实」）；本节留痕 |
| 2 | 私有远端的失败形态有确切证据 | 本机 codeup 的 `info/refs?service=git-upload-pack` 返回 **HTTP 401** → 即**网络是通的**，纯粹缺凭证（此前只能推断） | 记入 L-014 第 3 条；`OPEN-005` 的处置补充见下 |
| 3 | 沙箱内是否有 GitHub 凭证通道 | **无**：`gh` 未安装、`GITHUB_TOKEN`/`GH_TOKEN`/`GIT_TOKEN`/`GITHUB_PAT` 均未设置、`~/.config/gh/hosts.yml` 不存在 | 记录为事实；故「切到私有 GitHub 仓」仍不能解决沙箱核实问题 |
| 4 | 本机全局 `url.*.insteadOf` 会**同时改写 fetch 与 push** | 全局配置含 `url.https://ghfast.top/https://github.com/.insteadof https://github.com/`。仅设 `insteadOf`（无独立 `pushInsteadOf`）→ 临时仓库实测 `get-url` 与 `get-url --push` **都**变成 `ghfast.top/...`。含义：若把本仓远端指向 GitHub，**推送凭证会经第三方加速镜像** | 记入 L-014 第 5 条：涉及远端地址的判断（尤其安全判断）必须用 `git remote get-url --push <remote>` 看**实际生效** URL，不能只看 `git remote -v` 的字面值。切换远端前需先评估/处理该重写 |
| 5 | 另一条全局规则指向不存在的本地路径 | `url.file:///tmp/SDWebImage.insteadof https://github.com/SDWebImage/SDWebImage.git`，而 `/tmp/SDWebImage` **当前不存在**（`/tmp` 重启即清）→ 任何对 SDWebImage 的取用会被改写到 `file:///tmp/SDWebImage` 并失败，报错信息与「远端不可达」无关 | 留档备查（不属本仓改动）；若日后遇到 SDWebImage 相关拉取异常，先查这条规则 |
| 6 | `--target origin` 在换远端后的行为 | 脚本用 `symbolic-ref refs/remotes/origin/HEAD`，缺失时回落 `origin/master`（已核实代码路径：`sync-hosts.sh:422-423`）；但**换 URL 后未 fetch 之前，`origin/master` 仍是旧远端的陈旧值**，脚本不会崩、却可能给出**过期的目标** | 记入本文档；切换远端后应先 `git fetch`（并 `git remote set-head origin -a` 或确认 `origin/HEAD`）再使用 `--target origin` |

**`OPEN-005` 处置补充（本条不改变其 `by-design` 状态，仅收窄可执行的规避步骤）**

本轮实测把 `OPEN-005` 的规避方案从一句「需人工 push」细化成三步，**根因不变**（本机沙箱无私有远端凭证，push 与标签确认只能由使用者完成）：

1. **push 标签后无法在本机自证**——`git push` 只更新远程跟踪引用（分支可反推），**push 标签不产生任何本地引用**，故「标签推没推」只能查远端。`sync-hosts.sh` 也不代查（无 `ls-remote`），即**工具永远不会替你确认 release 标签是否已 push**。
2. **远端换成公开 GitHub 仓可解，换成私有仓不可解**——沙箱对**公开**仓可匿名 `ls-remote` 自证；**私有**仓（含私有 GitHub 仓）仍为 `HTTP 401 → rc 128`，因沙箱无任何 GitHub 凭证通道（`gh` 未装、无 token 变量、无 `hosts.yml`）。
3. **换远端地址前先处理全局 `insteadOf` 重写**——本机全局规则会把 `https://github.com/` 改写为 `https://ghfast.top/https://github.com/`，且该重写**同时作用于 push**。这意味着改远端后**推送凭证会经第三方加速镜像**；同时未 `git fetch` 前 `origin/master` 是旧远端的陈旧值，会让 `--target origin` 给出过期目标。切换远端后请按 §9.7 第 6 行先 `git fetch`、并用 `git remote get-url --push origin` 确认实际生效 URL。

## 9.8 2026-09-19 变更（CR-010：`origin` 由 codeup 替换为公开 GitHub 仓）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | `origin` 替换 | 已执行 `git remote set-url origin git@github.com:xiyuyanhen/archive-pgy-uploader.git`；`git remote -v` 的 fetch/push 均为该 SSH 地址 | 本节留痕；STATUS §5 表格与 frontmatter `repository` 同步更新 |
| 2 | **SSH 形式天然绕开全局 `insteadOf` 重写**（CR-009 曾警告的点） | **已实测**：`git remote get-url --push origin` 原样返回 `git@github.com:...`，未被改写。原因：全局规则是 `url.https://ghfast.top/https://github.com/.insteadof https://github.com/`，只匹配 `https://github.com/` 前缀，**不匹配 `git@github.com:`** → 推送凭证**不会**经 ghfast.top 镜像 | 选 SSH 而非 HTTPS 是本轮的实际收益；日后若改回 HTTPS 需重新评估该重写 |
| 3 | 沙箱内能否推送 | **不能**。`~/.ssh/id_ed25519`（注释 `xiyuyanhen@163.com`）**带口令**（`ssh-keygen -y -P ""` 失败），且 `ssh-add -l` → `The agent has no identities`；`ssh -T git@github.com` → `Permission denied (publickey)`。网络与 22 端口**是通的**（已收到服务端拒绝，非超时） | push 仍由使用者在其终端完成（与 STATUS §3 用户主导 push 一致）；`OPEN-005` 的「需人工 push」结论不变，仅理由从「无 codeup 凭证」改为「无可用非交互密钥身份」 |
| 4 | 目标仓当前状态 | **存在且为空**：匿名 `git ls-remote https://github.com/xiyuyanhen/archive-pgy-uploader.git` → `rc=0` 且输出为空。**配对照**：查询不存在的仓 → `rc=128` + `fatal: could not read Username`。故 rc=0+空 是「仓在、无任何 ref」，非「查不到」 | 使用者推 `master`（及标签）后即可正常同步 |
| 5 | 公开前的泄密预检（因目标仓为 **Public**） | **通过**：对全部 25 个跟踪文件扫描 `PGY_API_KEY=`/`PGY_USER_KEY=` 实值、`sk-`、`ghp_`、JWT(`eyJ`)、`-----BEGIN … PRIVATE KEY`、token 赋值、邮箱、手机号、内网 IP、隧道域名 → **零命中**；`.gitignore` 已排除 `pgy_config.sh` / `.local/` / `.env*`。**但**：`.workbuddy/memory/*.md` 与 `execution-log.json` 被跟踪，其中含**内部宿主项目名**（xiyuScoreboard / xiyu_todo_list / xiyuWebBrowser）、本机绝对路径、codeup 命名空间 URL | 已向使用者提示该暴露面；是否把记忆移出版本控制由其决定（本轮**不擅自改动**） |
| 6 | 换远端后的陈旧远程跟踪引用 | `refs/remotes/origin/master` 仍为换 URL 前从 codeup 取到的 `2dbc1a0`（线上 GitHub 实际为空）→ 此刻它**不代表 GitHub 状态**（正是 §9.7 第 6 行预警的情形）。本轮**不删该引用**（非破坏性原则，且它是 codeup 最后状态的唯一本地记录） | 使用者 push 后执行 `git fetch origin && git remote set-head origin -a`，该引用即被修正为 GitHub 真实状态 |
| 7 | 三个宿主的子模块地址**尚未**跟随 | 各宿主 `.gitmodules` 内仍写 codeup 地址（本轮只改引擎自身 `origin`，未动宿主）。含义：**新克隆宿主时引擎仍从 codeup 拉取**，而引擎新提交推往 GitHub → 两边分叉 | **遗留决策**（未擅自改）：若确定迁移到 GitHub，需同步改写 3 个宿主 `.gitmodules` 的 url 并各自提交。列入 `OPEN-006` |

## 9.9 2026-09-20 变更（CR-011：push 已核实 + OPEN-006 整体迁移完成 + 验证方法订正）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | **push 结果（公开仓首次可自证）** | 已核实：匿名 `git ls-remote https://github.com/xiyuyanhen/archive-pgy-uploader.git` → `refs/heads/master` = `98eef5e`（= 本机 HEAD）；`v1.1.0` / `v1.2.0` / `v1.3.0` 三个标签均在，且 `v1.3.0^{}` = `dd06073` 与 STATUS §1 记载一致 | 长期悬置的「标签推没推」在本仓**已可自证**（这是迁移到公开仓的直接收益）；`OPEN-005` 的「无法自证」限制在本仓转为「已可自证」 |
| 2 | 陈旧远程跟踪引用已修正 | `origin/master` 原为 codeup 遗留 `2dbc1a0`（不代表 GitHub）→ 现为 `98eef5e`，`git rev-list --left-right --count origin/master...HEAD` = `0 0` | 因 `origin` 是 SSH 且本机无法非交互认证，`git fetch origin` 不可用 → 改用**匿名 HTTPS 显式取**：`git fetch https://github.com/xiyuyanhen/archive-pgy-uploader.git '+refs/heads/*:refs/remotes/origin/*'`，再 `git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master` |
| 3 | `OPEN-006` 整体迁移执行 | 3 个宿主的 `.gitmodules` 与宿主 `.git/config` 的 `submodule.<name>.url` 全部改指 `https://github.com/xiyuyanhen/archive-pgy-uploader.git`；`git submodule sync -- <path>` 一并同步 `.git/modules/<name>/config` 的 origin。**gitlink 全程未变**（仍 `160000 → dd06073`），各宿主仅 `.gitmodules` 一处改动 | 宿主侧本地提交（不 push）：`xiyuScoreboard 0e69d28`、`xiyu_todo_list 7d2d3ba`、`xiyuWebBrowser 05ee675`；`.local/hosts.json` 的 `engineRemote` 同步更新（该字段**无逻辑依赖**，仅 init 时写入） |
| 4 | **端到端证明（迁移是否真的成立）** | 全新克隆 `xiyu_todo_list`（`--no-checkout` + `git read-tree HEAD` 建索引）后执行 `git submodule update --init -- ios/Scripts/archive-pgy-uploader` → stderr 显示 `Submodule ... (https://github.com/xiyuyanhen/archive-pgy-uploader.git) registered`，随后 `checked out 'dd0607310aeafc4bf441852549750dedbfa773fd'`、**退出码 0**（全程匿名，无任何凭证） | OPEN-006 关闭（见 STATUS §7 已关闭条目） |
| 5 | **验证方法本身出过一次错，已订正** | 首次验证用 `git clone --no-checkout` 后直接 `git ls-files -s` / `git config -f .gitmodules`，得到 **空结果与 pathspec 报错**，一度像是「gitlink 未登记」——实际是 `--no-checkout` **不建索引**（`ls-files` 读索引故为空；`submodule` 找不到 pathspec） | 改为 `--no-checkout` 后先 `git read-tree HEAD` 建索引再验；沉淀为 `experience/LESSONS.md` **L-015**。**「空结果」又一次差点被当成结论**（L-014 同族，但这次根因不是丢 stderr，而是**前置状态未建立**） |
| 6 | 存储值 vs 生效值（两层都出现） | `.git/modules/<sub>/config` 与 `.gitmodules` 的**存储值**是干净的 `https://github.com/...`；`git remote get-url` 显示的**生效值**是 `https://ghfast.top/https://github.com/...`（被全局 `insteadOf` 改写） | 对**公开**仓的**只读**取用，镜像重写**无害**（不涉及凭证）；但报告与排障时须区分这两个值，避免把生效值误当成配置写错了 |
| 7 | 公开暴露面决策（使用者 2026-09-20 确认） | 使用者确认：`.workbuddy/memory/` 与 `experience/execution-log.json` 中的**内部项目名属测试项目**，可继续公开；**后续不再提交其它隐私信息** | 本仓保留现有跟踪范围不变；后续新增内容遵守该约定（写入项目记忆） |
