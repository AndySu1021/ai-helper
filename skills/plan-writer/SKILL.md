---
name: plan-writer
description: 依需求摘要撰寫結構化實作計畫，輸出至 tmp/<ticket-id>/plan.md。計畫必須包含目標、範圍、影響檔案、API 變更、測試策略與風險。
tools: ["Read", "Write", "Bash", "AskUserQuestion"]
---

# Plan Writer — 實作計畫撰寫

依需求摘要與 brainstorm 討論結果，撰寫可供後續階段使用的結構化實作計畫。

## 使用方式

```
/plan-writer <ticket-id>
```

---

## 步驟 0：讀取 ticket-id

```bash
TICKET_ID="${ARGUMENTS:-}"
if [ -z "${TICKET_ID}" ]; then
  # AskUserQuestion: 請提供 ticket ID（例如 PROJ-123）
fi
mkdir -p "tmp/${TICKET_ID}"
```

---

## 步驟 1：前置確認

確認 `tmp/${TICKET_ID}/requirements.md` 存在，否則立即停止：

```
❌ Plan Writer 無法啟動

tmp/<ticket-id>/requirements.md 不存在。
請執行 /brainstorm 或手動建立 requirements.md 後再試。
```

讀取 requirements.md 的 `complexity` 欄位：

```bash
COMPLEXITY=$(grep '^complexity:' "tmp/${TICKET_ID}/requirements.md" | awk '{print $2}' || echo "medium")
```

---

## 步驟 2：執行 plan-writer agent

**`complexity: low`** → 以 **plan-writer** agent 執行一次（`perspective: default`），輸出至 `tmp/${TICKET_ID}/plan.md`，直接進入步驟 3。

**`complexity: medium` 或 `high`** → 並行以 **plan-writer** agent 執行三次，附加不同視角：

- **Agent 1**：`perspective: default`，輸出 `tmp/${TICKET_ID}/plan-draft-1.md`
- **Agent 2**：`perspective: critical`，輸出 `tmp/${TICKET_ID}/plan-draft-2.md`
- **Agent 3**：`perspective: minimal`，輸出 `tmp/${TICKET_ID}/plan-draft-3.md`

三份 draft 完成後整合：
1. 以 `plan-draft-1.md` 為基礎
2. 將 `plan-draft-2.md` 中的遺漏/潛在問題納入風險表或影響範圍
3. 將 `plan-draft-3.md` 中標為「可 defer」的項目移入「排除」區段並備注原因
4. 生成 `tmp/${TICKET_ID}/plan.md`，frontmatter 加入：`reviewed_by: plan-draft-1, plan-draft-2, plan-draft-3`

---

## 步驟 3：完成

輸出：

```
══════════════════════════════════
✅ 計畫撰寫完成
══════════════════════════════════
tmp/<ticket-id>/plan.md 已產生。

建議後續步驟：
  /api-schema <ticket-id>    設計 API schema（若有 API 變更）
  /implement  <ticket-id>    TDD 實作
══════════════════════════════════
```

---

## 規則

- requirements.md 必須存在才可執行。
- 計畫必須根據實際程式碼探索結果撰寫，不可憑空假設影響範圍。
