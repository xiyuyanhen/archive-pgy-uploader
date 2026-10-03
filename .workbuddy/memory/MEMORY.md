# archive-pgy-uploader 长期记忆（项目级）

## 核心定位
Xcode Archive → 蒲公英(Pgyer) 自动上传**引擎**；多宿主以 submodule 共享，凭证/配置按宿主分离（引擎目录内**禁止**出现密钥/绝对路径/真实 Bundle ID）。事实来源 = `STATUS.md`（冲突以它为准，README 非事实来源）。

## Xcode 接线坑（宿主侧，高频踩坑）
- 外部脚本改 `*.xcscheme` 注入 Archive PostActions，Xcode **不热加载**，须完全退出重开才生效 → 用户常因"没重开"误以为脚本不跑（实则 scheme 未加载、无日志）。
- **推荐 AI/CI 走 CLI 入口** `archive_upload.sh --target "测试版本"`（自 xcodebuild archive + 上传，零 GUI 依赖）。
- XcodeGen 工程（如 xiyuWebBrowser）优先用 **Build Phase `runOnlyWhenInstalling: true`** 调 `pgy_upload.sh`；须项目专属包装脚本预置 `--workspace/--scheme/--config`（引擎默认 `--scheme Runner`）。**勿盲目 `xcodegen generate`**：会清空 `DEVELOPMENT_TEAM`、改写 `LD_RUNPATH_SEARCH_PATHS` → 改 pbxproj 中那段 `shellScript` 即可。

## 诊断 SOP
- 脚本一旦启动必写 `$TMPDIR/pgy_upload_*.log`；**无日志=脚本没启动**（多半 scheme 未加载/未重开 Xcode）。
- 日志按 **IPA 名/Bundle ID** 区分 App（`xiyu_scoreboard.ipa`=Scoreboard，`xiyu_todolist.ipa`=todo_list），勿混淆。

## 蒲公英约定（2026-08-08 确认）
- 同蒲公英用户共用一对 `PGY_USER_KEY`/`PGY_API_KEY`，靠 Bundle ID 区分 App；多项目 key 一致正常。
- 区分靠 config 的 `TARGET_BUNDLE_ID`（须与 pbxproj `PRODUCT_BUNDLE_IDENTIFIER` 一致）。

## 接入核对清单（防"半套接入"）
1. 子模块 gitlink 对齐最新引擎 commit，且含 `archive_upload.sh/link-skill.sh/skill/`。**验证完整性看索引模式** `git ls-files -s -- <path>` = `160000`，勿看磁盘目录（见下"unregistered-gitlink"）。
2. 接 Post-actions 时同步在 SKILL.md 标注"需重开 Xcode"。
3. `pgy_config.sh` 密钥就位、gitignored；`TARGET_BUNDLE_ID` 与 pbxproj 一致。
4. 接后用 CLI 入口实跑验证整条链路。
5. **子模块登记须「.gitmodules + gitlink(160000)」两件齐全**；只交 `.gitmodules` 得 `unregistered-gitlink`——本地正常、新克隆**静默**缺子模块（`git submodule update --init` 退出码 0 不报错也不检出）。用 `sync-hosts.sh --check` 体检、`--apply` 可补登（v1.3.0 起，仅真 submodule checkout 生效）。

## 共享与同步机制（v1.1.0/v1.2.0/v1.3.0）
- 共享机制统一 **submodule**（弃用文件复制——复制会失版本锚点并漂移）。三宿主：xiyuScoreboard / xiyu_todo_list（路径 `ios/Scripts/archive-pgy-uploader`）、xiyuWebBrowser（路径 `pgy-archive-uploader`，宿主根）。
- 工程不变量：引擎目录禁密钥；凭证/控制文件放引擎外兄弟目录（`*-archive-pgy-config/`）。项目专属包装脚本放宿主根（勿放引擎内，会被 submodule 覆盖）。
- **本机多宿主同步**：`bash sync-hosts.sh`（默认 `--check`；`--apply` 更新各宿主 gitlink 并**仅本机 commit、不 push**）。名单 `.local/hosts.json`（gitignored）。
- **同步目标 = 发布标签**（v1.2.0 起，默认 `--target release`）：跟最新 `v*` 标签，非每个 HEAD。**纯文档/记忆提交不再惊动宿主 pin**（v1.1.0 痛点已解）。
  - 发布主路径：`bash sync-hosts.sh --tag vX.Y.Z --apply`（打标签+推宿主一条命令）；`--tag` 护栏：格式/工作区干净/标签不存在/与 `STATUS.md project_version` 一致。
  - `ahead-of-target`（宿主 pin 是标签后代）= 良性，默认不动，回落需 `--allow-downgrade`。
  - 钩子只能兜底（git 无 post-tag，`post-commit` 常规不触发）→ 别指望钩子完成发布同步。
- 远端 URL 已于 2026-09-20 整体迁 **HTTPS** `https://github.com/xiyuyanhen/archive-pgy-uploader.git`（公开仓克隆免凭证），gitlink 未变、宿主仅 `.gitmodules` 改动。

## 治理约定（v1.0.0 起）
- 动手顺序：`AGENTS.md` → `STATUS.md` → `experience/LESSONS.md` → `changelog/CHANGELOG.md`。
- 变更走 `STATUS.md` §8：READ→ASSESS→CALIBRATE→IMPLEMENT→UPDATE→VERSION。改行为 → 同步 `STATUS.md` + 顶部追加 `CR-NNN`（`changelog/CHANGES.md`）。
- **仅影响宿主调用行为**（参数/默认值/JSON 字段/退出码/产物路径）才升版本 + 建 `changelog/vX.Y.Z.md` + 打标签（`sync-hosts.sh --tag`）；纯文档/错别字记 CR 标「无版本变更」、**不打标签**。
- 新问题分配 `OPEN-NNN`；经验追加 `L-NNN`（只追加）+ `execution-log.json`。
- 文档插入新条目锚点取**自身正文**（A→A+B），勿用下一目标题当锚点（会静默吞标题）。
- `STATUS.md` 关键约束：`jq` 硬依赖（缺失 exit 1）；Post-actions 入口只收 `--config/--archive`、更新说明恒取 JSON `updateDes`；`--notes` 仅 CLI 入口生效。

## shell 脚本约定（本仓 `*.sh`）
- 变量后紧跟全角/CJK 字符写 `${VAR}`：bash ≥5.2 变量名支持多字节 → `"$V）"` 被当变量名（值空+字节错位）；bash 3.2.57 反正常（L-011）。
- 双解释器验证：`./x.sh` 走 `/bin/bash` 3.2.57，`bash x.sh` 走 PATH 首位（本机 5.3.15），语法行为都跑。
- `set -euo pipefail` 下慎用 `工具 | grep -q`/`| head -1`（读端早退→写端 SIGPIPE 141→条件反向判假，L-009）。
- **TSV 进程内通道所有列必须非空**（空写 `-`）：tab 是 IFS 空白，`read` 折叠连续分隔符，而 `jq split("\t")`/`awk -F'\t'` 保留空字段 → 两套解析器结果不同（L-012）。
- `read` 单独测：遇 EOF 清空目标变量（L-006）、IFS 空白折叠（L-012）。
- **判定性命令禁止 `2>/dev/null`**（L-014）：会把"命令失败"伪装成"空结果"。`rc=0 且空`=确实没有；`rc≠0`=无法判定。仅"失败有明确无害默认值"处可用（如 `rev-parse --quiet x 2>/dev/null || true`）。

## 远端状态可核实性（CR-008/009 校准）
- **公开远端可匿名核实**：`git ls-remote https://github.com/xiyuyanhen/archive-pgy-uploader` → `rc=0` + 真实 SHA（无需凭证）。**私有远端不能**（需凭证，沙箱无通道，HTTP 401 非网络问题）。
- **push 能否直推取决于 `ssh-agent` 身份**（非固定）：2026-09-20 前无身份须用户本地 push；**2026-09-20 起实测 `id_ed25519` 已加载**，`git push origin master` 成功。**标签也必须 push**。
- 本机全局 `url.*.insteadOf` 同时改写 fetch/push（`https://github.com/`→镜像）；判远端实际地址用 `git remote get-url --push <remote>`，勿只看 `git remote -v` 字面值。
- 分支状态可本地反推（`git push` 更新远程跟踪引用）；**标签状态不可**（push 标签不产生本地引用）→ 只能查远端。
- 会随时间变化的事实（推送状态/远端引用）写入记忆**必须带核实方式与时间点**。

## 公开仓内容约定（2026-09-20 确认）
- 本仓公开 GitHub。`.workbuddy/memory/` 与 `execution-log.json` 内**内部项目名属测试项目**，用户确认可继续公开。
- 后续约定：**不再提交**其他隐私（真实客户名/未公开业务、凭证、个人身份信息、内网地址）。新增内容前自检：愿被任何人永久读到吗？
