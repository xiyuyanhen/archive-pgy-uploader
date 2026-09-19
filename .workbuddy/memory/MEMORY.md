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
- **只有影响宿主调用行为**（参数/默认值/输出 JSON 字段/退出码/生成物路径）才升版本 + 建 `changelog/vX.Y.Z.md`；纯文档/错别字记 CR 标「无版本变更」。
- 新问题在 `STATUS.md` §7 分配 `OPEN-NNN`（frontmatter `known_issues` 须同步）；经验追加 `experience/LESSONS.md`（`L-NNN`，只追加）+ `execution-log.json`。
- 追加式文档插入新条目时，锚点取**新条目自身正文**并在其前插入（等价「A→A+B」），**绝不用下一条目标题当锚点**，否则会静默吞掉该标题。
- `STATUS.md` 关键约束：`jq` 是硬依赖（缺失 exit 1）；Post-actions 入口只收 `--config/--archive`，更新说明恒取 JSON `updateDes`；`--notes` 只在 CLI 入口生效。
- 尚未补的文档债：`OPEN-003`（jq 未登记进 README/SKILL.md 前置条件）、`OPEN-004`（README 文件树缺 `archive_upload.sh`/`link-skill.sh`/`skill/`）。
