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
