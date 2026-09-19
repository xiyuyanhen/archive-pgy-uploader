---
document_type: "project-status"
schema_version: "1.0"
status_version: "1.0"
project_name: "archive-pgy-uploader"
project_version: "1.0.0"
last_calibrated: "2026-09-19"
calibration_state: "baseline"
authority: "本文件是本项目现状的唯一事实来源；与 README / AGENTS.md 冲突时以本文件为准"
repository: "https://codeup.aliyun.com/61c852431ccc3a1faae0a9fa/scripts/archive-pgy-uploader.git"
project_type: "code"
positioning: "通用 Xcode Archive → 蒲公英(Pgyer) 自动上传引擎（多项目以 submodule 共享，配置与密钥按项目分离）"
maturity: "已在 3 个 iOS 项目实际使用（xiyuScoreboard / xiyu_todo_list / xiyuWebBrowser）；治理基线自 v1.0.0 起"
entrypoints:
  - id: "cli-full"
    name: "archive_upload.sh — 全自动 Archive + 上传（AI / CI 主入口）"
    path: "archive_upload.sh"
    args: "--target \"测试版本\" [--archive <path>] [--version] [--notes] [--method] [--bundle-id] [--config] [--workspace] [--scheme] [--configuration] [--dry-run]"
  - id: "upload-only"
    name: "pgy_upload.sh — 对已有 .xcarchive/.ipa 上传；亦为 Xcode Post-actions 被调方"
    path: "pgy_upload.sh"
    args: "--archive <path> [--config <pgy_config.sh>] [--target] [--version] [--notes] [--method] [--bundle-id] [--json] [--history]"
  - id: "skill-register"
    name: "link-skill.sh — 把 skill/SKILL.md 注册到 WorkBuddy 技能扫描目录"
    path: "link-skill.sh"
    args: "[-g] [-f] [--project-root <path>]"
change_control:
  entry_doc: "AGENTS.md"
  status_doc: "STATUS.md"
  change_log: "changelog/CHANGES.md"
  version_notes_dir: "changelog/"
  experience_dir: "experience/"
  rules:
    - "变更前必读 STATUS.md + experience/LESSONS.md，确认现有实现与已知问题"
    - "变更后同步更新 STATUS.md（frontmatter 与正文）并追加 changelog/CHANGES.md 条目（CR-NNN）"
    - "影响运行行为的变更须升版本并新建 changelog/vX.Y.Z.md + 更新 changelog/CHANGELOG.md 索引"
    - "发现 STATUS.md 与实现不一致时，先校准再变更，并在 §9 校准记录中留痕"
known_issues:
  - {id: "OPEN-001", severity: "medium", status: "by-design", summary: "Xcode 不热加载外部手改的共享 .xcscheme：注入 Post-actions 后未完全重开 Xcode 则不生效，表现为「不上传、无日志」"}
  - {id: "OPEN-002", severity: "low", status: "by-design", summary: "--notes 仅在 CLI/手动入口生效；Xcode Post-actions 入口根本不接收该参数，更新说明恒取自 PGYUploadHistory.json [0].updateDes"}
  - {id: "OPEN-003", severity: "low", status: "open", summary: "jq 是引擎硬依赖（缺失即 exit 1），但 README 与 skill/SKILL.md 的前置条件均未登记"}
  - {id: "OPEN-004", severity: "low", status: "open", summary: "README「架构」文件树未列出 archive_upload.sh / link-skill.sh / skill/，与仓库实际内容不一致"}
  - {id: "OPEN-005", severity: "medium", status: "by-design", summary: "子模块接入要求引擎 commit 已 push origin；仅本地 commit 会导致他人/新克隆解析不到 gitlink"}
---

# STATUS.md — 项目状态与交接基线

> 本文件是 `archive-pgy-uploader` 的**实现真相索引与交接主文档**。任何 Agent 在修改本项目之前，
> **必须先读取本文件**；任何功能或规范性变更之后，**必须同步更新本文件**。
> 机器可读摘要见文件顶部 YAML frontmatter，正文为等价的人类可读展开。

## 1. 状态概览

| 项 | 值 |
| --- | --- |
| 项目名称 | `archive-pgy-uploader` |
| 项目版本 | 1.0.0 |
| 状态文档版本 | 1.0 |
| 最近校准 | 2026-09-19（`baseline`，建立本文件时的首次基线） |
| 一句话定位 | 通用 Xcode Archive → 蒲公英(Pgyer) 自动上传引擎（多项目以 submodule 共享，配置与密钥按项目分离） |
| 成熟度 | 已在 3 个 iOS 项目实际使用（xiyuScoreboard / xiyu_todo_list / xiyuWebBrowser）；治理基线自 v1.0.0 起 |
| 远端仓库 | https://codeup.aliyun.com/61c852431ccc3a1faae0a9fa/scripts/archive-pgy-uploader.git |

> **版本号语义**：本项目在此基线前**没有版本号体系**（无 git tag、脚本内无版本常量）。
> `v1.0.0` 不表示"发布版本"，而是**建立治理基线时的现状快照**——即当时 HEAD 的可用能力集合。
> 后续按 §8.4 规则递增；`v1.0.0.md` 是首份版本档案。

## 2. 目标与范围

### 2.1 具备的能力

| # | 能力 | 实现方 | 成熟度 | 备注 |
| -- | --- | --- | --- | --- |
| C1 | Archive → 导出 IPA → 上传蒲公英主链路（等待/直接两种模式） | `pgy_upload.sh` | 稳定 | 已在 3 个项目实跑成功 |
| C2 | 一条命令全自动 `xcodebuild archive` + 上传，零 GUI 依赖 | `archive_upload.sh` | 稳定 | AI / CI 主入口 |
| C3 | 归档身份校验：比对归档 Bundle ID 与 `TARGET_BUNDLE_ID`，不匹配即拦截 | `pgy_upload.sh` | 稳定 | 防止误传其他项目安装包 |
| C4 | 项目级控制文件开关：`PGYUploadHistory.json [0].versionTarget` 为空则跳过上传 | `pgy_upload.sh` | 稳定 | `--target` 可覆盖以强制上传 |
| C5 | 多策略 `.xcarchive` 发现（`$ARCHIVE_PATH` 为空时轮询，上限 `PGY_MAX_WAIT`） | `pgy_upload.sh` | 稳定 | 等待模式 |
| C6 | 本地 HTML 实时监控页（`<meta refresh>` 自刷新，成功/失败转静态结果页） | `pgy_upload.sh` / `archive_upload.sh` | 稳定 | 无需 HTTP 服务、无 CORS |
| C7 | 结构化 JSON 输出（stdout 单行），供 AI / CI 解析 | `pgy_upload.sh --json` | 稳定 | 中间日志走 stderr |
| C8 | 双触发防护：回溯祖先进程判定 `xcodebuild` 驱动，避免 CLI 与 Post-actions 重复上传 | `pgy_upload.sh` | 稳定 | 进程树硬判定，不依赖环境变量继承 |
| C9 | 技能注册器：把 `skill/SKILL.md` 以相对软链注册到 WorkBuddy 扫描目录 | `link-skill.sh` | 稳定 | 支持项目级 / 用户级 |
| C10 | 项目配置与控制文件模板 | `examples/` | 稳定 | `pgy_config.example.sh` / `PGYUploadHistory.example.json` |

### 2.2 明确不做（范围外）

- **不携带任何项目密钥或路径**：本仓库是共享引擎，禁止出现真实 `PGY_USER_KEY` / `PGY_API_KEY`、项目绝对路径、Bundle ID 真值。
- **不管理签名与证书**：不做证书申请、profile 生成、team 配置；依赖项目自身签名能力（`xcodebuild -exportArchive` 的 `ExportOptions.plist` 由引擎生成）。
- **不做 Git 操作**：不 commit / 不 push。子模块 gitlink 的 push（见 `OPEN-005`）由使用者本地完成（本机 sandbox 无 codeup 凭证）。
- **不扩展到其他分发平台**：仅蒲公英（`apiv2/app/upload`）；不做 TestFlight / Firebase / 自建分发。
- **不覆盖非 iOS 平台**：假定产物是 `.xcarchive` / `.ipa`。
- **不修改宿主 Xcode 工程**：不写 `project.pbxproj` / `.xcscheme`（Post-actions 由使用者在 Xcode 内手动添加或按文档注入）。
- **不在仓库内提供 GUI 提示**：Xcode 内"scheme 未重载"的告警无法由本引擎呈现（见 `OPEN-001`），只能靠文档与 CLI 入口规避。

## 3. 入口与调用方式

### 3.1 调用序列

```bash
# 0) 前置：读取状态与经验（必做）
#    读 STATUS.md、experience/LESSONS.md

# 1) 安装依赖（一次性）
brew install jq              # 硬依赖：缺失时 pgy_upload.sh 直接 exit 1（见 OPEN-003）
xcode-select --install       # 提供 xcodebuild

# 2) 宿主项目侧一次性接入（在宿主项目根目录执行，下方 <IOS> = 宿主 ios/ 目录）
git submodule add <本仓库 remote> ios/Scripts/archive-pgy-uploader
mkdir -p "$IOS/Scripts/archive-pgy-config"
cp ios/Scripts/archive-pgy-uploader/examples/pgy_config.example.sh \
   "$IOS/Scripts/archive-pgy-config/pgy_config.sh"     # 填入密钥，gitignore 该文件
# 放置 PGYUploadHistory.json（控制"是否上传"+ 版本目标 + 更新说明）
bash ios/Scripts/archive-pgy-uploader/link-skill.sh   # 可选：注册 WorkBuddy 技能

# 3) 日常上传（AI / CI 主入口，推荐）
bash ios/Scripts/archive-pgy-uploader/archive_upload.sh --target "测试版本"

# 4) 仅上传已有包（复用归档，跳过 xcodebuild）
bash <引擎目录>/pgy_upload.sh --archive /path/to/Runner.xcarchive \
  --config <项目配置目录>/pgy_config.sh --json
```

> **默认工程假设**：`archive_upload.sh` 以自身位置反推 `<宿主>/ios/`（即假定子模块位于 `<宿主>/ios/Scripts/<repo>/`），
> 并默认 `Runner.xcworkspace` + `--scheme Runner` + `--configuration Release`；
> `Runner.xcworkspace` 不存在时自动回退 `Runner.xcodeproj`。
> 不满足该假设的工程必须显式传 `--workspace` / `--scheme` / `--config`（见 §6.2）。

### 3.2 入口参数

**A. `archive_upload.sh`（全自动主入口）**

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `--target` | 无 | 版本目标标签（如「测试版本」）。**非空才会实际上传** |
| `--archive` | 无 | 传入已有 `.xcarchive` 则跳过 `xcodebuild archive` |
| `--version` | 自动探测 | 显式版本号 |
| `--notes` | 无 | 更新说明（**仅本入口生效**，见 `OPEN-002`） |
| `--method` | `development` | `development` / `ad-hoc` / `app-store` |
| `--bundle-id` | config 的 `TARGET_BUNDLE_ID` | 目标 Bundle ID（身份校验） |
| `--config` | `<宿主>/ios/Scripts/archive-pgy-config/pgy_config.sh` | 凭证配置路径 |
| `--workspace` / `--scheme` / `--configuration` | `Runner.xcworkspace` / `Runner` / `Release` | 工程结构覆盖 |
| `--dry-run` | 关 | 只打印将执行的 `xcodebuild` 命令 |
| `-h` / `--help` | — | 打印脚本头部用法 |

**B. `pgy_upload.sh`（底层引擎 / Post-actions 被调方）**

| 参数 | 说明 |
| --- | --- |
| `--archive <path>` | `.xcarchive` 或 `.ipa`；省略则进入 `PGY_MAX_WAIT` 秒等待模式自动发现 |
| `--config <path>` | 凭证配置；省略时按 `$PGY_CONFIG` → `<引擎目录>/pgy_config.sh` → `$HOME/.pgy_config.sh` → `./pgy_config.sh` 顺序探测 |
| `--history <path>` | 控制文件路径（通常由 `pgy_config.sh` 的 `PGY_HISTORY_FILE` 提供） |
| `--_upload` | **内部 worker 模式**：跳过等待/自触发逻辑，直接执行导出+上传 |
| `--monitor-path` / `--log-path` | 主进程下传给 worker 复用同一监控页 / 日志文件 |
| `--json` | stdout 输出结构化 JSON |
| `-h` / `--help` | 打印头部注释 |

## 4. 输入输出契约

### 4.1 输入契约

| 形态 | 示例 | 解析结果 |
| --- | --- | --- |
| CLI 参数 | `--target "测试版本"` | 版本目标标签；决定是否上传 |
| 项目配置 `pgy_config.sh`（shell，`source` 执行） | `PGY_USER_KEY=... ; TARGET_BUNDLE_ID=com.xiyu.browser` | 凭证 + 身份 + 控制文件路径（**该文件必须 gitignored**） |
| 环境变量 | `PGY_METHOD` / `PGY_MAX_WAIT` / `PGY_DEBUG_CHECK` / `PGY_VERSION_TARGET` / `PGY_UPDATE_DESCRIPTION` / `PGY_TEAM_ID` | 同配置项，可被 config / CLI 覆盖 |
| 控制文件 `PGYUploadHistory.json` | `[{"version":"1.0.3.0","versionTarget":"测试版本","updateDes":"..."}]` | 取 `.[0]`；`versionTarget` 空 → 跳过上传；`updateDes` → 更新说明默认值 |
| 归档 / 安装包 | `Runner.xcarchive`（或直接 `.ipa`） | 校验 `Info.plist` 中 Bundle ID 与 `TARGET_BUNDLE_ID` 一致 |

**取值优先级**（高 → 低）：CLI 参数（`--version`/`--notes`/`--target`/`--bundle-id`）> `pgy_config.sh` / 环境变量 > `PGYUploadHistory.json [0]` > `Info.plist` 自动探测。

**凭证变量**：`PGY_USER_KEY`、`PGY_API_KEY` —— 只允许来自 `pgy_config.sh`（gitignored）或环境变量。

### 4.2 输出契约 / 成功判定

`--json` 模式下 stdout **恰好一行** JSON（中间日志全部走 stderr）：

```json
{"status":"success","version":"1.0.3.2","versionTarget":"测试版本",
 "updateDescription":"...","downloadUrl":"https://www.pgyer.com/xxxx",
 "archivePath":"...","ipaPath":"...","logPath":"...","monitorPath":"...","error":null}
```

| 字段 | 取值 / 含义 |
| --- | --- |
| `status` | `success`（已上传）/ `error`（失败）/ `skipped`（按设计跳过，如 `versionTarget` 为空） |
| `downloadUrl` | 成功时 `https://www.pgyer.com/<buildShortcutUrl>`；否则 `null` |
| `error` | 失败原因（Bundle ID 不匹配 / 签名失败 / 网络问题 / 控制文件非法）；成功为 `null` |
| `logPath` / `monitorPath` | `$TMPDIR/pgy_upload_<pid>.log` 与 `$TMPDIR/pgy_monitor_<pid>.html` |

- [x] **成功判定**：`status == "success"` 且 `downloadUrl` 非空，且退出码 `0`。
- [x] **错误路径可区分**：`status == "error"` 且 `error` 非空，退出码 `1`；不得静默返回空结果。
- [x] **跳过可区分**：`status == "skipped"`，退出码仍为 `0`（按设计跳过不等于失败）。
- **退出码**：`archive_upload.sh` 与 `pgy_upload.sh --json` 均为 `0`=成功或跳过、`1`=任意失败；**未传 `--json` 时（Xcode Build/Post-actions 场景）恒为 `0`**——上传失败不得阻塞 Build，错误只体现在监控页与日志。
- **诊断入口**：`$TMPDIR/pgy_upload_*.log`。脚本一旦启动必写日志；**无日志 = 脚本根本没启动**（多为 scheme 未重载，见 `OPEN-001`）。

## 5. 依赖与约束

### 5.1 环境依赖

| 依赖 | 版本 | 备注 |
| --- | --- | --- |
| macOS | — | 依赖 `open`（监控页）与 `base64 -i`（二维码）等 Darwin 行为 |
| `/bin/bash` | 3.2+ | 引擎按系统 bash 编写；`pgy_upload.sh` 用 `set -e`，`archive_upload.sh` 用 `set -euo pipefail` |
| Xcode 命令行工具 | 需支持 `archive` / `-exportArchive` | `archive_upload.sh` 前置检查 `command -v xcodebuild` |
| `jq` | 任意 | **硬依赖**：`pgy_upload.sh` 在依赖检查处缺失即 `exit 1`（`OPEN-003`） |
| `python3` | 3.x | 仅用于拼装 JSON（`archive_upload.sh`、`link-skill.sh` 同样依赖） |
| `curl` | 任意 | 上传与二维码下载；连接超时 30s、总超时 600s |
| 外部命令 | `awk`（`--help`）、`open`、`base64`、`xcodebuild -exportArchive` | 由 macOS 自带 |

### 5.2 外部契约（改版即失效的核心风险）

| 外部系统 | 契约点 | 失效表现与重探方式 |
| --- | --- | --- |
| 蒲公英 API v2 | `POST https://www.pgyer.com/apiv2/app/upload`，multipart 字段 `file` / `uKey` / `_api_key` / `updateDescription` / `buildUpdateDescription` / `buildVersion`；成功判定 `code == 0` 且 `data.buildShortcutUrl` 非空；二维码 `data.buildQRCodeURL` | 上传返回 `status=error` 且 `error` 为蒲公英 `message`。重探：直接 `curl -F` 手工调用该端点观察响应结构 |
| 蒲公英下载页 | `https://www.pgyer.com/<buildShortcutUrl>` | 链接 404 / 指向他包 |
| Xcode `$ARCHIVE_PATH` | **仅在 Scheme 的 Post-actions 中被注入**；普通 Build Phase Run Script 内恒为空 | 若误接在 Build Phase，脚本落入等待模式轮询最新 `.xcarchive`（行为不确定），或超时失败 |
| Xcode scheme 加载 | Xcode **不热加载**外部手改的 `.xcscheme` | 表现为「不上传、无日志」（`OPEN-001`）；重探：`grep -c "Upload to Pgyer" <scheme 文件>` + 完全退出重开 Xcode |
| 宿主目录结构 | `archive_upload.sh` 以 `$(dirname $0)/../..` 反推 `ios/`，即假定子模块位于 `<宿主>/ios/Scripts/<repo>/` | 子模块放在别处 → 默认 `--config` / `--workspace` 路径全错；须显式传参 |
| IPA 导出 | `xcodebuild -exportArchive` + 引擎生成 `ExportOptions.plist`，`PGY_METHOD` 决定签名方式 | 导出失败 → `error: xcodebuild -exportArchive 失败`；需项目侧有效签名 |

### 5.3 安全约束

- 凭证只从环境变量 / `pgy_config.sh`（gitignored）读取；**禁止**硬编码、禁止入库、禁止出现在日志/报错正文。
  已核实：`pgy_upload.sh` 的日志与 JSON 只输出 `versionTarget` / `version` / `updateDes` 等非敏感字段，不打印 key。
- `.gitignore` 必须忽略 `pgy_config.sh` 与 `.env*`（保留 `.env.example`）。
- **部署产物**：`pgy_config.sh` 与 `PGYUploadHistory.json` 属宿主项目侧文件，不在本仓库内维护。

## 6. 适用场景与限制

### 6.1 适用

- 任意能产出 `.xcarchive` 的 iOS 项目（原生 / Flutter / React Native / Unity）。
- **多项目共享同一引擎**：各项目仅持有 `pgy_config.sh` + `PGYUploadHistory.json`（密钥与是否上传的差异全在配置侧）。
- AI / CI 全自动触发（`archive_upload.sh`），或 Xcode GUI Archive 后自动上传（Post-actions）。
- Flutter 工程可用 `PGY_DEBUG_CHECK` 拦截 Debug 包误传。

### 6.2 不适用

- 非 macOS 环境（缺 `xcodebuild` / `open` / `base64`）。
- 无签名能力的环境（无证书 / profile）。
- 工程结构与 `Runner` scheme 假设不一致、且调用方未传 `--workspace` / `--scheme` / `--config`。
  - 已知适配范式（**已验证**）：XcodeGen 原生工程（如 `xiyuWebBrowser`，无 `Runner` scheme、无共享 scheme）
    应采用「Build Phase `runOnlyWhenInstalling: true` 调 `pgy_upload.sh`」+「项目专属包装脚本预置 `--workspace *.xcodeproj --scheme <本scheme> --config pgy_config.sh`」，而非 Post-actions。
- Android / Web / 桌面等其他分发目标。

## 7. 已知问题与开放问题

> 每条在 frontmatter 的 `known_issues` 中同步一条 `OPEN-NNN` 记录；已解决的移出本表，
> 处置过程写入 `changelog/CHANGES.md`。

| ID | 严重度 | 问题 | 触发条件 | 影响 | 规避方案 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| OPEN-001 | medium | Xcode 不热加载外部手改的共享 `.xcscheme` | 用文本/脚本注入 Post-actions，且未完全退出重开 Xcode | Archive 后不上传、`$TMPDIR` 无 `pgy_upload_*.log`（脚本根本没启动） | ① 优先走 CLI 入口 `archive_upload.sh`（不依赖 scheme 缓存）；② 在 Xcode `Edit Scheme → Archive → +` 手动添加；③ 接入后**完全退出 Xcode 重开** | by-design |
| OPEN-002 | low | `--notes` 仅在 CLI/手动入口生效 | 走 Xcode Post-actions 入口时该参数未传入 | 更新说明恒取 `PGYUploadHistory.json [0].updateDes`，改 `--notes` 看似无效 | 改 JSON 的 `updateDes`，或改走 `archive_upload.sh` | by-design |
| OPEN-003 | low | `jq` 为硬依赖但未在文档前置条件登记 | 新环境未装 `jq` | 引擎直接 `exit 1`，README / `skill/SKILL.md` 均未提示 | 接入前 `brew install jq`；待补入 README 与 SKILL.md 前置条件 | open |
| OPEN-004 | low | README「架构」文件树与实际仓库内容不一致 | 阅读 README 判断仓库内容 | 文件树未列出 `archive_upload.sh` / `link-skill.sh` / `skill/`，易误以为只有 `pgy_upload.sh` | 以本文件 §3 与仓库实际为准；待补 README 文件树 | open |
| OPEN-005 | medium | 子模块接入要求引擎 commit 已 push origin | 仅本地 commit 未 push 即在他处/新克隆使用 | 新克隆解析不到 gitlink commit，子模块拉取失败 | 引擎侧改动先 push 再由宿主更新 gitlink；本机 sandbox 无 codeup 凭证，需人工 push | by-design |

## 8. 变更管理协议（强制执行）

### 8.1 三份文档的职责边界

| 文件 | 职责 | 更新时机 |
| --- | --- | --- |
| `STATUS.md` | **实现真相 + 交接主文档**：目标、入口、契约、约束、已知问题 | 任何功能或规范性变更后立即更新 |
| `changelog/CHANGES.md` | **变更流水**：每次变更一条（CR-NNN），追加式，禁止删除 | 每次变更后追加到顶部 |
| `changelog/vX.Y.Z.md` | **版本档案**：迭代原因 / 内容 / 效果 | 版本号递增时新建 |

> 另：`experience/` 沉淀可复用经验与执行日志（L-NNN / run_id）；`AGENTS.md` 是跨工具入口。

### 8.2 变更流程

```
① READ      读取 STATUS.md（确认现有实现与已知问题）+ experience/LESSONS.md
② ASSESS    判断变更类型：功能变更 / 规范性变更（文档、协议）/ 校准修正
③ CALIBRATE 若 STATUS.md 缺失或与实现不一致 → 先校准（改代码或改文档）并在 §9 留痕，再继续
④ IMPLEMENT 功能变更须先验证，通过后再并入主干
⑤ UPDATE    同步 STATUS.md（frontmatter + 受影响章节）+ 追加 changelog/CHANGES.md
⑥ VERSION   影响运行行为 → 升版本 + 新建 changelog/vX.Y.Z.md + 更新 changelog/CHANGELOG.md 索引
```

### 8.3 变更记录条目模板（追加到 `changelog/CHANGES.md` 顶部）

```markdown
## CR-NNN — <一句话标题>

- **变更时间**：YYYY-MM-DD
- **变更类型**：功能变更 | 规范性变更 | 校准修正
- **关联版本**：vX.Y.Z（规范性/校准可标注「无版本变更」）
- **变更原因**：<为什么改，关联 OPEN-XXX / L-XXX / CR-XXX>

**变更前后差异**

| 项 | 变更前 | 变更后 |
|----|--------|--------|
| ... | ... | ... |

**影响范围**：<受影响的文件 / 脚本 / 调用方式>
**兼容性说明**：向后兼容 | 破坏性变更（需调用方调整：<具体内容>）
**验证方式**：<命令或检查项，须给出可复现的判定标准>
```

### 8.4 版本号规则

| 变更类型 | 递增 | 示例 |
| --- | --- | --- |
| 破坏性变更、架构重构、首个可用版本 | 主/次版本 | 0.1.0 → 1.0.0 |
| 新能力、逻辑优化 | 次版本 | 0.1.0 → 0.2.0 |
| 文档修正、排障补充、校准 | 修订号 | 0.1.0 → 0.1.1 |

> **本项目特别约定（优先于上表）**：引擎被宿主项目以 **submodule gitlink** 引用，版本号即"宿主更新 gitlink 的锚点"。
> 因此**只有改动影响宿主调用行为**时（参数、默认值、输出 JSON 字段、退出码、生成物路径）才升版本并写版本档案；
> 纯文档修正 / 错别字 / 排障补充 / 不改变行为的校准 → 记 CR 并标注「无版本变更」，**不升版本**。
> （依据：本治理体系的设计规则——「影响运行行为 → 升版本」，未影响运行行为的校准只需在 §9 留痕。）
> 注：v1.0.0 为治理基线建立时的现状快照，非发布版本（见 §1）。

### 8.5 变更完成检查清单

- [ ] `STATUS.md` frontmatter 的 `project_version` / `last_calibrated` 已更新
- [ ] `STATUS.md` 正文受影响章节已同步（能力表 / 契约表 / 已知问题表）
- [ ] `changelog/CHANGES.md` 已追加条目（含验证方式）
- [ ] 影响运行行为的变更已升版本并建 `changelog/vX.Y.Z.md` + 更新 `CHANGELOG.md` 索引
- [ ] 新问题已在 §7 分配 `OPEN-NNN` 编号
- [ ] 已记录执行日志到 `experience/execution-log.json`
- [ ] 已完成语法/构建校验，文档与代码一致

## 9. 校准记录

### 9.1 2026-09-19 首次基线（建立本文件时）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | 仓库现状核对 | 与 README / `skill/SKILL.md` 记述一致；无 TODO/FIXME 残留 | 据实登记 §2 能力表（C1–C10），未纳入"不做"范围的缺口登记为 `OPEN-003` / `OPEN-004` |
| 2 | 治理基线建立 | 由 `xiyu-project-governance` 脚手架生成 | 记 CR-001，版本记 1.0.0（现状快照语义见 §1） |
| 3 | `skill/SKILL.md` 编码缺陷 | 第 13 行含 2 个 UTF-8 替换字符（U+FFFD）：`测试\ufffd\ufffd员`，应为 `测试人员`；经 `git show HEAD:skill/SKILL.md` 确认**该乱码自 HEAD 起即存在**（历史遗留，非本次引入） | 记 CR-002 校准修正（不改运行行为，无版本变更） |
| 4 | `.gitignore` 凭证规则缺口 | 原文件仅忽略 `pgy_config.sh` / `*.log` / `.DS_Store`，缺 `.env*` 规则 | 在保留既有规则前提下追加 `.env*`（保留 `!.env.example`）与编辑器目录，纳入 CR-001 影响范围 |
| 5 | 工作区未提交改动 | 基线建立时存在上一会话遗留：`.workbuddy/memory/2026-08-0{6,7}.md` 追加、`skill/SKILL.md` 新增「Xcode GUI Archive Post-actions」章节 | 未回滚（属有效文档产出），随 CR-002 同批提交并在条目中注明 |
| 6 | 全局 gitignore 陷阱 | 本机 `~/.gitignore_global` 含 `.gitignore` 一行 | 本项目 `.gitignore` **已在版本控制内**（`git ls-files` 可见），故 `git check-ignore` 不命中、规则正常入库，无需处理 |
