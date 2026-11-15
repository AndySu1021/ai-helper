---
name: bugfix
description: Bug 修復流程。跳過 brainstorm/plan-writer/api-schema，直接進入 TDD 實作。適用於：已知原因的 bug（生產環境緊急修復、QA 驗收後開出的 bug ticket）、不涉及 API 設計變動的修復。需要釐清需求或設計新端點，請改用 /plan-writer + /implement。
tools: ["Read", "Write", "Bash", "AskUserQuestion"]
---

# Bugfix — Bug 修復流程

跳過需求討論與計畫階段，直接進入測試撰寫與實作，適用於**已知問題、已知修法**的情境。

## 適用情境

**適合使用 `/bugfix`**：
- 生產環境緊急 bug，需要快速修復
- QA 驗收後開出的 bug ticket，原因已明確，修法清楚
- 一般 bug，不需要 schema 變動
- 測試補足、已知邊界條件遺漏的修復

**應改用 `/plan-writer` + `/implement`**：
- 需要與使用者討論需求範圍
- 需要設計或修改 API schema
- 修復方式不確定，需要方案比較

## 使用方式

```
/bugfix <問題描述或 ticket 號碼>
```

---

## 前置作業：確定 Ticket ID 與工作目錄

從 `$ARGUMENTS` 解析 ticket-id：
- 若包含 ticket 格式（如 `PROJ-1234`），取該值
- 否則，使用 `AskUserQuestion` 詢問識別碼

建立工作目錄：

```bash
TICKET_ID="<ticket-id>"
mkdir -p "tmp/${TICKET_ID}"
printf '%s' "${TICKET_ID}" > tmp/.current-ticket
```

---

## 前置作業：推斷專案設定

```bash
[ -f go.mod ]           && LANG=go
[ -f package.json ]     && LANG=node
[ -f requirements.txt ] && LANG=python
[ -f Cargo.toml ]       && LANG=rust
```

| 語言 | `commands.test` 預設 | `paths.test` 預設 | `paths.impl` 預設 |
|------|---------------------|-------------------|-------------------|
| go | `go test ./...` | `**/*_test.go` | `**/*.go`（排除 `*_test.go`）|
| node | `npm test` | `**/*.test.ts`, `**/*.spec.ts`, `**/*.test.js` | `src/**` |
| python | `pytest` | `tests/**`, `**/*_test.py` | 排除 tests 以外 |
| rust | `cargo test` | `**/tests/**`, `src/**`（含 `#[cfg(test)]`）| `src/**` |

若語言無法推斷，使用 `AskUserQuestion` 詢問：「無法自動偵測專案語言，請告知：1) 語言 2) 測試指令 3) 測試檔路徑規則。」

固定預設值：`max_impl_retry: 3`、`min_coverage: 80%`

---

## 步驟 1：釐清問題

使用 `AskUserQuestion` 確認：

> 請描述：
> 1. 問題是什麼？（觀察到的錯誤行為）
> 2. 預期正確行為是什麼？
> 3. 修復方式是否已確定？（若不確定，建議改用 `/plan-writer`）
> 4. 是否涉及 API 或 schema 變動？（若有，建議改用 `/plan-writer`）

---

## 步驟 2：產生簡化計畫

根據使用者的回答，直接寫入 `tmp/${TICKET_ID}/plan.md`：

```
---
stage: plan
created: <YYYY-MM-DD>
source: <ticket 連結或描述>
bugfix: true
---

# 修復計畫：<簡短描述>

## 問題描述

<觀察到的錯誤行為>

## 預期行為

<正確行為>

## 修復方式

<已確認的修復做法>

## 影響範圍

<預計修改的檔案或模組>

## 測試策略

- 撰寫重現 bug 的失敗測試
- 修復後確認測試通過
- 確認未破壞既有測試
```

---

## 步驟 3：測試撰寫（test-writer agent）

記錄測試基準點：

```bash
git rev-parse HEAD > "tmp/${TICKET_ID}/.test-baseline"
```

以 **test-writer** agent 執行，傳入：
- `tmp/${TICKET_ID}/plan.md`
- ticket-id
- 前置作業推斷的 `paths.test`、`commands.test`

test-writer 會自動偵測 `schema.md` 不存在並進入降級模式，僅依 `plan.md` 規劃測試案例。

test-writer 完成後確認 `tmp/${TICKET_ID}/test-report.md` 已產生。

**【人工關卡】** — 顯示：

```
══════════════════════════════════
人工關卡：測試確認
══════════════════════════════════
測試撰寫完成，請審閱：

tmp/<ticket-id>/test-report.md

確認以下事項：
- 測試是否重現了 bug（預期為失敗）
- 邊界條件是否涵蓋

回覆「確認」繼續，或說明需要調整的測試。
══════════════════════════════════
```

使用 `AskUserQuestion` 等待確認。若使用者要求調整，重新執行 test-writer agent。

---

## 步驟 4：實作（implementer agent）

以 **implementer** agent 執行，傳入：
- `tmp/${TICKET_ID}/plan.md`
- ticket-id
- 前置作業推斷的 `paths.test`、`paths.impl`、`commands.test`

---

## 步驟 5：測試檔不可變驗證

implementer 完成後執行：

```bash
TEST_BASELINE=$(cat "tmp/${TICKET_ID}/.test-baseline")
git diff --name-only "${TEST_BASELINE}" -- <paths.test glob>
```

若 `.test-baseline` 不存在或為空，停止並回報：「測試基準點遺失，請從步驟 3 重新執行。」

若輸出非空（測試檔被修改）：
- 顯示錯誤：「測試檔案已被修改，請人工確認後從步驟 3 重新執行。」
- 停止，不可自動繼續。

---

## 步驟 6：覆蓋率驗證

```bash
# Go
go test -coverprofile="tmp/${TICKET_ID}/.coverage.out" ./...
go tool cover -func="tmp/${TICKET_ID}/.coverage.out" | grep "^total:" | awk '{print $3}'

# TypeScript/JavaScript（jest）
jest --coverage --coverageReporters=text-summary 2>&1 | grep "All files"

# Python
pytest --cov --cov-report=term-missing 2>&1 | grep "^TOTAL"
```

若工具不支援覆蓋率，顯示警告「無法取得覆蓋率數據」並繼續（不阻擋流程）。

**計數器**：`impl_retry_count`（初始為 0）

若覆蓋率 < `min_coverage`：
- `impl_retry_count += 1`
- 若 `impl_retry_count >= max_impl_retry`：停止，提示人工介入。
- 否則顯示：「測試覆蓋率不足（目前 X%，要求 ≥ 80%），請補充測試後重新實作。」，回到步驟 3 人工關卡。

若測試失敗（非覆蓋率問題）：
- `impl_retry_count += 1`
- 若 `impl_retry_count >= max_impl_retry`：停止，提示人工介入。
- 否則回到 implementer agent 重新實作。

---

## 步驟 7：完成

實作通過後輸出：

```
══════════════════════════════════
✅ 修復完成
══════════════════════════════════
所有測試通過，覆蓋率：<X%>

建議後續步驟：
  /code-review      程式碼審查（確認符合需求與 coding style）
  /security-scan    安全掃描

交接檔：tmp/<ticket-id>/
══════════════════════════════════
```

---

## 規則

- 若使用者確認問題涉及 schema 變動，停止並建議改用 `/plan-writer` + `/implement`。
- 人工關卡不可跳過。
- `.test-baseline` 驗證不可跳過。
- 覆蓋率與測試失敗的 retry 上限共用同一計數器。

## 錯誤處理

| 情況 | 處理方式 |
|------|---------|
| 問題涉及 schema 變動 | 建議改用 /plan-writer，停止 |
| .test-baseline 遺失 | 停止，要求從步驟 3 重新執行 |
| impl_retry_count >= max_impl_retry | 停止，提示人工介入 |
