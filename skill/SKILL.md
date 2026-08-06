---
name: archive-pgy-uploader
description: >-
  Archive（xcodebuild）并上传蒲公英（Pgyer）分发。当用户要求「构建并上传」「Archive 上传蒲公英」
  「打包 iOS 分发」「xcodebuild archive 后上传」或任何触发 iOS 构建+蒲公英分发的请求时调用。
  全自动、零 GUI 依赖，输出结构化 JSON 供程序解析。
  本技能是 archive-pgy-uploader 子模块的扩展功能，随子模块分发，支持多项目复用。
---

# Archive → 蒲公英上传（archive-pgy-uploader）

## 用途
将 iOS 项目自动 Archive（生成 .xcarchive）+ 导出 IPA + 上传蒲公英，供测试��员扫码下载。
供 AI 工具用一条命令准确触发，**无需手动点 Xcode**。

> 本技能是 `archive-pgy-uploader` 子模块的扩展功能，作为子模块的一部分分发。
> 其他项目引入该子模块后，运行 `link-skill.sh` 即可在本项目注册此技能（详见文末「跨项目复用」）。

## 前置条件
- macOS + Xcode 命令行工具（`xcodebuild` 可用）
- 有效签名：development 证书 + 自动签名，或对应 provisioning profile
- 已引入 `archive-pgy-uploader` 子模块，且项目配置目录已提供 `pgy_config.sh`
  （含 `PGY_USER_KEY` / `PGY_API_KEY`，gitignored，本地维护）

## 调用方式
统一入口脚本 `archive_upload.sh`（已做参数透传与结构化输出），位于子模块目录内：

```bash
bash <子模块目录>/archive_upload.sh [参数]
```

`<子模块目录>` 即 `archive-pgy-uploader` 子模块根，项目内常见路径如
`ios/Scripts/archive-pgy-uploader/archive_upload.sh`（按实际子模块位置调整）。

> 工程结构假设：脚本默认 `--scheme Runner`、workspace 为 `Runner.xcworkspace`（CocoaPods 工程）。
> 若你的工程 scheme 不叫 `Runner`、或纯 `.xcodeproj`（无 CocoaPods），请通过
> `--scheme <你的scheme>` / `--workspace <你的.xcworkspace 或 .xcodeproj>` 覆盖；
> 当 `Runner.xcworkspace` 不存在时，脚本会自动回退到 `Runner.xcodeproj`。

### 自动模式（推荐，全自动）
不传 `--archive` 时脚本自动执行 `xcodebuild archive` 生成 .xcarchive，再导出上传：
```bash
bash <子模块目录>/archive_upload.sh --target "测试版本"
```

### 复用已有归档
已生成 .xcarchive 时直接传入（跳过 xcodebuild archive）：
```bash
bash <子模块目录>/archive_upload.sh --archive /path/to/Runner.xcarchive --target "测试版本"
```

## 参数
| 参数 | 说明 | 默认 |
|------|------|------|
| `--target` | 版本目标标签（如「测试版本」「正式版本」）。**非空才会实际上传**（空则按设计跳过） | 无 |
| `--version` | 显式版本号，覆盖 Info.plist 探测 | 自动探测 |
| `--notes` | 更新说明（蒲公英「更新说明」字段） | 无 |
| `--method` | 签名方法：`development` / `ad-hoc` / `app-store` | `development` |
| `--bundle-id` | 目标 Bundle ID（身份校验，防止误传其他项目包） | config 中的 `TARGET_BUNDLE_ID` |
| `--archive` | 传入已有 .xcarchive，跳过 xcodebuild archive | 无 |
| `--config` | 蒲公英凭证配置文件路径（项目级，含密钥，gitignored） | 项目配置目录下的 `pgy_config.sh` |
| `--dry-run` | 只打印将执行的 xcodebuild 命令，不真正构建 | 关 |
| `--workspace` | 指定 .xcworkspace 路径（多 target / pod 项目时可能需要） | `<项目>/ios/Runner.xcworkspace` |
| `--scheme` | 指定 Xcode scheme | `Runner` |
| `--configuration` | 指定构建配置 | `Release` |
| `-h`, `--help` | 打印脚本头部用法说明并退出 | 关 |

> 也可直接运行 `bash <子模块目录>/archive_upload.sh --help` 查看内嵌用法。

## 输出（stdout，供 AI 解析）
脚本把底层 `pgy_upload.sh` 的结构化 JSON 原样输出到 **stdout**（中间日志走 stderr）：

```json
{"status":"success","version":"1.0.3.2","versionTarget":"测试版本",
 "updateDescription":"1.0.3.2 测试版本\n本次更新说明",
 "downloadUrl":"https://www.pgyer.com/xxxx","archivePath":"...",
 "ipaPath":"...","logPath":"...","monitorPath":"...","error":null}
```

字段：`status`(success|error|skipped)、`version`、`versionTarget`、`updateDescription`、
`downloadUrl`、`archivePath`、`ipaPath`、`logPath`、`monitorPath`、`error`。

- `status=success`：上传成功，取 `downloadUrl` 给用户
- `status=error`：失败，看 `error` 字段（常见：Bundle ID 不匹配 / 签名失败 / 网络问题）
- `status=skipped`：按设计跳过（如 `--target` 为空），不会上传

## 退出码
- `0`：成功(success) 或 按设计跳过(skipped)
- `1`：任意失败(error)

## 安全机制（已内置，勿绕过）
- **Bundle ID 校验**：上传前比对归档 Bundle ID 与 `--bundle-id`，不匹配立即拦截，
  防止误传其他项目的安装包（历史上曾因环境配置污染误传非本项目的包）。
- **历史控制**：`PGYUploadHistory.json` 的 `[0].versionTarget` 为空时默认跳过，
  但命令行 `--target` 可覆盖以强制上传。

## 更多调用示例

```bash
# 1) 最简：自动 archive + 上传，版本目标「测试版本」（AI 触发最常用）
bash <子模块目录>/archive_upload.sh --target "测试版本"

# 2) 指定更新说明（蒲公英「更新说明」字段会显示此内容）
bash <子模块目录>/archive_upload.sh \
  --target "测试版本" --notes "环境噪音监测功能 + Bug 修复"

# 3) 复用已生成的归档（跳过 xcodebuild archive，加快重传）
bash <子模块目录>/archive_upload.sh \
  --archive /Users/me/Library/Developer/Xcode/Archives/2026-07-31/Runner.xcarchive \
  --target "测试版本"

# 4) 自定义 scheme / workspace（多 target 项目时）
bash <子模块目录>/archive_upload.sh \
  --scheme Runner --workspace ios/Runner.xcworkspace --target "正式版本"

# 5) 仅预览将执行的 xcodebuild 命令，不真正构建
bash <子模块目录>/archive_upload.sh --target "测试版本" --dry-run

# 6) CI 中捕获 JSON 结果（退出码 0=成功/跳过，1=失败）
RESULT=$(bash <子模块目录>/archive_upload.sh --target "测试版本")
if [ $? -eq 0 ]; then
  URL=$(echo "$RESULT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('downloadUrl',''))")
  echo "上传成功，下载链接: $URL"
fi
```

## 典型对话触发
用户：「帮我把当前代码 Archive 并传到蒲公英，版本目标写测试版本」
→ 执行 `bash <子模块目录>/archive_upload.sh --target "测试版本"`
→ 解析 stdout JSON，成功则回覆下载链接，失败则回覆 `error` 内容。

## 跨项目复用（本技能随子模块分发）
本 SKILL 是 `archive-pgy-uploader` 子模块的一部分（位于子模块内 `skill/SKILL.md`）。
WorkBuddy 仅扫描项目级 `.workbuddy/skills/` 与用户级 `~/.workbuddy/skills/`，不会主动扫描子模块内部，
因此其他项目引入子模块后需注册一次：

```bash
# 在项目根目录运行（默认注册到项目级 .workbuddy/skills/archive-pgy-uploader/）
bash <子模块目录>/link-skill.sh

# 或注册到用户级（本机所有项目直接可用）
bash <子模块目录>/link-skill.sh -g
```

注册本质是把子模块内 `skill/SKILL.md` 软链到 WorkBuddy 的技能扫描目录；
子模块更新后重新运行 `link-skill.sh` 即可同步最新技能。
