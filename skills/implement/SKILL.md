---
name: implement
description: TDD 實作流程。test-writer agent 先撰寫失敗測試，人工確認後 implementer agent 寫實作，直到所有測試通過。test-writer 與 implementer 分開執行，測試檔案不可被 implementer 修改。
tools: ["Read", "Write", "Bash", "AskUserQuestion"]
---

# Implement — TDD 實作

以 TDD 方式進行功能實作。**test-writer 與 implementer 是分開的 agent**，職責嚴格隔離。

## 使用方式

```
/implement
```

執行前，`tmp/<ticket-id>/plan.md` 必須已存在。

---

## 步驟 0：讀取 ticket-id 與專案設定

```bash
TICKET_ID=$(cat tmp/.current-ticket)
```

固定設定值：

| 設定 | 值 |
|------|---|
| `commands.test` | `go test ./...` |
| `paths.test` | `**/*_test.go` |
| `paths.impl` | `**/*.go`（排除 `*_test.go`）|
| `min_coverage` | 80% |
| `max_impl_retry` | 3 |

---

## 步驟 1：前置確認

平行讀取：
- `tmp/${TICKET_ID}/plan.md` — 必須存在，若不存在則停止，提示先執行 `/plan-writer`。
- `tmp/${TICKET_ID}/schema.md` — 若存在則傳給 test-writer；若不存在，test-writer 進入降級模式。

---

## 步驟 2：測試撰寫（test-writer agent）

記錄測試基準點：

```bash
git rev-parse HEAD > "tmp/${TICKET_ID}/.test-baseline"
```

以 **test-writer** agent 執行，傳入：
- `tmp/${TICKET_ID}/plan.md`
- `tmp/${TICKET_ID}/schema.md`（若存在）
- ticket-id
- 步驟 0 推斷的 `paths.test`、`commands.test`

test-writer 完成後執行以下驗證：

```bash
# 1. 確認 test-report.md 已產生
[ -f "tmp/${TICKET_ID}/test-report.md" ] || { echo "ERROR: test-report.md 未產生"; exit 1; }

# 2. 確認有實際的測試檔案被寫入（相較基準點有新增或修改）
TEST_BASELINE=$(cat "tmp/${TICKET_ID}/.test-baseline")
CHANGED_TEST_FILES=$(git diff --name-only "${TEST_BASELINE}" -- <paths.test glob>)
if [ -z "${CHANGED_TEST_FILES}" ]; then
  echo "ERROR: test-writer 未產生任何測試檔案。請重新執行 test-writer agent。"
  exit 1
fi
echo "測試檔案已產生：${CHANGED_TEST_FILES}"
```

若驗證失敗，重新執行 test-writer agent，要求明確建立測試檔案。

**【人工關卡】** — 顯示：

```
══════════════════════════════════
人工關卡：測試確認
══════════════════════════════════
測試撰寫完成，請審閱：

tmp/<ticket-id>/test-report.md

確認以下事項：
- 測試案例是否涵蓋 plan.md 中所有需求
- 邊界條件是否齊全（nil、空值、數值邊界）
- 測試失敗原因是否正確（功能未實作，非語法錯誤）

回覆「確認」繼續，或說明需要調整的測試。
══════════════════════════════════
```

使用 `AskUserQuestion` 等待確認。若使用者要求調整，重新執行 test-writer agent。

---

## 步驟 3：實作（implementer agent）

以 **implementer** agent 執行，傳入：
- `tmp/${TICKET_ID}/plan.md`
- `tmp/${TICKET_ID}/schema.md`（若存在）
- ticket-id
- 步驟 0 推斷的 `paths.test`、`paths.impl`、`commands.test`

---

## 步驟 4：測試檔不可變驗證

implementer 完成後執行：

```bash
TEST_BASELINE=$(cat "tmp/${TICKET_ID}/.test-baseline")
# paths.test 為步驟 0 推斷的測試路徑 glob
git diff --name-only "${TEST_BASELINE}" -- <paths.test glob>
```

若 `.test-baseline` 不存在或為空，停止並回報：「測試基準點遺失，請從步驟 2 重新執行。」

若輸出非空（測試檔被修改）：
- 顯示錯誤：「測試檔案已被修改，請人工確認後從步驟 2 重新執行。」
- 停止，不可自動繼續。

---

## 步驟 5：覆蓋率驗證

```bash
go test -coverprofile="tmp/${TICKET_ID}/.coverage.out" ./...
go tool cover -func="tmp/${TICKET_ID}/.coverage.out" | grep "^total:" | awk '{print $3}'
```

**計數器**：`impl_retry_count`（初始為 0）

若覆蓋率 < `min_coverage`：
- `impl_retry_count += 1`
- 若 `impl_retry_count >= max_impl_retry`：停止，提示人工介入。
- 否則顯示：「測試覆蓋率不足（目前 X%，要求 ≥ N%），請補充測試後重新實作。」，回到步驟 2 人工關卡。

若測試失敗（非覆蓋率問題）：
- `impl_retry_count += 1`
- 若 `impl_retry_count >= max_impl_retry`：停止，提示人工介入。
- 否則回到 implementer agent 重新實作。

---

## 步驟 6：完成

實作通過後輸出：

```
══════════════════════════════════
✅ 實作完成
══════════════════════════════════
所有測試通過，覆蓋率：<X%>

建議後續步驟：
  /code-review      程式碼審查
  /security-scan    安全掃描

交接檔：tmp/<ticket-id>/
══════════════════════════════════
```

---

## 規則

- plan.md 必須存在才可執行。
- 人工關卡不可跳過。
- 測試檔被修改時必須停止，不可繼續。
- 覆蓋率與測試失敗的 retry 上限各自獨立計算。
