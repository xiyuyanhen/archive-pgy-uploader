# AGENTS.md — archive-pgy-uploader 协作入口

> 本文件是 `archive-pgy-uploader` 的**跨工具入口**（WorkBuddy / Kiro / Codex / Cursor 等均读此文件）。
> 篇幅刻意保持精简——**细节一律以 `STATUS.md` 为准**，避免两处维护、互相漂移。

## 项目一句话

通用 Xcode Archive → 蒲公英(Pgyer) 自动上传引擎（多项目以 submodule 共享，配置与密钥按项目分离）

## 动手之前：按顺序读

| # | 文件 | 目的 |
| --- | --- | --- |
| 0 | [`STATUS.md`](./STATUS.md) | 项目现状唯一事实来源：能力、入口、契约、约束、已知问题（`OPEN-NNN`） |
| 1 | [`experience/LESSONS.md`](./experience/LESSONS.md) | 已验证的可复用经验（`L-NNN`）；把 `verified` 条目当默认策略 |
| 2 | [`changelog/CHANGELOG.md`](./changelog/CHANGELOG.md) | 当前版本与最近变更概览 |

## 交接速览（新会话 / 新工具 start here）

| 想了解 | 看哪里 |
| --- | --- |
| 现在做到哪了、能做什么 | `STATUS.md` §1 状态概览 + §2 目标与范围 |
| 怎么跑起来 | `STATUS.md` §3 入口与调用方式 |
| 输入输出长什么样 | `STATUS.md` §4 契约 |
| 有什么坑 / 哪些还没做 | `STATUS.md` §7 已知问题 |
| 最近改了什么、为什么 | `changelog/CHANGES.md` |
| 踩过什么坑、怎么解 | `experience/LESSONS.md` |

## 变更控制协议（强制）

| 步骤 | 动作 |
| --- | --- |
| ① READ | 读 `STATUS.md` + `experience/LESSONS.md`，确认现有实现与已知问题 |
| ② ASSESS | 判定变更类型：功能变更 / 规范性变更 / 校准修正 |
| ③ CALIBRATE | 若 `STATUS.md` 与实现不一致 → **先校准**并在 §9 留痕，再继续 |
| ④ IMPLEMENT | 功能变更先验证通过，再并入主干 |
| ⑤ UPDATE | 同步 `STATUS.md`（frontmatter + 受影响章节）**并**在 `changelog/CHANGES.md` 顶部追加 `CR-NNN` 条目（含：变更时间、原因、前后差异、影响范围、兼容性说明、验证方式） |
| ⑥ VERSION | 影响运行行为 → 升版本 + 新建 `changelog/vX.Y.Z.md` + 更新 `changelog/CHANGELOG.md` 索引 |

完整协议、条目模板、版本规则与完成检查清单见 **`STATUS.md` §8**。

## 硬性约束（勿违反）

- **凭证安全**：所有 token / secret 只从环境变量 / gitignored 的 `pgy_config.sh` 读取；禁止硬编码、禁止入库、禁止出现在日志/报错正文。
- **本仓库是共享引擎**：不得写入任何项目密钥、项目绝对路径或真实 Bundle ID（示例一律用占位符）。
- **不过度承诺**：`STATUS.md` §2.2 列出的「不做」事项，不要擅自扩展为「能做」。
- **不猜测**：契约不明确时先探测/验证并记 CR，不要靠猜写实现。
- **改宿主 Xcode 接线前先读 §7**：Post-actions 路由的坑（scheme 不热加载 → 不上传且无日志）见 `OPEN-001`，`--notes` 只在 CLI 入口生效见 `OPEN-002`。

## 目录导航

**治理文档**

| 路径 | 说明 |
| --- | --- |
| `STATUS.md` | 实现真相 + 交接主文档 |
| `AGENTS.md` | 本文件（跨工具入口） |
| `changelog/CHANGES.md` | 变更流水 `CR-NNN`（追加式） |
| `changelog/CHANGELOG.md` | 版本索引 |
| `changelog/vX.Y.Z.md` | 版本档案 |
| `experience/INDEX.md` | 经验库使用说明与条目状态定义 |
| `experience/LESSONS.md` | 结构化经验 `L-NNN` |
| `experience/execution-log.json` | 机器可读执行日志（`run_id`） |

**引擎实现**（细节见 `STATUS.md` §2 / §3 / §4）

| 路径 | 说明 |
| --- | --- |
| `archive_upload.sh` | 全自动 Archive + 上传的 CLI 入口（AI / CI 主入口） |
| `pgy_upload.sh` | 底层引擎：导出 IPA、Bundle ID 校验、蒲公英上传、监控页、JSON 输出 |
| `link-skill.sh` | 把 `skill/SKILL.md` 软链注册到 WorkBuddy 技能扫描目录 |
| `skill/SKILL.md` | 分发给 AI 工具的技能入口文档（**功能入口**，与 `AGENTS.md` 治理入口职责不同，勿互相覆盖） |
| `examples/` | `pgy_config.example.sh` / `PGYUploadHistory.example.json` 模板 |
| `README.md` | 面向使用者的接入说明（非事实来源，冲突时以 `STATUS.md` 为准） |
