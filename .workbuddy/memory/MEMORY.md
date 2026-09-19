# archive-pgy-uploader 长期记忆（项目级）

## Xcode 共享 scheme 外部改动的坑（重要）
- 用文本/脚本在 `ios/Runner.xcodeproj/xcshareddata/xcschemes/*.xcscheme` 外部注入 ArchiveAction PostActions，Xcode **不会热加载**，必须完全退出 Xcode 重开项目才生效。用户测试时仍用旧内存方案 → Post-actions 不跑、无日志、不上传。
- **规避（推荐）**：日常/自动化/AI 触发一律走 CLI 入口 `ios/Scripts/archive_upload.sh --target "测试版本"`（自己 xcodebuild archive + 上传，零 GUI 依赖，不踩 scheme 缓存坑）。
- **若坚持 Xcode GUI Archive 自动上传**：接入后必须提示用户**完全退出 Xcode 重开**，或直接在 Xcode `Edit Scheme → Archive → + → New Run Script Phase` 手动添加 Post-actions（手动加的一定生效）。

## 诊断 SOP
- 引擎/Post-actions 是否通，看 `$TMPDIR/pgy_upload_*.log`。脚本一旦启动必写日志；无日志=脚本没启动（多半是 scheme 未加载/未重开 Xcode）。
- 日志归属靠 **IPA 名 / Bundle ID** 区分：导出 `xiyu_scoreboard.ipa` 是 Scoreboard，导出 `xiyu_todolist.ipa` 是 todo_list。**勿混淆**（曾因混淆浪费一轮排查）。

## 蒲公英上传约定（用户 2026-08-08 确认）
- 同一蒲公英用户共用一对 `PGY_USER_KEY`/`PGY_API_KEY`，不同 App 靠 Bundle ID 区分。多项目（xiyuScoreboard、xiyu_todo_list）key 一致是正常的，不是配置串味。
- 真正区分 App 的是 config 里的 `TARGET_BUNDLE_ID`（须与 pbxproj `PRODUCT_BUNDLE_IDENTIFIER` 一致）。

## 接入核对清单（避免"半套接入"）
1. 子模块 gitlink 对齐到最新引擎 commit，且含 archive_upload.sh/link-skill.sh/skill/。
2. 接入 Post-actions 时同步在 SKILL.md/文档标注"需重开 Xcode"。
3. `pgy_config.sh` 密钥就位、gitignored；`TARGET_BUNDLE_ID` 与 pbxproj 一致。
4. 接入后用 CLI 入口实跑一次验证整条链路（不依赖 Xcode GUI）。
5. 引擎仓 commit 必须先 push origin，否则他人/新克隆解析不到子模块 commit（sandbox 无 codeup 凭证，需用户本地 push）。
6. **原生 XcodeGen 工程（无 Runner scheme / 无共享 scheme，如 xiyuWebBrowser）接入范式**：
   - Xcode 接线优先用 **Build Phase `runOnlyWhenInstalling: true`** 调 `pgy_upload.sh`（比 Post-actions 稳，不依赖选哪个 scheme；`$ARCHIVE_PATH` 为空时引擎多策略查找兜底）。改 `project.yml` 后需 `xcodegen generate`。
   - 因引擎默认 `--scheme Runner`/`Runner.xcworkspace`，须加**项目专属包装脚本**（如 `archive_and_upload.sh`）预置 `--workspace *.xcodeproj --scheme <本scheme> --config pgy_config.sh`，让 AI/CLI 一条命令跑通。
   - sandbox 无法推 codeup 远程时，用**复制引擎文件**代替 submodule（README 注明后续需手动重同步）。

## 治理约定（2026-09-19 起，v1.0.0）
**动手前必读顺序**：`AGENTS.md` → `STATUS.md`（唯一事实来源）→ `experience/LESSONS.md` → `changelog/CHANGELOG.md`。
冲突时以 `STATUS.md` 为准（README 不是事实来源）。

- 任何修改走 `STATUS.md` §8：READ → ASSESS → CALIBRATE → IMPLEMENT → UPDATE → VERSION。
- 改行为 → 同步 `STATUS.md` + 在 `changelog/CHANGES.md` **顶部**追加 `CR-NNN`（含前后差异/影响范围/兼容性/验证方式）。
- **只有影响宿主调用行为**（参数/默认值/输出 JSON 字段/退出码/生成物路径）才升版本 + 建 `changelog/vX.Y.Z.md`
  **+ 打发布标签**（`sync-hosts.sh --tag vX.Y.Z`，v1.2.0 起版本号与标签绑定）；纯文档/错别字记 CR 标「无版本变更」、**不打标签**。
- 新问题在 `STATUS.md` §7 分配 `OPEN-NNN`（frontmatter `known_issues` 须同步）；经验追加 `experience/LESSONS.md`（`L-NNN`，只追加）+ `execution-log.json`。
- 追加式文档插入新条目时，锚点取**新条目自身正文**并在其前插入（等价「A→A+B」），**绝不用下一条目标题当锚点**，否则会静默吞掉该标题。
- `STATUS.md` 关键约束：`jq` 是硬依赖（缺失 exit 1）；Post-actions 入口只收 `--config/--archive`，更新说明恒取 JSON `updateDes`；`--notes` 只在 CLI 入口生效。
- 尚未补的文档债：`OPEN-003`（jq 未登记进 README/SKILL.md 前置条件）、`OPEN-004`（README 文件树缺 `archive_upload.sh`/`link-skill.sh`/`skill/`）。
  → **已在 v1.1.0 关闭**（README / SKILL.md 补 jq；README 文件树补全）。

## 多项目共享方式与同步机制（2026-09-19 起，v1.1.0 / v1.2.0）

- **共享机制统一为 submodule**（不再有文件复制）。三个宿主：`xiyuScoreboard` / `xiyu_todo_list`（路径 `ios/Scripts/archive-pgy-uploader`）、`xiyuWebBrowser`（路径 `pgy-archive-uploader`，宿主根）。
- **工程不变量：引擎目录内不得出现密钥**。凭证与控制文件必须放**引擎目录之外**的兄弟目录（命名约定 `*-archive-pgy-config/`）。通用入口默认按 `<宿主>/ios/Scripts/archive-pgy-config/pgy_config.sh` 探测；非此结构（如 XcodeGen 工程）必须显式传 `--config`。
- **项目专属包装脚本不得放在引擎目录内**（会被 submodule 覆盖）：放宿主根，内部用 `ENGINE_DIR` / `<PROJ>_CONFIG` 变量转发。
- **本机多宿主跟随同步**：`bash sync-hosts.sh`（默认 `--check` 只读体检，退出码 0=一致 / 2=有落后或需人工介入 / 1=出错）→ `--apply` 更新各宿主 gitlink 并**只在宿主侧本地 commit**（不 push）；名单 `.local/hosts.json`（gitignored，本机私有）。
- **同步目标 = 发布标签（v1.2.0 起，默认 `--target release`）**：跟**最新 `v*` 标签**，不是每个 HEAD。
  - **发布主路径**：`bash sync-hosts.sh --tag vX.Y.Z --apply`（打标签 + 推宿主，一条命令）。
  - `--tag` 护栏：格式 `vX.Y.Z`、工作区干净、标签不存在、**与 `STATUS.md` `project_version` 一致**（不一致即拒绝）。
    补打历史标签必须用原生 `git tag -a <tag> <commit>`（`--tag` 只认 HEAD 且过不了版本护栏）。
  - 逃生口：`--target local`（本机 HEAD，开发期）/ `--target origin`（远端分支，交接期）；`--from-origin` 是 origin 的别名。
  - **无标签时直接报错**，不静默退回 HEAD（这是刻意的）。
  - `ahead-of-target`（宿主 pin 是标签的后代）= **良性**：不计入 attention、`--check` 不返回 2、默认不动，回落需 `--allow-downgrade`。
  - 意图：**纯文档 / 记忆提交不再让三个宿主重新 pin**（v1.1.0 时代每个提交都会，甚至为规避而不敢提交记忆）。判据见 `STATUS.md` §8.4。
  - `v1.0.0` **无标签**（按 §1 是治理基线快照、非发布版本）；`v1.1.0` 是事后补打的第一个发布标签。
- **钩子只能当兜底**：git 无 `post-tag`，常规顺序「先 commit 后 tag」下 `post-commit` 永不触发 → `--auto` 改为「仅 HEAD 正好是发布标签时才 apply」。别指望钩子完成发布同步。
- **push 一律由用户主导**（本机沙箱无 codeup 凭证，见 `OPEN-005`）。**标签也必须 push**，否则他人 / 新克隆看不到 release 目标。
- 评估结论（勿反复推翻）：**软链共享只适合「暴露层」**（如 `link-skill.sh` 注册技能），不适合承载引擎共享——会让所有宿主共享同一工作区，失去版本锚点与并行版本能力，且 `rm -rf <link>/` 会穿透删中央实体。

## shell 脚本约定（本仓所有 `*.sh` 必须遵守）

- **变量后紧跟全角/CJK 字符一律写 `${VAR}`**：根因是 **bash ≥ 5.2 的变量名解析支持多字节字符**（`"$V）"` 会被当成一个变量名 → 值展开为空 + 字节错位）。**bash 3.2.57 反而正常**（曾误记为「3.2 吞变量名」，已订正为 L-011）。
- **双解释器验证**：macOS 上 `./x.sh` 走 shebang `/bin/bash`（3.2.57），`bash x.sh` 走 PATH 首位（本机 `/opt/homebrew/bin/bash` 5.3.15）。语法与关键行为**两个都要跑**，只测一个不算通过。
- 静态检查（排除注释）：
  `python3 -c "import re,pathlib;pat=re.compile(r'\\\$([A-Za-z_][A-Za-z0-9_]*)(?=[^\x00-\x7f])');[print(f'{f}:{i}') for f in ['sync-hosts.sh','link-skill.sh','archive_upload.sh','pgy_upload.sh'] for i,l in enumerate(pathlib.Path(f).read_text().splitlines(),1) if not l.lstrip().startswith('#') and pat.search(l)]"`
- `set -euo pipefail` 下慎用 `工具 | grep -q` / `| head -1`（读端提前退出 → 写端 SIGPIPE 141 → 条件反向判假），见 L-009。
