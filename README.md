# archive-pgy-uploader

通用 **Xcode Archive → 蒲公英（Pgyer）自动上传引擎**。多项目共享同一份脚本，
各项目只持有自己的配置（密钥 + 是否上传 + 上传包信息）。

> 本仓库是「共享引擎」，自身**不含任何项目密钥与路径**。

---

## 架构：引擎共享 / 配置分离

```
中央仓库  archive-pgy-uploader/          ← 本仓库，多项目共享（git submodule 引用）
├── archive_upload.sh          # CLI 全自动入口：xcodebuild archive + 上传
├── pgy_upload.sh              # 底层引擎：导出 IPA、Bundle ID 校验、蒲公英上传、监控页
├── link-skill.sh              # 把 skill/SKILL.md 注册到 WorkBuddy 技能扫描目录
├── sync-hosts.sh              # 本机多宿主跟随同步器（.local 名单模式，仅本机用）
├── skill/SKILL.md             # 分发给 AI 工具的技能入口文档
├── examples/
│   ├── pgy_config.example.sh          # 项目配置模板
│   └── PGYUploadHistory.example.json  # 控制文件模板
├── changelog/ · experience/   # 变更流水（CR-NNN）/ 经验库（L-NNN）
├── STATUS.md · AGENTS.md      # 实现真相（唯一事实来源）/ 跨工具入口
├── .local/                    # 本机私有（gitignored）：宿主名单、钩子、备份
└── .gitignore

每个项目（如 xiyuScoreboard）：
├── ios/Scripts/archive-pgy-uploader/  → git submodule → 本仓库
├── ios/Scripts/archive-pgy-config/
│   ├── pgy_config.sh          # 真实密钥（gitignore，不入库）
│   └── PGYUploadHistory.json  # 控制文件：是否触发 + 上传包信息
└── Runner.xcodeproj/project.pbxproj   # Run Script
```

> **工程不变量**：密钥与控制文件位于**引擎目录之外**（上例的 `archive-pgy-config/`）。
> 引擎目录内只允许出现引擎自身的文件——把 `pgy_config.sh` 放进引擎目录会让所有宿主共用同一份
> `TARGET_BUNDLE_ID`，Bundle ID 校验（防误传）随即失效。

**Post-actions（Archive 成功后执行，推荐）**：

> ⚠️ `$ARCHIVE_PATH` 只在 **Scheme 的 Post-actions** 中由 Xcode 注入；
> 普通 Build Phase 的 Run Script 里该变量恒为空，会导致脚本落入「等待模式」轮询最近生成的归档（行为不确定）。
> 因此 Archive 触发的上传**必须放在 Post-actions**，而非 Build Phase Run Script。

在 Xcode 中 `Edit Scheme → Archive → Post-actions` 添加 Run Script：

```bash
bash "${SRCROOT}/Scripts/archive-pgy-uploader/pgy_upload.sh" \
  --config "${SRCROOT}/Scripts/archive-pgy-config/pgy_config.sh" \
  --archive "$ARCHIVE_PATH"
```

（备选：若只能放在 Build Phase Run Script，可省略 `--archive`，脚本会进入等待模式轮询最新 `.xcarchive`；仍强烈建议改用 Post-actions。）

引擎读取 `--config` 指定的项目配置 → 拿到密钥与 `PGY_HISTORY_FILE` → 再从控制文件
决定**跳过/上传**、**版本号 / 版本目标 / 更新说明**。

---

## 三种运行模式

| 模式 | 调用 | 说明 |
|---|---|---|
| 直接（推荐，Archive 后） | `--archive "$ARCHIVE_PATH"` | 同步执行导出+上传，监控页随进度刷新 |
| 等待（Build Phase 前置） | 不传 `--archive` | 后台轮询最新 `.xcarchive` 再处理 |
| 手动 / CI | `--archive xxx.ipa --version 1.2.3 --notes "..."` | 直接对已有包上传 |

---

## 控制文件 `PGYUploadHistory.json`

数组 `.[0]` 为「当前生效」条目（其余作手工人账本）：

```json
[
  { "version": "1.0.3.0", "versionTarget": "测试版本", "updateDes": "环境噪音监测功能" }
]
```

- `versionTarget` **为空** → 跳过本次上传（最核心的「是否上传」开关）
- `version` / `updateDes` → 仅在对应变量未被 CLI/config 赋值时作为默认值
- 优先级：`--version/--notes/--target` > `pgy_config.sh`/环境变量 > 控制文件 > `Info.plist` 自动探测

> ⚠️ **更新说明的来源取决于你走的入口（最容易踩坑）**：
> - **Xcode Post-actions 入口**（推荐、`Edit Scheme → Archive → Post-actions`）：脚本只收到 `--config --archive`，**不会**收到 `--notes`。因此更新说明恒取自 `PGYUploadHistory.json [0].updateDes`。想改说明 → 直接改这个 JSON 文件（或临时改 `[0].updateDes`）后重新 Archive。
> - **CLI / 手动入口**（`archive_upload.sh --notes "..."` 或 `pgy_upload.sh --archive xxx --notes "..."`）：才用 `--notes` 覆盖。
> 换句话说：`--notes` 只在 CLI/手动路径生效；走 Xcode Post-actions 时它根本没被传入，改 `--notes` 不会影响 Xcode 触发的上传。不要误以为改 `--notes` 能影响 Xcode 路径的更新说明。

> ⚠️ **双触发防护（CLI 自动化时避免重复上传）**：`archive_upload.sh` 会自己跑 `xcodebuild archive` 再调 `--_upload` worker 上传，但 `xcodebuild archive` **本身也会触发 Xcode Post-actions**（即本脚本的主进程模式），若不处理会双上传。
> 防护采用**进程树硬判定**：主进程启动后回溯祖先进程，若发现某个祖先的可执行文件 basename 为 `xcodebuild`，即判定本次归档由 CLI 驱动 → 主进程直接 `exit 0`，上传交由 `archive_upload.sh` 拉起的 `--_upload` worker 完成；GUI Archive 的祖先是 `Xcode.app`（无 `xcodebuild` 进程），则正常 fork worker 上传。该判定不依赖任何信号/环境变量继承（旧版 `PGY_SKIP_POSTACTION` 仅作兜底）。判定的健壮性要点：比对的是祖先**命令行首个 token 的 basename**，而非整行子串，避免命令行参数里恰好出现 `xcodebuild` 字样造成误判。

---

## 前置依赖

| 依赖 | 说明 |
|---|---|
| macOS + Xcode 命令行工具 | `xcodebuild`（`xcode-select --install`） |
| **`jq`** | **硬依赖**：`pgy_upload.sh` / `sync-hosts.sh` 在依赖检查处缺失即 `exit 1`。`brew install jq` |
| `python3` | 拼装 JSON 输出（`archive_upload.sh` / `link-skill.sh` / `sync-hosts.sh` 的部分路径） |
| `curl` / `base64` / `open` | 上传、二维码、监控页（macOS 自带） |

## 项目接入步骤

1. 在项目中添加 submodule：
   ```bash
   git submodule add <本仓库 remote> ios/Scripts/archive-pgy-uploader
   ```
2. 建项目配置目录 `ios/Scripts/archive-pgy-config/`：
   - `cp examples/pgy_config.example.sh pgy_config.sh` 并填入真实密钥
   - 放置 `PGYUploadHistory.json`（可参考 `examples/PGYUploadHistory.example.json`）
   - 项目 `.gitignore` 加入 `ios/Scripts/archive-pgy-config/pgy_config.sh`
3. 在 Xcode `Edit Scheme → Archive → Post-actions` 添加 Run Script，填入上方命令
   （`$ARCHIVE_PATH` 仅在 Post-actions 注入；普通 Build Phase Run Script 里恒空，会落入等待模式）。
   若用纯 Xcode 工程（非 CocoaPods / 非 Runner scheme），注意 `archive_upload.sh` 默认
   `--scheme Runner` / `--workspace Runner.xcworkspace`，需改用 `--scheme` / `--workspace` 覆盖。
4. `plutil -lint` 校验 pbxproj，Clean → Archive 实机验证一次。

---

## 配置项

| 变量 | 默认 | 说明 |
|---|---|---|
| `PGY_USER_KEY` / `PGY_API_KEY` | — | 蒲公英凭证（必填，来自 pgy_config.sh 或 env） |
| `PGY_HISTORY_FILE` | — | 控制文件路径（由 pgy_config.sh 设置） |
| `PGY_TEAM_ID` | `$DEVELOPMENT_TEAM` | 签名 team，可用此变量显式覆盖 |
| `PGY_METHOD` | `development` | development / ad-hoc / app-store |
| `PGY_MAX_WAIT` | `300` | 等待模式最长秒数 |
| `PGY_DEBUG_CHECK` | `auto` | auto / on / off（仅 Flutter 拦截 Debug） |
| `PGY_VERSION_TARGET` | — | 版本目标标签 |
| `PGY_UPDATE_DESCRIPTION` | — | 默认更新说明 |

---

## 实时状态页

自动打开一个本地 HTML 监控页（`<meta refresh>` 自刷新，成功/失败转静态结果页），
无需 HTTP 服务、无 CORS 问题。

---

## 多项目跟随同步（本机，`sync-hosts.sh`）

引擎被多个项目以 submodule 共享后，「引擎迭代」与「宿主更新 gitlink」是两步操作，缺少机制时会自然滞后
——本机实测曾同时存在三种状态：某项目落后 4 个 commit、某项目的 gitlink 只 add 未 commit、某项目干脆退化成文件复制。

`sync-hosts.sh` 用一个**本机私有名单**把这件事压成一条命令：

```bash
# 1) 登记需要跟随的项目（每个项目一次）
bash sync-hosts.sh --add xiyuScoreboard /path/to/xiyuScoreboard ios/Scripts/archive-pgy-uploader

# 2) 随时体检：谁落后了、落后多少
bash sync-hosts.sh                 # 加 --json 可输出单行 JSON 供 AI/CI 解析

# 3) 一键同步：更新各宿主 gitlink 并本地 commit（不 push）
bash sync-hosts.sh --apply

# 可选：引擎仓每次提交后自动跟随
bash sync-hosts.sh --install-hook --auto     # 默认仅提示；--auto 才真正自动同步
```

- 名单落在 `.local/hosts.json`（**gitignored，本机私有**）；退出码：`0`=一致或成功、`2`=有落后/需人工介入、`1`=出错。
- 目标版本默认取**本机引擎仓 HEAD**（引擎刚提交、还没 push 也能跟随）；加 `--from-origin` 改为跟 origin 默认分支。
- 只处理「落后且工作区干净」的项目；`--dry-run` 可先看动作，`--allow-dirty` 才越过工作区检查。
- 完整状态取值与参数见 `STATUS.md` §3.3。

---

## AI / WorkBuddy 技能（扩展功能）

本仓库附带一份 WorkBuddy 技能文档 `skill/SKILL.md`，描述如何用一条命令
（`archive_upload.sh`）全自动 Archive 并上传蒲公英，**无需手动点 Xcode**，
供 AI 工具准确触发。该技能随子模块分发，**支持多项目复用**。

### 注册到 WorkBuddy
WorkBuddy 只扫描项目级 `.workbuddy/skills/` 与用户级 `~/.workbuddy/skills/`，
不会主动扫描子模块内部，因此其他项目引入本子模块后需注册一次：

```bash
# 在项目根目录运行：默认注册到项目级 .workbuddy/skills/archive-pgy-uploader/
bash <子模块目录>/link-skill.sh

# 或注册到用户级（本机所有项目直接可用）
bash <子模块目录>/link-skill.sh -g
```

`link-skill.sh` 会把子模块内 `skill/SKILL.md` 以**相对路径软链**注册到 WorkBuddy
技能扫描目录；子模块更新后重新运行 `link-skill.sh` 即可同步最新技能。
加 `-f` 可在目标已存在时强制覆盖。

### 技能触发
注册后，AI 工具在收到「Archive 上传蒲公英」「构建并上传」等请求时，会调用：

```bash
bash <子模块目录>/archive_upload.sh --target "测试版本"
```

脚本输出单行 JSON（含 `downloadUrl` / `status` / `error`），退出码 `0`=成功或跳过、
`1`=失败，详见 `skill/SKILL.md`。
