---
document_type: "project-status"
schema_version: "1.0"
status_version: "1.0"
project_name: "archive-pgy-uploader"
project_version: "1.3.0"
last_calibrated: "2026-09-19"
calibration_state: "current"
authority: "本文件是本项目现状的唯一事实来源；与 README / AGENTS.md 冲突时以本文件为准"
repository: "https://github.com/xiyuyanhen/archive-pgy-uploader"
project_type: "code"
positioning: "通用 Xcode Archive → 蒲公英(Pgyer) 自动上传引擎（多项目以 submodule 共享，配置与密钥按项目分离）"
maturity: "已在 3 个 iOS 项目实际使用且接入方式已统一为 submodule（xiyuScoreboard / xiyu_todo_list / xiyuWebBrowser）；治理基线自 v1.0.0 起"
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
  - id: "hosts-sync"
    name: "sync-hosts.sh — 本机多宿主 gitlink 跟随同步（.local 名单模式，仅本机使用）"
    path: "sync-hosts.sh"
    args: "[--check|--apply|--list|--json] [--target release|local|origin] [--tag vX.Y.Z] [--only <names>] [--no-commit] [--allow-dirty] [--allow-downgrade] [--dry-run] [--add <name> <宿主路径> <子模块相对路径>] [--remove <name>] [--install-hook [--auto]] [--uninstall-hook]（--from-origin = --target origin，兼容别名）"
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
  - {id: "OPEN-005", severity: "medium", status: "by-design", summary: "子模块接入要求引擎 commit 已 push origin；仅本地 commit 会导致他人/新克隆解析不到 gitlink。自 v1.2.0 起发布标签（vX.Y.Z）同理需 push，否则他人/新克隆看不到 release 同步目标"}
---

# STATUS.md — 项目状态与交接基线

> 本文件是 `archive-pgy-uploader` 的**实现真相索引与交接主文档**。任何 Agent 在修改本项目之前，
> **必须先读取本文件**；任何功能或规范性变更之后，**必须同步更新本文件**。
> 机器可读摘要见文件顶部 YAML frontmatter，正文为等价的人类可读展开。

## 1. 状态概览

| 项 | 值 |
| --- | --- |
| 项目名称 | `archive-pgy-uploader` |
| 项目版本 | 1.3.0 |
| 状态文档版本 | 1.0 |
| 最近校准 | 2026-09-19（v1.3.0：新增「半套接入」`unregistered-gitlink` 的检测与自动补登；同批修复 `--apply` 的 tab 折叠串列缺陷） |
| 一句话定位 | 通用 Xcode Archive → 蒲公英(Pgyer) 自动上传引擎（多项目以 submodule 共享，配置与密钥按项目分离） |
| 成熟度 | 已在 3 个 iOS 项目实际使用且接入方式已统一为 submodule（xiyuScoreboard / xiyu_todo_list / xiyuWebBrowser）；治理基线自 v1.0.0 起 |
| 远端仓库 | **公开** GitHub：https://github.com/xiyuyanhen/archive-pgy-uploader （SSH：`git@github.com:xiyuyanhen/archive-pgy-uploader.git`）｜历史（codeup，已不再作 origin）：https://codeup.aliyun.com/61c852431ccc3a1faae0a9fa/scripts/archive-pgy-uploader.git |

> **版本号语义**：本项目在治理基线建立前**没有版本号体系**（无 git tag、脚本内无版本常量）。
> `v1.0.0` 不表示"发布版本"，而是**建立治理基线时的现状快照**——即当时 HEAD 的可用能力集合。
> 后续按 §8.4 规则递增；`v1.0.0.md` 是首份版本档案。
>
> **自 v1.2.0 起，版本号与 git 发布标签（`vX.Y.Z`）绑定**：标签是各宿主 gitlink 的同步目标
> （`sync-hosts.sh --target release` 默认取最新 `v*`）。因此「升版本」不再只是文档动作，
> 它决定宿主何时被推进。相应地，**只有影响宿主调用行为的变更才打标签**。
> `v1.1.0` 为事后补打的第一个发布标签（`v1.0.0` 属治理基线快照，按上述语义**不打标签**）。

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
| C11 | 本机多宿主跟随同步：按 `.local/hosts.json` 名单体检 / 批量更新各宿主 gitlink（含可选 post-commit 自动跟随） | `sync-hosts.sh` | 稳定 | 仅本机使用，**不 push**；名单 gitignored（v1.1.0 新增） |
| C12 | **发布标签驱动的同步目标**：默认只跟「最新发布标签 `v*`」，只有影响宿主调用行为的变更才推进标签 → 文档 / 记忆类提交不再让所有宿主无谓重新 pin | `sync-hosts.sh --target release`（默认）+ `--tag` | 稳定 | v1.2.0 新增；`--target local/origin` 保留为开发期 / 交接期逃生口 |
| C13 | **半套接入检测与自动补登**：识别「`.gitmodules` 已入库但 gitlink 未登记」并自动补登（可同时把版本对齐到目标）；仅对真正的子模块 checkout 生效，vendored 副本不误补登 | `sync-hosts.sh`（状态 `unregistered-gitlink`） | 稳定 | v1.3.0 新增；该状态对新克隆是**静默**失效（`update --init` 不报错也不检出） |

### 2.2 明确不做（范围外）

- **不携带任何项目密钥或路径**：本仓库是共享引擎，禁止出现真实 `PGY_USER_KEY` / `PGY_API_KEY`、项目绝对路径、Bundle ID 真值。
- **不管理签名与证书**：不做证书申请、profile 生成、team 配置；依赖项目自身签名能力（`xcodebuild -exportArchive` 的 `ExportOptions.plist` 由引擎生成）。
- **不 push、不替使用者决定远端**：引擎本体不 push；`sync-hosts.sh` 仅在**宿主侧做本地 commit**（更新 gitlink），
  push 一律由人决定。子模块 gitlink 的 push（见 `OPEN-005`）由使用者本地完成（本机 sandbox 内推送不可行：
  origin 现为 GitHub SSH，`~/.ssh/id_ed25519` 带口令且 `ssh-agent` 无已加载身份 → 无法非交互认证）。
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

### 3.3 本机多宿主同步（`sync-hosts.sh`，v1.1.0 新增 / v1.2.0 发布标签目标 / v1.3.0 补登半套接入）

> **仅在本机使用，不进入宿主调用链**——宿主项目无需更新 gitlink 即可继续工作。
> 名单文件 `.local/hosts.json`（**gitignored、本机私有**）：`{schema, engineRemote, hosts:[{name, path, submodule}]}`，
> 可用 `PGY_SYNC_REGISTRY` 覆盖名单路径。

**同步目标（`--target`，默认 `release`）**——决定「宿主该跟到哪个引擎版本」：

| 取值 | 含义 | 适用 |
| --- | --- | --- |
| `release`（默认） | 跟**最新发布标签** `v*`（`--sort=-v:refname` 取最新） | 日常：只有发布才移动宿主 |
| `local` | 跟**本机引擎仓 HEAD** | 引擎开发期快速联调（无版本锚点，勿用于交接） |
| `origin` | 跟 **`origin/HEAD` 指向的分支** | 交接 / 多机 / CI（需先 push） |

> `release` 是默认目标；引擎仓**没有任何 `v*` 标签**时直接报错并给出指引（不会静默退回 HEAD）。
> `--from-origin` 保留为 `--target origin` 的兼容别名。

| 参数 | 说明 |
| --- | --- |
| `--check`（默认） | 只读体检：逐宿主报告固定 commit / 落后多少 / 状态 / 是否脏 |
| `--json` | stdout **单行 JSON**（`status` / `engine{path,head,target,target_short,source,release_tag}` / `summary{total,outdated,unregistered,ahead_of_target,attention}` / `hosts[]` / `error`） |
| `--list` | 打印本机名单 |
| `--target <release\|local\|origin>` | 选择同步目标（默认 `release`） |
| `--tag vX.Y.Z` | 在当前 HEAD 打**发布标签**（发布动作）；与 `STATUS.md` 的 `project_version` **不一致即拒绝**，工作区脏也拒绝 |
| `--apply` | 对「状态 = `outdated` 或 `unregistered-gitlink` 且工作区干净」的宿主：`fetch` + `checkout --detach <目标>` + `git add <子模块路径>` + **本地** commit（`unregistered-gitlink` 见下） |
| `--no-commit` | 只 checkout + stage，不 commit |
| `--only <a,b>` | 只处理指定宿主 |
| `--allow-dirty` | 越过「宿主工作区脏则跳过」的默认拒绝（gitlink 更新带 pathspec，不会卷入宿主其它改动） |
| `--allow-downgrade` | 允许把 `ahead-of-target`（pin 比目标新）的宿主**回落到**目标（默认不动，见下） |
| `--dry-run` | 只打印将执行的动作 |
| `--add` / `--remove` | 维护本机名单（`--add <name> <宿主路径> <子模块相对路径>`） |
| `--install-hook [--auto]` / `--uninstall-hook` | 装 / 卸本机 `post-commit` 钩子；`--auto` **只在「HEAD 正好是发布标签」（= 一次发布）时**才 `--apply`，普通提交只提示；`PGY_SYNC_HOOK_DISABLE=1` 可临时禁用 |

**状态取值**：`up-to-date` / `outdated` / `ahead-of-target`（宿主 pin 是目标的**后代**，即比发布版本新）/
`unregistered-gitlink`（**半套接入**：`.gitmodules` 已入库 + 目录是合法子模块 checkout，但 gitlink 未登记）/
`uncommitted-gitlink`（子模块已 add 但宿主从未 commit）/ `diverged` / `unknown-engine-commit` /
`not-a-submodule` / `not-a-repo` / `missing`。

- 只有 `outdated` / `unregistered-gitlink`（以及显式 `--allow-downgrade` 下的 `ahead-of-target`）
  会被 `--apply` 改动；其余只给人工提示。
- `ahead-of-target` **是良性状态**（宿主已包含发布版本的行为），不计入「需人工处理」，也不会让 `--check` 返回 `2`。

**`unregistered-gitlink`（半套接入，v1.3.0 新增）——危害是静默的**

成因：`.gitmodules` 被提交了，但 gitlink 没进索引/HEAD（例如把 `.gitmodules` 单独 commit、或 `git rm --cached` 子模块）。
本地 `git status` 只把该目录显示成**未跟踪**，看不出异常。**实测**新克隆的后果：

| 状态 | 新克隆后 `git submodule status` | 子模块目录 | `submodule update --init` 退出码 |
| --- | --- | --- | --- |
| 半套接入（未修） | **空**（git 完全不认识该路径） | **不存在** | **0（不报错、也不检出）** |
| 已补登 | `<sha> sub (vX.Y.Z)` | 存在 | 0 |

即：**不报错、静默不检出**，直到构建时才发现引擎脚本缺失。`--apply` 会自动补登：
`git add -- <子模块路径>`（对嵌仓库即写模式 `160000`）+ 本地 commit；若该子模块当前 HEAD 落后于目标，
会先 `fetch` + `checkout --detach <目标>` 再补登（一条命令同时完成「补登 + 对齐」）。
**仅为真正的子模块 checkout 补登**（判据：其 git dir 落在宿主 `.git/modules/` 下）——
vendored 副本 / 嵌套仓库不会被误补登，而是被报为 `not-a-submodule` 并提示走 `git submodule add`。
`uncommitted-gitlink` 属「人已 stage、只差 commit」，**不自动处理**（避免猜测人的意图）。

**退出码**：`0` = 一致或全部成功；`2` = 存在落后 / 半套接入 / 需人工介入（仅 `--check` 语义）；`1` = 执行出错。
**JSON `status` 取值**：`ok` / `outdated` / `unregistered` / `attention` / `error`（`unregistered` 为 v1.3.0 新增）。
**前置依赖**：`jq`（硬依赖，启动即校验）、`git`。

```bash
bash sync-hosts.sh                          # 体检：谁没跟上最新发布版本
bash sync-hosts.sh --apply                  # 一键把本机所有登记宿主推到最新发布标签（仅本地 commit）
bash sync-hosts.sh --tag v1.2.0             # 判定为行为变更 → 打发布标签（标签即宿主同步目标）
bash sync-hosts.sh --target local --check   # 开发期：改看本机 HEAD
bash sync-hosts.sh --install-hook --auto    # 可选：发布时自动跟随（普通提交不动宿主）
```

## 4. 输入输出契约

### 4.1 输入契约

| 形态 | 示例 | 解析结果 |
| --- | --- | --- |
| CLI 参数 | `--target "测试版本"` | 版本目标标签；决定是否上传 |
| 项目配置 `pgy_config.sh`（shell，`source` 执行） | `PGY_USER_KEY=... ; TARGET_BUNDLE_ID=com.example.app` | 凭证 + 身份 + 控制文件路径（**该文件必须 gitignored**） |
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
| `jq` | 任意 | **硬依赖**：`pgy_upload.sh` 与 `sync-hosts.sh` 在依赖检查处缺失即 `exit 1`；README 与 `skill/SKILL.md` 已登记（v1.1.0 关闭 `OPEN-003`） |
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
    应采用「Build Phase `runOnlyWhenInstalling: true` 调 `pgy_upload.sh`」+「项目专属包装脚本预置
    `--workspace *.xcodeproj --scheme <本scheme> --config <配置路径>`」，而非 Post-actions。
  - **`xiyuWebBrowser` 的收敛后布局（v1.1.0，CR-003）**：仓库根 `pgy-archive-uploader/`（**git submodule**，不要再放密钥）+
    兄弟目录 `pgy-archive-config/`（`pgy_config.sh` 已 gitignore、`PGYUploadHistory.json` 入库）+
    宿主根 `archive_and_upload.sh`（项目专属包装，预置 `--workspace` / `--scheme` / `--config`）。
    Build Phase 必须**显式**传 `--config "${PROJECT_DIR}/pgy-archive-config/pgy_config.sh"`——
    一旦凭证移出引擎目录，引擎的目录探测就找不到它了。
  - ⚠️ **XcodeGen 工程的额外坑**：`project.pbxproj` 可能早已与 `project.yml` 不同步（有人在 Xcode GUI 里改过设置而未回写 spec），
    此时盲目 `xcodegen generate` 会**清空** `DEVELOPMENT_TEAM` 等设置。改 spec 后应先做「生成到临时目录 + diff 评估」，
    必要时改为**就地替换** pbxproj 中目标片段。详见 `experience/LESSONS.md` L-008。
- Android / Web / 桌面等其他分发目标。

## 7. 已知问题与开放问题

> 每条在 frontmatter 的 `known_issues` 中同步一条 `OPEN-NNN` 记录；已解决的移出本表，
> 处置过程写入 `changelog/CHANGES.md`。

| ID | 严重度 | 问题 | 触发条件 | 影响 | 规避方案 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| OPEN-001 | medium | Xcode 不热加载外部手改的共享 `.xcscheme` | 用文本/脚本注入 Post-actions，且未完全退出重开 Xcode | Archive 后不上传、`$TMPDIR` 无 `pgy_upload_*.log`（脚本根本没启动） | ① 优先走 CLI 入口 `archive_upload.sh`（不依赖 scheme 缓存）；② 在 Xcode `Edit Scheme → Archive → +` 手动添加；③ 接入后**完全退出 Xcode 重开** | by-design |
| OPEN-002 | low | `--notes` 仅在 CLI/手动入口生效 | 走 Xcode Post-actions 入口时该参数未传入 | 更新说明恒取 `PGYUploadHistory.json [0].updateDes`，改 `--notes` 看似无效 | 改 JSON 的 `updateDes`，或改走 `archive_upload.sh` | by-design |
| OPEN-005 | medium | 子模块接入要求引擎 commit 已 push origin | 仅本地 commit 未 push 即在他处/新克隆使用 | 新克隆解析不到 gitlink commit，子模块拉取失败（v1.2.0 起**发布标签同理需 push**，否则看不到 release 目标） | 引擎侧改动先 push 再由宿主更新 gitlink；本机 sandbox 无法完成推送（无可用凭证/密钥身份），需人工 push | by-design |

**已关闭条目**（处置过程见 `changelog/CHANGES.md`，本表不再保留）：

| ID | 关闭版本 | 关闭方式 |
| --- | --- | --- |
| OPEN-003 | v1.1.0 | `jq` 硬依赖补登进 `README.md` 与 `skill/SKILL.md`；`sync-hosts.sh` 亦启动即校验 |
| OPEN-004 | v1.1.0 | README 文件树补全（`archive_upload.sh` / `link-skill.sh` / `skill/` / `sync-hosts.sh` / `.local/`） |
| OPEN-006 | 无版本变更（CR-011） | 整体迁移完成：3 个宿主 `.gitmodules` 与 `submodule.<name>.url` 改指公开 GitHub 仓（`git submodule sync` 同步 `.git/modules/*/config`），各宿主本地提交（`0e69d28` / `7d2d3ba` / `05ee675`）；已用**全新克隆 + `submodule update --init`** 端到端证明可匿名解析（详见 §9.9） |

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
>
> **自 v1.2.0 起，升版本的收尾动作包含打发布标签**：
> `bash sync-hosts.sh --tag vX.Y.Z`（或 `--tag vX.Y.Z --apply` 一并推宿主）。标签即宿主同步目标，
> 因此「升版本」直接影响宿主何时被推进——**不该升版本时不要打标签**，否则会让所有宿主无谓重新 pin。
> `--tag` 内置护栏：标签必须与 frontmatter 的 `project_version` 一致，且工作区干净、标签不存在。

### 8.5 变更完成检查清单

- [ ] `STATUS.md` frontmatter 的 `project_version` / `last_calibrated` 已更新
- [ ] `STATUS.md` 正文受影响章节已同步（能力表 / 契约表 / 已知问题表）
- [ ] `changelog/CHANGES.md` 已追加条目（含验证方式）
- [ ] 影响运行行为的变更已升版本并建 `changelog/vX.Y.Z.md` + 更新 `CHANGELOG.md` 索引
- [ ] 影响宿主调用行为的变更已打发布标签（`sync-hosts.sh --tag vX.Y.Z`），并提醒 push 标签（`OPEN-005`）
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

### 9.2 2026-09-19 v1.1.0 校准（多宿主接入收敛）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | 三宿主接入状态核查 | `xiyuScoreboard` = submodule（落后引擎 HEAD 4 个 commit）；`xiyu_todo_list` = submodule 但 gitlink 仅在索引（宿主从未 commit，落后 3 个）；`xiyuWebBrowser` = 文件复制且已漂移（缺治理目录、`skill/SKILL.md` 与引擎不一致） | 收敛 `xiyuWebBrowser` 为 submodule（CR-003）；另两处落后/未提交由 `sync-hosts.sh` 体检输出呈现，交由使用者决定何时同步（本轮未执行真实 `--apply`） |
| 2 | `xiyuWebBrowser` 副本内含真实密钥 | `pgy-archive-uploader/pgy_config.sh` 的 `PGY_USER_KEY` / `PGY_API_KEY` 已填实（长度 32、非占位符），但该文件被副本 `.gitignore` 忽略、**未入库**（无泄漏） | 记为**结构缺口**而非安全事故：把凭证与控制文件移出引擎目录到兄弟目录 `pgy-archive-config/`，并对 `pgy_config.sh` `chmod 600` |
| 3 | 引擎仓 `.git/hooks/` 目录不存在 | git 仓库允许没有 hooks 目录；直接写钩子文件会 `No such file or directory` | `sync-hosts.sh --install-hook` 改为先 `mkdir -p "$(dirname "$HOOK_FILE")"`；纳入经验条目 |
| 4 | `project.yml` ↔ `project.pbxproj` 不同步 | 就地 `xcodegen generate`（2.46.0）除目标改动外还会清空 `DEVELOPMENT_TEAM`、改写 `LD_RUNPATH_SEARCH_PATHS` | 本轮**不重生成**，改为就地替换 pbxproj 中目标 `shellScript` 段（实测差异 1 增 1 删）；沉淀为 L-008 并在 §6.2 警示 |
| 5 | 文档债 `OPEN-003` / `OPEN-004` | 与本版新增能力直接相关（新增入口同样硬依赖 `jq`；README 文件树还要再加一项） | 随 CR-004 一并关闭，见 §7「已关闭条目」 |
| 6 | 引擎 HEAD 未 push origin | `origin/master` 停在 `155046c`，本机 HEAD 为 `6fadcb2` | 不自动 push（push 由使用者主导）；在 CR-003 与 `changelog/v1.1.0.md` 中显式标注 `OPEN-005` 的影响面 |
| 7 | §4.1 输入契约示例含**真实 Bundle ID** | `TARGET_BUNDLE_ID=com.xiyu.browser` 出现在示例单元格，违反本仓 §2.2「不得写入真实 Bundle ID（示例一律用占位符）」；系基线建立时未剥离 | 校准修正为 `com.example.app`（仅文档，不改运行行为；同时纳入 CR-004 的影响范围） |

### 9.3 2026-09-19 v1.2.0 校准（同步目标改为发布标签驱动）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | 同步目标语义（使用者拍板） | v1.1.0 的默认目标是**本机 HEAD**，即「每提交一次就推进各宿主 pin」。实测两个**纯文档/记忆**提交（`6fadcb2`、`c6c32b4`）各引发一轮 3 宿主 gitlink 更新；上一轮为避免此副作用，记忆文件**故意未提交** | 默认目标改为 `release`（最新发布标签 `v*`），只有影响宿主调用行为的变更才推进标签；`local` / `origin` 保留为开发期与交接期逃生口 |
| 2 | 仓库**没有任何 git tag** | 新默认一上线会立刻不可用（无标签可跟）。CHANGELOG 原已声明 `v1.0.0` 是「治理基线快照，不是发布版本」 | 补打 `v1.1.0`（指向 `0734932`，第一个影响行为的发布；**不给 `v1.0.0` 打标签**，保持历史诚实）；并把「版本号 ↔ 发布标签」的绑定与判据写入 §1 与 §8.4 |
| 3 | 钩子语义与新默认**互相矛盾** | 原 `--auto` = 「每次提交后 `--apply`」；且**常规顺序是「先提交、后打标签」，而 `post-commit` 只对 commit 生效 → 钩子永远赶不上发布**（HEAD 在 commit 时尚未带标签） | ① 钩子改为「仅当 HEAD 正好是发布标签时才 `--apply`」，定位为**兜底**；② 发布主路径改为 `--tag vX.Y.Z --apply`（打标签 + 推宿主，一条命令）；③ `--tag` 单独使用时打印后续两步命令 |
| 4 | 状态机缺一个状态 | 原二值（`up-to-date` / `outdated`）无法表达「宿主 pin 是目标的**后代**」——当时 3 个宿主 pin 在 `c6c32b4`、而 v1.1.0 标签在 `0734932`，会被误判为 `diverged` | 扩为四值，新增 `ahead-of-target` 并定义为**良性**（宿主已含发布版本行为）：不计入「需人工处理」、`--check` 不因此返回 `2`；回落需显式 `--allow-downgrade` |
| 5 | 钩子的 `--check --quiet` 与文档记述不符 | 钩子注释写「落后时打印报告」，但 `--quiet` 会把报告一起吞掉，实际什么都不打印 | 改为「静默跑取退出码，仅当 `rc=2` 时重跑一次打印完整报告」；`rc=1`（出错）的 `die` 信息本就写在 stderr，不重复打印 |
| 6 | `jq … \| grep -q` 在 `set -o pipefail` 下的隐患 | 读端（`grep -q`）命中即退出 → 写端 `jq` 收 `SIGPIPE`(141) → pipefail 使条件判为「假」。名单重复登记检查会**反向放行**（当前 3 条数据量下不会触发，属潜在缺陷） | 改为 `jq -e 'any(...)'` 内联判定，去掉管道；`--only` 的字符串匹配也改为纯 bash 循环（顺带支持多值与空格容错） |

### 9.4 2026-09-19 校准（CR-006：全角字符吞变量名 + bash 版本归因订正）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | 静态检查扫出两处**真实**缺陷 | `link-skill.sh:76`（软链冲突提示会丢路径）、`pgy_upload.sh:422`（不支持的输入类型报错会丢输入路径）。均为**文案**，不影响控制流 | 改为 `${VAR}`（各 1 行）；记 CR-006（无版本变更）。`pgy_upload.sh:37/568/751` 的同类命中都在注释里，不展开、无需改 |
| 2 | **归因订正**（重要） | 本项目此前记为「**bash 3.2** 在多字节字符前会吞掉变量名」（`execution-log.json` → run-20260919-hosts-sync-and-browser-consolidation）。字节级实测**恰好相反**：`/bin/bash` 3.2.57 正确输出 `[abc\357\274\211tail]`，`/opt/homebrew/bin/bash` 5.3.15 输出 `[\274\211tail]`（值消失 + 字节错位）。根因是 **bash ≥ 5.2 的变量名解析支持多字节字符**；显式 `LC_ALL=C` 不触发，而本机 `LANG="" LC_CTYPE=C` 形态下 5.3 仍触发 | 新增 L-011 记录正确机制与订正说明；在 CR-006 中显式标注「修法不变、归因反转」，避免后人按错方向排障 |
| 3 | **验证盲区**：单解释器验证 | 本项目脚本 shebang 为 `/bin/bash`（3.2.57），但此前一律用 `bash xxx.sh` 验证（PATH 首位 = Homebrew bash 5.x）。两个大版本语言特性不同 | 自本版起，逐文件语法与关键行为**双解释器各跑一遍**（3.2 + 5.x）；已写入 L-011 推广段。`sync-hosts.sh --check` 在两者下输出与退出码一致（已实测） |

### 9.5 2026-09-19 v1.3.0 校准（`unregistered-gitlink` 补登 + tab 折叠串列）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | `unregistered-gitlink` 的危害描述失准 | 实现初稿把后果写成「`git submodule update --init` 会失败（硬故障）」。实测**不是失败**：该命令**退出码 0、不报错、也不检出**，克隆里子模块目录根本不出现 → 属**静默**失效（对构建的破坏更晚、更难查） | 订正脚本头部注释、状态采集处注释与 `--check` 提示文案；并把 A/B 实测表写入 §3.3 |
| 2 | **`--apply` 存在 tab 折叠导致的整行串列**（既有缺陷，被新状态照出） | rows.tsv 用 `\t` 分隔；`pinned` 为空时写出连续两个 `\t`，而 **tab 属 IFS 空白字符 → bash 的 `read` 把连续分隔符折叠成一个**（jq 的 `split("\t")` 不折叠，故二者行为不同）。结果：`--apply` 循环里其后所有列左移一格 → `state` 变 `N`、ACTION 变 `skip:<dirty值>`，并原样写入 JSON `hosts[]` | 所有列一律写非空占位符（`${pinned:--}`），并在该 printf 上方加注释说明「为何不能有空列」；实测 `not-a-submodule` 宿主在修复前后 ACTION 由 `skip:N` 变为 `skip:not-a-submodule` |
| 3 | 自动补登的**安全边界** | 若不加限制，`git add` 会把「随手放进目录的 vendored 副本 / 嵌套仓库」也补登成 gitlink——而该 commit 通常不在引擎仓，补登完立刻是 `unknown-engine-commit`，制造假象 | 新增 `is_submodule_checkout()`：仅当子模块的 git dir 落在宿主 `.git/modules/` 下才认定可补登；否则维持 `not-a-submodule` 并提示走 `git submodule add`。反向对照夹具（vendored 副本）已实测不被登记 |
| 4 | `uncommitted-gitlink` 是否也自动提交 | 该状态是「人已 `git add`、只差 commit」，可能正处于人工编辑中间态 | **刻意不自动处理**，维持人工提示（不猜测人的意图） |
| 5 | 发布后对使用者陈述「远端一个标签都没有」 | **错误结论**：依据是 `git ls-remote --tags origin 2>/dev/null` 的空输出，而该命令实际**退出码 128**（`could not read Username` —— sandbox 内 keychain 不可用且无交互终端）。**空输出是「查询失败」而非「结果为无」**，结论方向相反且未经核实 | 记 CR-008（无版本变更）；新增 L-014 固化判据「`rc=0 且空` 才等于确实没有」；同步订正记忆中的该条陈述；并澄清「push 分支会更新远程跟踪引用（可本地反推）、**push 标签不产生任何本地引用（只能查远端）**」。脚本已核实不依赖网络，故不受影响 |

### 9.6 2026-09-19 校准（CR-008：远端标签状态的判定依据）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | 「远端没有标签」的结论未经核实 | 该结论由**查询失败**（`ls-remote` rc=128）的空输出推出，属「把失败误读成判断依据」（同族：L-009）。它让结论**反向**，且**看起来证据充分**（命令跑了、输出为空、无可见报错） | 订正记忆中的陈述为「**无法判定**，需使用者在有凭证的终端核实」；新增 L-014 记录判据与推广（判定性命令禁止 `2>/dev/null`） |
| 2 | 提交是否已 push | **是**：`origin/master == HEAD == 9d3aa18`，且 reflog 最新一条为 `9d3aa18 refs/remotes/origin/master@{0}: update by push`。此前记忆里「领先 1 个提交」已过期 | 更新记忆为「已 push」；并在 L-014 中记录「分支状态可本地反推、标签状态不可」 |
| 3 | 脚本是否受同类风险影响 | **否**：已核实 `sync-hosts.sh` 无 `ls-remote` / `fetch origin`，`--apply` 只从本地 `$ENGINE_DIR` 取对象，全程离线可用 | 无需改动；但须明确「工具也不会替你确认标签是否已 push」（`OPEN-005`） |

### 9.7 2026-09-19 校准（CR-009：远端可核实性的实测边界 + 本机全局 URL 重写）

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

### 9.8 2026-09-19 变更（CR-010：`origin` 由 codeup 替换为公开 GitHub 仓）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | `origin` 替换 | 已执行 `git remote set-url origin git@github.com:xiyuyanhen/archive-pgy-uploader.git`；`git remote -v` 的 fetch/push 均为该 SSH 地址 | 本节留痕；§5 表格与 frontmatter `repository` 同步更新 |
| 2 | **SSH 形式天然绕开全局 `insteadOf` 重写**（CR-009 曾警告的点） | **已实测**：`git remote get-url --push origin` 原样返回 `git@github.com:...`，未被改写。原因：全局规则是 `url.https://ghfast.top/https://github.com/.insteadof https://github.com/`，只匹配 `https://github.com/` 前缀，**不匹配 `git@github.com:`** → 推送凭证**不会**经 ghfast.top 镜像 | 选 SSH 而非 HTTPS 是本轮的实际收益；日后若改回 HTTPS 需重新评估该重写 |
| 3 | 沙箱内能否推送 | **不能**。`~/.ssh/id_ed25519`（注释 `xiyuyanhen@163.com`）**带口令**（`ssh-keygen -y -P ""` 失败），且 `ssh-add -l` → `The agent has no identities`；`ssh -T git@github.com` → `Permission denied (publickey)`。网络与 22 端口**是通的**（已收到服务端拒绝，非超时） | push 仍由使用者在其终端完成（与 §3 用户主导 push 一致）；`OPEN-005` 的「需人工 push」结论不变，仅理由从「无 codeup 凭证」改为「无可用非交互密钥身份」 |
| 4 | 目标仓当前状态 | **存在且为空**：匿名 `git ls-remote https://github.com/xiyuyanhen/archive-pgy-uploader.git` → `rc=0` 且输出为空。**配对照**：查询不存在的仓 → `rc=128` + `fatal: could not read Username`。故 rc=0+空 是「仓在、无任何 ref」，非「查不到」 | 使用者推 `master`（及标签）后即可正常同步 |
| 5 | 公开前的泄密预检（因目标仓为 **Public**） | **通过**：对全部 25 个跟踪文件扫描 `PGY_API_KEY=`/`PGY_USER_KEY=` 实值、`sk-`、`ghp_`、JWT(`eyJ`)、`-----BEGIN … PRIVATE KEY`、token 赋值、邮箱、手机号、内网 IP、隧道域名 → **零命中**；`.gitignore` 已排除 `pgy_config.sh` / `.local/` / `.env*`。**但**：`.workbuddy/memory/*.md` 与 `execution-log.json` 被跟踪，其中含**内部宿主项目名**（xiyuScoreboard / xiyu_todo_list / xiyuWebBrowser）、本机绝对路径、codeup 命名空间 URL | 已向使用者提示该暴露面；是否把记忆移出版本控制由其决定（本轮**不擅自改动**） |
| 6 | 换远端后的陈旧远程跟踪引用 | `refs/remotes/origin/master` 仍为换 URL 前从 codeup 取到的 `2dbc1a0`（线上 GitHub 实际为空）→ 此刻它**不代表 GitHub 状态**（正是 §9.7 第 6 行预警的情形）。本轮**不删该引用**（非破坏性原则，且它是 codeup 最后状态的唯一本地记录） | 使用者 push 后执行 `git fetch origin && git remote set-head origin -a`，该引用即被修正为 GitHub 真实状态 |
| 7 | 三个宿主的子模块地址**尚未**跟随 | 各宿主 `.gitmodules` 内仍写 codeup 地址（本轮只改引擎自身 `origin`，未动宿主）。含义：**新克隆宿主时引擎仍从 codeup 拉取**，而引擎新提交推往 GitHub → 两边分叉 | **遗留决策**（未擅自改）：若确定迁移到 GitHub，需同步改写 3 个宿主 `.gitmodules` 的 url 并各自提交。列入 `OPEN-006` |

### 9.9 2026-09-20 变更（CR-011：push 已核实 + OPEN-006 整体迁移完成 + 验证方法订正）

| # | 事项 | 判定 | 处理方式 |
| --- | --- | --- | --- |
| 1 | **push 结果（公开仓首次可自证）** | 已核实：匿名 `git ls-remote https://github.com/xiyuyanhen/archive-pgy-uploader.git` → `refs/heads/master` = `98eef5e`（= 本机 HEAD）；`v1.1.0` / `v1.2.0` / `v1.3.0` 三个标签均在，且 `v1.3.0^{}` = `dd06073` 与本文件 §1 记载一致 | 长期悬置的「标签推没推」在本仓**已可自证**（这是迁移到公开仓的直接收益）；`OPEN-005` 的「无法自证」限制在本仓转为「已可自证」 |
| 2 | 陈旧远程跟踪引用已修正 | `origin/master` 原为 codeup 遗留 `2dbc1a0`（不代表 GitHub）→ 现为 `98eef5e`，`git rev-list --left-right --count origin/master...HEAD` = `0 0` | 因 `origin` 是 SSH 且本机无法非交互认证，`git fetch origin` 不可用 → 改用**匿名 HTTPS 显式取**：`git fetch https://github.com/xiyuyanhen/archive-pgy-uploader.git '+refs/heads/*:refs/remotes/origin/*'`，再 `git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master` |
| 3 | `OPEN-006` 整体迁移执行 | 3 个宿主的 `.gitmodules` 与宿主 `.git/config` 的 `submodule.<name>.url` 全部改指 `https://github.com/xiyuyanhen/archive-pgy-uploader.git`；`git submodule sync -- <path>` 一并同步 `.git/modules/<name>/config` 的 origin。**gitlink 全程未变**（仍 `160000 → dd06073`），各宿主仅 `.gitmodules` 一处改动 | 宿主侧本地提交（不 push）：`xiyuScoreboard 0e69d28`、`xiyu_todo_list 7d2d3ba`、`xiyuWebBrowser 05ee675`；`.local/hosts.json` 的 `engineRemote` 同步更新（该字段**无逻辑依赖**，仅 init 时写入） |
| 4 | **端到端证明（迁移是否真的成立）** | 全新克隆 `xiyu_todo_list`（`--no-checkout` + `git read-tree HEAD` 建索引）后执行 `git submodule update --init -- ios/Scripts/archive-pgy-uploader` → stderr 显示 `Submodule ... (https://github.com/xiyuyanhen/archive-pgy-uploader.git) registered`，随后 `checked out 'dd0607310aeafc4bf441852549750dedbfa773fd'`、**退出码 0**（全程匿名，无任何凭证） | OPEN-006 关闭（见 §7 已关闭条目） |
| 5 | **验证方法本身出过一次错，已订正** | 首次验证用 `git clone --no-checkout` 后直接 `git ls-files -s` / `git config -f .gitmodules`，得到 **空结果与 pathspec 报错**，一度像是「gitlink 未登记」——实际是 `--no-checkout` **不建索引**（`ls-files` 读索引故为空；`submodule` 找不到 pathspec） | 改为 `--no-checkout` 后先 `git read-tree HEAD` 建索引再验；沉淀为 `experience/LESSONS.md` **L-015**。**「空结果」又一次差点被当成结论**（L-014 同族，但这次根因不是丢 stderr，而是**前置状态未建立**） |
| 6 | 存储值 vs 生效值（两层都出现） | `.git/modules/<sub>/config` 与 `.gitmodules` 的**存储值**是干净的 `https://github.com/...`；`git remote get-url` 显示的**生效值**是 `https://ghfast.top/https://github.com/...`（被全局 `insteadOf` 改写） | 对**公开**仓的**只读**取用，镜像重写**无害**（不涉及凭证）；但报告与排障时须区分这两个值，避免把生效值误当成配置写错了 |
| 7 | 公开暴露面决策（使用者 2026-09-20 确认） | 使用者确认：`.workbuddy/memory/` 与 `experience/execution-log.json` 中的**内部项目名属测试项目**，可继续公开；**后续不再提交其它隐私信息** | 本仓保留现有跟踪范围不变；后续新增内容遵守该约定（写入项目记忆） |
