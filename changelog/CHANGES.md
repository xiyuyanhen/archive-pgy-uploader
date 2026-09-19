# CHANGES.md — 变更流水（追加式，禁止删除）

> 本文件记录 `archive-pgy-uploader` 的**每一次**功能变更、规范性变更与校准修正。
> **新条目追加到文件顶部**，编号 `CR-NNN` 单调递增，已写入条目不得删除或改写（需更正时追加一条反向变更）。
> 与 `STATUS.md`（实现真相 + 交接）和 `changelog/vX.Y.Z.md`（版本档案）配合使用，职责边界见 `STATUS.md` §8.1。

## 条目模板

```markdown
## CR-NNN — <一句话标题>

- **变更时间**：YYYY-MM-DD
- **变更类型**：功能变更 | 规范性变更 | 校准修正
- **关联版本**：vX.Y.Z（无版本变更时写「无」）
- **变更原因**：<为什么改，关联 OPEN-XXX / L-XXX / CR-XXX>

**变更前后差异**

| 项 | 变更前 | 变更后 |
|----|--------|--------|
| ... | ... | ... |

**影响范围**：<受影响的文件 / 脚本 / 调用方式>
**兼容性说明**：向后兼容 | 破坏性变更（调用方需调整：<具体内容>）
**验证方式**：<可复现的命令或检查项>
```

---

## CR-008 — 校准：订正「远端无标签」的错误结论，并沉淀「空结果 vs 查询失败」判据（L-014）

- **变更时间**：2026-09-19
- **变更类型**：校准修正（**无版本变更**）
- **关联版本**：无
- **变更原因**：CR-007 发布后，我向使用者陈述「远端一个标签都没有」，依据是
  `git ls-remote --tags origin 2>/dev/null` 的**空输出**。使用者追问判定依据后复核发现：该命令**退出码 128**，
  stderr 为 `fatal: could not read Username for 'https://codeup.aliyun.com': Device not configured`
  （sandbox 内 `credential.helper=osxkeychain` 无法解锁、也无交互终端）。**空输出是「查询失败」，不是「结果为无」**
  —— 结论**反向**且未经核实。同时澄清：`origin/master` 的 reflog 显示
  `9d3aa18 … update by push`，提交**已 push**（此前记的「领先 1 个提交」已过期）。

**变更前后差异**

| 项 | 变更前（错误陈述） | 变更后（校准） |
|----|--------|--------|
| 远端标签状态 | 「远端一个标签都没有」 | **无法判定**——本机沙箱无 codeup 凭证，`ls-remote` 退出码 128。需使用者在有凭证的终端执行 `git ls-remote --tags origin; echo rc=$?` |
| 判定依据 | 命令的空输出 | 空输出 + 退出码**共同**判定：`rc=0 且空` 才是「确实没有」；`rc≠0` 一律记为「无法判定」 |
| 提交推送状态 | 「领先 `origin/master` 1 个提交」 | 已 push（`origin/master == HEAD == 9d3aa18`，领先 0） |
| 本地可否反推标签 | 未说明 | 明确：`push` 会更新远程**跟踪引用**（分支可本地反推，reflog 记 `update by push`），但 **push 标签不产生任何本地引用** → 标签状态只可能查远端 |

**影响范围**：仅文档/记忆——`experience/LESSONS.md`（新增 L-014）、`STATUS.md`（§9.6）、
`changelog/CHANGES.md`、`experience/execution-log.json`、`.workbuddy/memory/`。
**脚本零改动**（已核实 `sync-hosts.sh` 不含 `ls-remote` / `fetch origin`，不依赖网络）。

**兼容性说明**：无行为变化，**不升版本、不打标签**（宿主仍 pin `v1.3.0`）。

**验证方式**：

```bash
# 复现「空输出 ≠ 没有」：
git ls-remote --tags origin 2>err.txt; echo "rc=$?"; cat err.txt   # rc=128 + could not read Username
# 确认脚本无网络依赖：
grep -n "ls-remote\|fetch origin" sync-hosts.sh || echo "无（脚本不依赖网络）"
# 确认提交已 push（本地可查）：
git reflog show origin/master | head -3      # 最新一条应为 update by push
git rev-list --left-right --count origin/master...HEAD   # 0  0
```

---

## CR-007 — `--apply` 支持自动补登「半套接入」（`unregistered-gitlink`）；修复 tab 折叠导致的整行串列

- **变更时间**：2026-09-19
- **变更类型**：功能变更 + 缺陷修复
- **关联版本**：v1.3.0
- **变更原因**：上一轮真实修复 `xiyu_todo_list` 时发现一种「半套接入」形态——`.gitmodules` **已入库**、目录是合法的子模块 checkout（git dir 在宿主 `.git/modules/` 下），但 **gitlink 既不在索引也不在 HEAD**（`git submodule status` 为空）。本地 `git status` 只把该目录显示成未跟踪，看不出异常；当时只能手工 `git add` + commit 修。工具把该状态判为 `not-a-submodule` 并拒绝处理，属能力缺口。同批被该状态的夹具照出一个**既有缺陷**：`--apply` 的 rows 读回因 tab 折叠而整行串列（详见差异表 2）。

**变更前后差异**

| 项 | 变更前 | 变更后 |
|----|--------|--------|
| 状态识别 | 该形态落入 `not-a-submodule`（误导：它不是「没有子模块」，而是「登记不完整」） | 新增独立状态 `unregistered-gitlink`；`--apply` 自动补登 |
| `--apply` 处理范围 | 仅 `outdated` | `outdated` +（新增）`unregistered-gitlink`；两者共用同一套前置检查（`precheck_actionable` 去重，行为不变） |
| 补登语义 | — | 落后于目标则先 `fetch` + `checkout --detach <目标>` 再补登（一条命令完成「补登 + 对齐」）；`ahead` 则按当前 HEAD 补登；`unknown`/`diverged` 只补登并提示版本关系未定 |
| 补登安全边界 | — | 新增 `is_submodule_checkout()`：仅当子模块 git dir 落在宿主 `.git/modules/` 下才补登。vendored 副本 / 嵌套仓库不被误补登，仍报 `not-a-submodule` 并提示走 `git submodule add` |
| `.gitmodules` 尚未入库时 | — | 一并纳入本次提交（pathspec 含 `.gitmodules`）；已在 HEAD 时不动它（实测提交恰为 1 行 gitlink 变更） |
| JSON `summary` | `{total, outdated, ahead_of_target, attention}` | 增加 `unregistered` 字段 |
| JSON `status` | `ok` / `outdated` / `attention` / `error` | 增加 `unregistered`（在 `outdated` 之后、`attention` 之前判定） |
| `--check` 退出码 | `OUTDATED>0` 或 `ATTENTION>0` → `2` | 增加 `UNREG>0` → `2`（属「可自动处理」，与 `outdated` 同级） |
| **缺陷：rows 串列** | `pinned` 为空时写出连续两个 `\t`；**tab 属 IFS 空白字符 → bash 的 `read` 把连续分隔符折叠成一个**（jq 的 `split("\t")` 不折叠，二者行为不同）→ `--apply` 循环内其后所有列**左移一格**：`state` 变成 `N`、ACTION 变成 `skip:<dirty值>`，并原样写入 JSON `hosts[]` | 所有列一律写非空占位符 `-`（`${pinned:--}`），并在 printf 上方加注释说明「为何不能有空列」。实测 `not-a-submodule` 宿主：`skip:N` → `skip:not-a-submodule` |
| `--check` 提示 | 无该状态的专门提示 | 单独列出（该状态本地极易漏看），文案含实测结论：**新克隆会静默缺少该子模块**（`update --init` 退出码 0、不报错、不检出） |

**影响范围**：`sync-hosts.sh`（状态机 / `--apply` / JSON / 退出码 / 提示文案）；`STATUS.md`（能力 C13、§3.3、§9.5）；`README.md`（跟随同步章节）；`changelog/v1.3.0.md`。**不影响**宿主调用链（`archive_upload.sh` / `pgy_upload.sh` / `link-skill.sh` 零改动）。

**兼容性说明**：向后兼容。新增状态值与 JSON 字段为**追加**语义；`--check` 退出码 `2` 的含义由「有落后/需人工介入」扩为「有落后 / 半套接入 / 需人工介入」——消费者若把 `2` 解读为「执行 `--apply` 即可」，行为**更**准确（这类项目确实可被 `--apply` 修复）。
**注**：`uncommitted-gitlink`（人已 `git add`、只差 commit）**刻意不自动处理**，维持人工提示，避免猜测人的意图。

**验证方式**：

```bash
# 1) 静态：双解释器语法 + CJK 花括号（排除注释）
for f in sync-hosts.sh archive_upload.sh pgy_upload.sh link-skill.sh; do
  /bin/bash -n "$f" && /opt/homebrew/bin/bash -n "$f"; done

# 2) 夹具 A/B（/tmp/pgy-unreg*）：构造 4 种宿主形态
#    host-a 半套接入(子模块=引擎HEAD) / host-b 半套接入+落后 / host-c .gitmodules 声明了 vendored 副本 / host-d 正常
PGY_SYNC_REGISTRY=/tmp/pgy-unreg/hosts.json bash sync-hosts.sh --check          # 退出码 2；host-c 判 not-a-submodule
PGY_SYNC_REGISTRY=/tmp/pgy-unreg/hosts.json bash sync-hosts.sh --apply          # a/b 补登；c/d 跳过
# 3) 新克隆对照（决定性）：修复前 clone → submodule 目录不存在（静默）；修复后 clone → sub/ 存在且 pin 正确
# 4) 边界：宿主脏 / 子模块脏 → 跳过；--allow-dirty → 处理且不卷入宿主其它改动；
#          --allow-downgrade → 未登记+ahead 也按目标补登；--no-commit → registered-staged；连跑两次幂等
# 5) 反向对照：host-c 的 vendored 目录 `git ls-files -s -- vend` 为空（未登记）
```

---

## CR-006 — 修复两处「变量后紧跟全角字符」导致的文案丢失（并订正 bash 版本归因）

- **变更时间**：2026-09-19
- **变更类型**：校准修正（**无版本变更**）
- **关联版本**：无
- **变更原因**：CR-005 引入的静态检查（变量后紧跟非 ASCII 的扫描）在既有文件中扫出两处**真实**命中。经字节级实测，根因是 **bash ≥ 5.2 的变量名解析支持多字节字符**，会把紧跟 `$VAR` 的 CJK 字符吞进变量名 → 变量判为未定义、展开为空，且被吞掉的首字节使后续字节错位。**这与本项目先前的归因相反**（此前记为「bash 3.2 吞变量名」，见 `execution-log.json` 的 run-20260919-hosts-sync-and-browser-consolidation 的 findings），故一并订正（新增 L-011）。

**变更前后差异**

| 项 | 变更前 | 变更后 |
|----|--------|--------|
| `link-skill.sh:76` | `echo "目标已存在软链（指向: $EXISTING），并非本源。"` → bash 5.x 下**路径消失**（只剩「目标已存在软链（指向: ），并非本源。」） | `…（指向: ${EXISTING}），…` |
| `pgy_upload.sh:422` | `ERROR_MSG="不支持的输入类型: $archive（仅支持 …）"` → bash 5.x 下**输入路径消失**（这是生产上传引擎的报错文案） | `…: ${archive}（仅支持 …）` |
| 归因记录 | 「bash 3.2 在多字节字符前会吞掉变量名」 | 「**bash ≥ 5.2** 会吞；3.2.57 正确」（实测：同一脚本两种解释器输出不同；显式 `LC_ALL=C` 不触发） |

**影响范围**：`link-skill.sh`（1 行）、`pgy_upload.sh`（1 行）、`STATUS.md` §9.4、`experience/LESSONS.md`（L-011）、`experience/execution-log.json`。
**兼容性说明**：**向后兼容**——仅字符串字面量的插值写法调整，参数、默认值、退出码、输出 JSON 字段、生成物路径**均未变**；`${VAR}` 与 `$VAR` 在非 CJK 场景语义完全等价。因未影响宿主调用行为，**不升版本、不打发布标签**（宿主仍 pin `v1.2.0`，本仓 HEAD 前移但标签不动，`sync-hosts.sh --check` 应仍报 3 宿主 up-to-date）。
**验证方式**：

```bash
# 1) 代码区（排除注释）不应再有「$VAR + 非 ASCII」
python3 -c "import re,pathlib;pat=re.compile(r'\\\$([A-Za-z_][A-Za-z0-9_]*)(?=[^\x00-\x7f])');[print(f'{f}:{i}',l.strip()[:60]) for f in ['sync-hosts.sh','link-skill.sh','archive_upload.sh','pgy_upload.sh'] for i,l in enumerate(pathlib.Path(f).read_text().splitlines(),1) if not l.lstrip().startswith('#') and pat.search(l)]"
# 2) 两个解释器分别语法校验（macOS 上 ./x.sh 走 shebang 3.2.57，bash x.sh 走 PATH 首位的 5.x）
for f in sync-hosts.sh link-skill.sh archive_upload.sh pgy_upload.sh; do /bin/bash -n "$f" && /opt/homebrew/bin/bash -n "$f"; done
# 3) 最小复现（对照）：V=abc; printf '[%s]\n' "$V）tail"
#    /bin/bash → [abc）tail] 正确 ; /opt/homebrew/bin/bash → 值丢失
# 4) 宿主未被惊动（本次为无版本变更，标签不动）
bash sync-hosts.sh --check    # 期望：3 宿主 up-to-date，退出码 0
```

> ⚠️ 本条同时暴露一个**验证盲区**：本项目所有脚本此前只用 `bash xxx.sh`（PATH 首位 = Homebrew bash 5.x）验证过，
> 而 shebang 声明的是 `/bin/bash`（3.2.57）。两者语言特性不同，**只测一个解释器得到的「通过」不可靠**（已写入 L-011 推广段）。

---

## CR-005 — 同步目标由「每个 HEAD」改为「发布标签驱动」（默认 `--target release`）

- **变更时间**：2026-09-19
- **变更类型**：功能变更（新增能力 + **默认值变更**）
- **关联版本**：v1.2.0
- **变更原因**：v1.1.0 的默认目标是**本机 HEAD**，等价于「引擎每提交一次，就让本机所有宿主重新 pin 一次」。实测两个**纯文档 / 记忆**提交（`6fadcb2`、`c6c32b4`）各触发一轮 3 宿主 gitlink 更新；上一轮甚至为规避该副作用而**故意不提交**记忆文件。按 §8.4 的项目约定，只有「影响宿主调用行为」的变更才值得让宿主移动，故把同步目标与发布标签绑定。使用者决策原话：「把同步目标从『每个 HEAD』改成 tag 或专用 stable 分支（只有行为变更才移动）」。

**变更前后差异**

| 项 | 变更前（v1.1.0） | 变更后（v1.2.0） |
| --- | --- | --- |
| 默认同步目标 | `local`（本机引擎仓 HEAD）——每提交即推进宿主 | `release`（**最新发布标签 `v*`**，`--sort=-v:refname`）——只有发布才推进宿主 |
| 目标选择 | 仅 `--from-origin`（布尔开关） | `--target release\|local\|origin`（显式三值）；`--from-origin` 保留为 `--target origin` 别名 |
| 无标签时的行为 | 不适用（跟 HEAD） | **显式报错并给出指引**（先 `--tag`，或临时 `--target local/origin`）——不静默退回 HEAD |
| 发布动作 | 无 | `--tag vX.Y.Z`：只对**最新发布标签**取 `^{commit}`；护栏 = 标签格式合法 + 工作区干净 + 标签不存在 + **与 STATUS.md `project_version` 一致**（不一致即拒绝） |
| 发布并同步 | 无 | `--tag vX.Y.Z --apply`：先打标签，再以该新标签为目标同步各宿主（**推荐主路径**） |
| 状态机 | 二值：`up-to-date` / `outdated` | 四值：新增 `ahead-of-target`（宿主 pin 是目标的**后代**）；`pinned == target` 单独判定为 `up-to-date` |
| `ahead-of-target` 语义 | 不存在（会被误判为 `diverged`） | 定义为**良性**：不计入「需人工处理」、`--check` 不因它返回 `2`；默认不动，回落需显式 `--allow-downgrade` |
| `--apply` 触发条件 | 仅当存在 `outdated` | 只要名单非空即进入决策循环（输出每行的 `ACTION`）；`--allow-downgrade` 时 `ahead-of-target` 也可被改动 |
| 输出 JSON | `engine{path,head,target,source}` | 增 `engine.target_short` / `engine.release_tag`（无则 `null`）与 `summary{total,outdated,ahead_of_target,attention}` |
| `post-commit` 钩子 `--auto` | 每次提交后 `--apply`（与新默认自相矛盾） | **仅当 HEAD 正好是发布标签时**才 `--apply`，定位为兜底（常规顺序是「先提交、后打标签」，`post-commit` 对 tag 不生效，钩子赶不上发布） |
| 钩子「仅提示」模式 | `--check --quiet`（`--quiet` 把报告一起吞掉，实际什么都不打印，与注释不符） | 静默跑取退出码，**仅 `rc=2`（有落后/需人工处理）时**重跑一次打印完整报告 |
| 名单重复检查 | `jq … \| grep -q`（`pipefail` 下写端收 SIGPIPE(141) → 条件判假 → 重复登记会**反向放行**） | `jq -e 'any(...)'` 内联判定，去掉管道；`--only` 匹配改为纯 bash 循环（支持多值与空格容错） |

**影响范围**：`sync-hosts.sh`（参数、默认值、状态取值、输出 JSON 字段、钩子内容）；`STATUS.md`（§1 版本号语义、§3.3、§8.4、§8.5、§9.3、`OPEN-005` 说明）；`README.md`（跟随同步章节）；`changelog/CHANGELOG.md`；新增发布标签 `v1.1.0`。
**兼容性说明**：**默认值变更（需调用方知晓）**——不带 `--target` 直接跑 `--check` / `--apply` 时，语义从「跟本机 HEAD」变为「跟最新发布标签」，且在引擎仓无 `v*` 标签时会**报错退出（code 1）**而非静默继续。参数层面**向后兼容**：`--from-origin` 仍是有效别名，v1.1.0 的其它参数与退出码语义不变。**`archive_upload.sh` / `pgy_upload.sh` / `link-skill.sh` 零改动**，宿主调用链不受影响（`sync-hosts.sh` 只在本机跑）。
**验证方式**：

```bash
bash -n sync-hosts.sh                                        # 语法（逐文件，见 L-005）
bash sync-hosts.sh --check                                   # 无标签时：报错退出 1，并给出 --tag / --target 指引
bash sync-hosts.sh --json | jq -e '.status,.error'           # JSON 模式下错误也是合法 JSON
bash sync-hosts.sh --target bogus                            # 非法目标：拒绝并打印用法（退出码 1）
bash sync-hosts.sh --check                                   # release 目标：3 宿主 ahead-of-target，退出码 0（良性）
bash sync-hosts.sh --apply --allow-downgrade --dry-run       # 回落动作可预览，不落改动
bash sync-hosts.sh --json | jq -e '.hosts|length == 3'       # 条目完整（防 L-007 静默丢记录）
bash sync-hosts.sh --tag 1.2                                 # 格式非法 → 拒绝
bash sync-hosts.sh --tag v9.9.9                              # 与 project_version 不一致 → 拒绝
bash sync-hosts.sh --tag v1.2.0 --apply                      # 主路径：打标签 + 推宿主到该发布版本
bash sync-hosts.sh --install-hook && bash .git/hooks/post-commit   # 钩子可装可跑、仅 rc=2 时打印报告
```

> ⚠️ 本轮**补打** `v1.1.0` 标签（指向 `0734932`）。这是「发布标签」约定的起点，属一次性迁移：`--tag` 只对当前 HEAD 生效且带 `project_version` 护栏（当时 frontmatter 为 1.1.0、HEAD 却已是纯文档提交 `c6c32b4`），故 v1.1.0 用原生 `git tag -a` 补打。`v1.0.0` 按 §1 语义（治理基线快照、非发布版本）**不打标签**。
> ⚠️ 发布标签与引擎 commit 一样**需要 push**（`OPEN-005`）；本机 sandbox 无 codeup 凭证，push 由使用者主导。

---

## CR-004 — 新增本机多宿主同步器 `sync-hosts.sh` 与 `.local` 名单模式

- **变更时间**：2026-09-19
- **变更类型**：功能变更（新增能力）
- **关联版本**：v1.1.0
- **变更原因**：引擎以 submodule 分发后，「引擎迭代」与「宿主更新 gitlink」是两步操作，缺少机制时会自然退化——实测三个宿主已跑出三种状态：`xiyuScoreboard` 落后引擎 HEAD 4 个 commit、`xiyu_todo_list` 的 gitlink 只存在于索引（宿主从未提交，落后 3 个）、`xiyuWebBrowser` 更退化为文件复制并漂移（见 CR-003）。需要在**不牺牲 submodule 版本锚点**的前提下，把「跟随同步」压成一条命令 / 一次提交。关联上一轮共享方式评估结论：软链共享能消除更新摩擦，但会失去版本锚点、并行版本能力与可复现性，故采用「submodule 锁定 + 本机名单批量同步」的折中。

**变更前后差异**

| 项 | 变更前 | 变更后 |
| --- | --- | --- |
| 引擎迭代后同步宿主 | 逐个手工 `git submodule update --remote` + 手工 commit gitlink；无清单、无体检手段 | `sync-hosts.sh --apply` 一条命令批量更新；`--check`（默认，只读）可随时体检 |
| 目标版本语义 | 隐式（跟 origin 还是跟本地无从区分） | 显式：默认跟**本机 HEAD**（引擎刚提交、未 push 也能跟随），`--from-origin` 跟 origin 默认分支 |
| 本机项目名单 | 无（散落在记忆与文档里） | `.local/hosts.json`（**gitignored**，本机私有：name / path / submodule） |
| 自动跟随 | 无 | 可选 `--install-hook [--auto]`：装本机 `post-commit` 钩子；默认**仅提示**，`--auto` 才自动同步；`PGY_SYNC_HOOK_DISABLE=1` 可临时禁用 |
| 依赖登记 | `jq` 是硬依赖但文档未登记（OPEN-003） | README 与 `skill/SKILL.md` 补 `jq` 前置条件（关闭 OPEN-003）；`sync-hosts.sh` 启动即校验 jq |
| README 文件树 | 与实际仓库内容不一致（OPEN-004） | 补全 `archive_upload.sh` / `link-skill.sh` / `skill/` / `sync-hosts.sh` / `.local/`（关闭 OPEN-004） |

**影响范围**：新增 `sync-hosts.sh`（引擎仓新入口，仅在本机运行）、新增 `.local/`（本机私有目录，不入库）；修改 `.gitignore`、`README.md`、`skill/SKILL.md`、`STATUS.md`。
**兼容性说明**：**向后兼容**——`archive_upload.sh` / `pgy_upload.sh` / `link-skill.sh` 的参数、默认值、输出 JSON 字段、退出码与生成物路径**零改动**；宿主项目无需更新 gitlink 即可继续工作（新能力只在引擎仓本机使用，不进入宿主调用链）。
**安全约束（新增）**：`--apply` 只处理「状态 = outdated 且工作区干净」的宿主；子模块工作区有未提交改动一律跳过；宿主工作区脏时默认拒绝，`--allow-dirty` 可显式越过（因 gitlink 更新走带 pathspec 的 `git add -- <子模块路径>` / `git commit -- <子模块路径>`，不会把宿主其它改动卷入本次提交）。
**验证方式**：

```bash
bash -n sync-hosts.sh                                     # 语法（逐文件校验，见 L-005）
bash sync-hosts.sh --list                                 # 名单可读
bash sync-hosts.sh --check                                # 3 宿主：outdated×1 / uncommitted-gitlink×1 / up-to-date×1；退出码 2
bash sync-hosts.sh --json | jq -e '.hosts | length == 3'  # 单行合法 JSON 且条目完整（防 L-007 的静默丢记录）
bash sync-hosts.sh --apply --dry-run --allow-dirty        # 干跑打印动作，不落任何改动
bash sync-hosts.sh --install-hook && bash sync-hosts.sh --uninstall-hook  # 可装可卸、重装幂等
PGY_SYNC_HOOK_DISABLE=1 bash .git/hooks/post-commit       # 钩子可一键禁用
```

> ⚠️ 本轮**未**对任何宿主执行真实 `--apply`（那会改写宿主仓的 gitlink 与提交历史），仅以 `--dry-run` 验证动作路径；真实同步由使用者决定时机。

---

## CR-003 — xiyuWebBrowser 的引擎接入由「文件复制」收敛为「git submodule」

- **变更时间**：2026-09-19
- **变更类型**：规范性变更（宿主接入方式收敛 + 本文档同步）
- **关联版本**：无版本变更（**引擎实现零改动**，改动发生在宿主项目与本文档）
- **变更原因**：多项目共享方式应统一为 submodule（有版本锚点、可复现），但 `xiyuWebBrowser` 此前是**文件复制**：宿主仓按普通 blob 跟踪 10 个引擎文件，已实测漂移——`skill/SKILL.md` 与引擎不一致、缺 `STATUS.md`/`changelog/`/`experience/`、遗留 33 KB 旧脚本 `PGYUploadScript.sh`；更关键的是**凭证与控制文件被放在引擎目录内**（`pgy-archive-uploader/pgy_config.sh`，密钥已填实），破坏了「引擎目录内不得出现密钥」的工程不变量。关联上一轮共享方式评估结论。

**变更前后差异**（宿主 `xiyuWebBrowser`，宿主侧本地 commit `c6c20b5`）

| 项 | 变更前 | 变更后 |
| --- | --- | --- |
| 接入方式 | 目录复制：宿主按普通 blob（`100644`/`100755`）跟踪；无 gitlink、无 `.gitmodules` | git submodule：`gitlink 6fadcb2` + `.gitmodules`（url = 引擎 codeup 远端） |
| 引擎目录内文件 | 引擎文件 + `pgy_config.sh`（真实密钥）+ `PGYUploadHistory.json` + 旧脚本 `PGYUploadScript.sh` + 项目包装脚本 | 仅引擎 HEAD 全量文件（含 `STATUS.md`/`changelog/`/`experience/`） |
| 凭证 / 控制文件 | 位于引擎目录内 | 移出到兄弟目录 `pgy-archive-config/`（`pgy_config.sh` 已 gitignore 且 `chmod 600`；`PGYUploadHistory.json` 入库） |
| 项目专属包装脚本 | 引擎目录内 `pgy-archive-uploader/archive_and_upload.sh`（随复制而来，非引擎文件） | 移到宿主根 `archive_and_upload.sh`，指向 `ENGINE_DIR` / `XIYU_CONFIG`，并补「子模块未初始化 / 凭证缺失」显式提示 |
| Xcode 接线 | Build Phase 调 `pgy_upload.sh --archive`，凭证靠引擎的目录探测（`<引擎目录>/pgy_config.sh`） | Build Phase 显式 `--config "$PROJECT_DIR/pgy-archive-config/pgy_config.sh"`；子模块或凭证缺失时安静跳过（不阻塞 Archive） |
| 宿主 `.gitignore` | 无该路径规则（此前靠引擎副本自带的 `.gitignore`） | 追加 `pgy-archive-config/pgy_config.sh` |
| 工程文件 | — | `project.yml` 更新 + `project.pbxproj` 中该 Build Phase 的 `shellScript` **就地替换**（**未**整体 `xcodegen generate`，原因见 L-008） |

**影响范围**：宿主仓 `xiyuWebBrowser`（`.gitmodules`、`pgy-archive-uploader`→gitlink、`pgy-archive-config/`、`archive_and_upload.sh`、`.gitignore`、`project.yml`、`project.pbxproj`）；本仓仅文档同步（`STATUS.md` §6.2）。
**兼容性说明**：宿主侧行为等价（`--dry-run` 已验证 workspace / scheme / config 解析结果与改前一致）。**但**子模块接入依赖引擎 commit 已 push origin（`OPEN-005`）：本机 pin 的是引擎 HEAD `6fadcb2`，而 `origin/master` 当前停在 `155046c`，**需人工 push 后其它机器 / 新克隆才能初始化该子模块**。
**验证方式**：

```bash
cd <xiyuWebBrowser>
git submodule status                                    # → 6fadcb2… pgy-archive-uploader (heads/master)，无前导减号
git ls-files -s pgy-archive-uploader                    # → 160000（gitlink），不再是多个 100644/100755 blob
git check-ignore -v pgy-archive-config/pgy_config.sh     # → 命中宿主 .gitignore
ls pgy-archive-uploader/ | grep pgy_config || echo "引擎目录内无密钥 ✓"
plutil -lint xiyuWebBrowser.xcodeproj/project.pbxproj    # → OK
xcodebuild -list -project xiyuWebBrowser.xcodeproj       # → 工程可解析
bash archive_and_upload.sh --target "测试版本" --dry-run  # → 正确解析 workspace/scheme/config，stdout 单行 JSON
```

**备份**：改动前把整个复制目录（含真实密钥、旧脚本）逐字节备份到 `~/xiyuyanhen/backups/2026-09-19-xiyuWebBrowser-pgy-vendored/`；原目录移入废纸篓 `~/.Trash/xiyuWebBrowser-pgy-archive-uploader-20260919`（可恢复）。

---

## CR-002 — 校准修正：修复 `skill/SKILL.md` 中的 UTF-8 替换字符乱码

- **变更时间**：2026-09-19
- **变更类型**：校准修正
- **关联版本**：无版本变更（不改变任何运行行为；仍为 v1.0.0）
- **变更原因**：建立治理基线时逐行核对 `skill/SKILL.md`，发现第 13 行含 2 个 UTF-8 替换字符（U+FFFD）。经 `git show HEAD:skill/SKILL.md` 比对确认**该乱码在 HEAD 中即存在**，属历史遗留缺陷而非本次引入，故按 §8.2 ③「先校准再变更」就地修正（关联 `STATUS.md` §9.1 第 3 项）。

**变更前后差异**

| 项 | 变更前 | 变更后 |
| --- | --- | --- |
| `skill/SKILL.md` 第 13 行 | `+ 上传蒲公英，供测试<U+FFFD><U+FFFD>员扫码下载。`（字节 `ef bf bd ef bf bd`） | `+ 上传蒲公英，供测试人员扫码下载。` |
| `skill/SKILL.md` 末尾 | HEAD 中无「可选：Xcode GUI `Archive` 后自动上传（Post-actions）」章节（该章节系上一会话产出、当时未提交） | 保留该章节，并随本条目一并入库（未做内容改写） |
| 其余文件 | — | 无改动 |

**影响范围**：`skill/SKILL.md`（经 `link-skill.sh` 软链分发给宿主项目的 AI 技能文档）。
不涉及 `archive_upload.sh` / `pgy_upload.sh` / `link-skill.sh` 的任何行为。
**兼容性说明**：向后兼容——纯文本修正，无参数、契约、输出或退出码变化。
**验证方式**：
1. `grep -c $'\xef\xbf\xbd' skill/SKILL.md` → 输出 `0`（无替换字符残留）；
2. `grep -n "供测试人员扫码下载" skill/SKILL.md` → 命中第 13 行；
3. `git show HEAD:skill/SKILL.md | grep -c $'\xef\xbf\xbd'` → 输出 `1`（命中 1 行），佐证为历史遗留；
4. `for f in pgy_upload.sh archive_upload.sh link-skill.sh; do bash -n "$f" || exit 1; done` → 无输出、退出码 0（确认未误伤脚本）。
   ⚠️ **勿写成 `bash -n a.sh b.sh c.sh`**：bash 只把首个参数当脚本、其余当位置参数，**后两个文件不会被检查**且仍返回 0（假通过）。详见 `experience/LESSONS.md` L-005。

---

## CR-001 — 建立项目治理基线（变更记录 + 交接机制）

- **变更时间**：2026-09-19
- **变更类型**：规范性变更（治理机制建设）
- **关联版本**：v1.0.0
- **变更原因**：项目需要由多个 Agent 在多个会话、多个客户端中接力开发。缺乏单一事实来源会导致跨工具上下文不一致、变更无痕、交接困难。故建立「变更记录 + 交接」治理基线。

**变更前后差异**

| 项 | 变更前 | 变更后 |
| --- | --- | --- |
| 状态/交接文档 | 无 | 新增 `STATUS.md`：机器可读 YAML frontmatter + 9 个结构化章节 |
| 变更流水 | 无 | 新增 `changelog/CHANGES.md`：`CR-NNN` 追加式条目 |
| 版本档案 | 无 | 新增 `changelog/CHANGELOG.md` + `changelog/v1.0.0.md` |
| 经验沉淀 | 无 | 新增 `experience/{INDEX.md,LESSONS.md,execution-log.json}` |
| 跨工具入口 | 无 | 新增 `AGENTS.md` |
| 变更流程 | 无强制流程 | `STATUS.md` §8 定义 READ → ASSESS → CALIBRATE → IMPLEMENT → UPDATE → VERSION |

**影响范围**：新增 `STATUS.md`、`AGENTS.md`、`changelog/*`、`experience/*`；
并**补强既有 `.gitignore`**（保留原有 `pgy_config.sh` / `*.log` / `.DS_Store` 规则，追加 `.env*` 凭证规则（保留 `!.env.example`）与编辑器目录）——
脚手架默认跳过已存在的 `.gitignore`，故该补强为人工追加，**未删除任何原有规则**。
**兼容性说明**：向后兼容——纯新增文档与流程约束，不影响既有内容的运行行为。
**验证方式**：
1. `STATUS.md` 顶部 YAML frontmatter 可被 YAML 解析器加载，含 `project_version: "1.0.0"`；
2. `grep -n "CR-001" changelog/CHANGES.md` 有结果；
3. `experience/execution-log.json` 为合法 JSON（`python3 -m json.tool` 无报错）；
4. `git check-ignore -v pgy_config.sh examples/.env` 命中忽略规则（凭证与 `.env*` 不入库）。
