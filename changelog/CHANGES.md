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
