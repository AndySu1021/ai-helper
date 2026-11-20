---
name: bugfix
description: Bug 修復流程。跳過 brainstorm/plan-writer/api-schema，直接進入 TDD 實作。適用於：已知原因的 bug（生產環境緊急修復、QA 驗收後開出的 bug ticket）、不涉及 API 設計變動的修復。需要釐清需求或設計新端點，請改用 /plan-writer + /implement。
tools: ["Read", "Write", "Bash", "AskUserQuestion", "EnterWorktree", "ExitWorktree"]
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

若 `$ARGUMENTS` 包含 ticket 格式（如 `PROJ-1234`），先讀取 ticket 內容：
- 讀取 ticket 本身的描述、重現步驟、預期行為
- **若有母票（parent ticket / epic），一併讀取母票描述與驗收條件**
- **若 ticket 有評論（comments），一併讀取所有評論**（開發者補充、QA 備注、PM 說明等，均視為需求的一部分）

整合以上資訊後，使用 `AskUserQuestion` 確認不清楚之處：

> 請描述：
> 1. 問題是什麼？（觀察到的錯誤行為）
> 2. 預期正確行為是什麼？
> 3. 修復方式是否已確定？（若不確定，建議改用 `/plan-writer`）
> 4. 是否涉及 API 或 schema 變動？（若有，建議改用 `/plan-writer`）

若 ticket 資訊已足夠回答以上問題，可省略 `AskUserQuestion`，直接進入步驟 2。

**【判斷是否為真正的 bug】**

釐清完成後，判斷問題性質：
- 若屬於**使用者操作問題**（非程式缺陷，只是不知道如何使用功能），輸出說明並停止，不進行修復：

  ```
  ══════════════════════════════════
  ℹ️ 非 bug，無需修復
  ══════════════════════════════════
  根據描述，這是使用方式的問題，而非程式缺陷。
  
  建議操作：<正確使用方式說明>
  ══════════════════════════════════
  ```

- 若屬於**外部依賴問題**（我方提供 API，資料缺失或未更新的原因是第三方未呼叫、呼叫頻率異常，或呼叫失敗），此問題超出我方程式碼範疇，無法透過修復程式碼解決，立即停止並要求人工確認：

  ```
  ══════════════════════════════════
  ⚠️ 無法排查：疑似外部依賴問題
  ══════════════════════════════════
  根據描述，資料缺失或未更新的可能原因是：
  第三方未呼叫我方 API、呼叫頻率異常，或呼叫請求失敗。
  
  這不是我方程式碼的問題，請先向第三方確認：
  1. 對方是否有如期呼叫 API？
  2. 呼叫的 request / response 是否正常？
  3. 對方的錯誤日誌是否有相關記錄？
  
  確認後若確實為我方程式碼問題，請再次執行 /bugfix。
  ══════════════════════════════════
  ```

- 若確認為程式 bug，繼續步驟 2。

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

## 步驟 2.5：確定分支名稱並建立 Worktree

從 ticket 取得以下資訊：
- **Fix version**：ticket 的 Fix Version / Target Version 欄位（如 `v1.2.3`、`2024.Q4`）
- **Ticket 號碼**：如 `PROJ-1234`
- **Short description**：從 ticket 標題取 3–5 個英文單字，以底線連接，全部小寫（如 `null_pointer_on_login`）

分支命名規則：

```
<fix_version>/bug/<ticket_no>_<short_description>
```

範例：`v1.2.3/bug/PROJ-1234_null_pointer_on_login`

若 Fix version 欄位不存在，使用 `AskUserQuestion` 詢問：「Ticket 無 Fix Version，請提供目標版本（例如 v1.2.3）。」

分支名稱確認後，使用 `EnterWorktree` 建立並切換至獨立 worktree，以隔離本次修復的所有變更：

```
EnterWorktree(branch: "<branch_name>")
```

後續所有步驟（測試撰寫、實作、驗證、推送）均在此 worktree 中進行。

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

**【自動驗證】** — test-writer agent 完成後，立即執行測試指令：

```bash
<commands.test>
```

驗收標準：
- 新增的測試**必須失敗**（確認重現了 bug）
- 既有測試**不可新增失敗**

若新增測試未如預期失敗，或既有測試被破壞：
- 重新執行 test-writer agent，要求修正
- 無上限重試，直到驗收標準通過為止
- 每次重試須在 `tmp/${TICKET_ID}/test-report.md` 更新原因與修正方向

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

## 步驟 7：建立 MR

此步驟為**強制執行**，不可略過或以推送分支代替。

呼叫 `/gitlab-mr` skill 建立 MR：

```
/gitlab-mr
```

MR 建立成功後，使用 `ExitWorktree` 離開 worktree：

```
ExitWorktree()
```

最後輸出完成摘要：

```
══════════════════════════════════
✅ 修復完成
══════════════════════════════════
所有測試通過，覆蓋率：<X%>
分支：<branch_name>
PR/MR：<連結>

建議後續步驟：
  /code-review      程式碼審查（確認符合需求與 coding style）
  /security-scan    安全掃描

交接檔：tmp/<ticket-id>/
══════════════════════════════════
```

---

## 規則

- 若使用者確認問題涉及 schema 變動，停止並建議改用 `/plan-writer` + `/implement`。
- 若釐清後判斷為操作問題而非 bug，輸出說明並停止，不進行任何修復或分支建立。
- 修復前必須先建立符合命名規則的分支，不可在預設分支（main/master/develop）上直接修復。
- 測試撰寫由 agent 自行驗證，無人工關卡，驗證不過就重試直到通過為止。
- `.test-baseline` 驗證不可跳過。
- 覆蓋率與測試失敗的 retry 上限共用同一計數器（僅限步驟 6 的實作 retry）。
- Ticket 若有母票或評論，均須納入問題理解，不可忽略。
- 實作完成後必須建立 PR 或 MR，不可僅推送分支後停止。

## 錯誤處理

| 情況 | 處理方式 |
|------|---------|
| 疑似外部依賴問題（第三方未呼叫 API） | 停止，要求人工向第三方確認後再重試 |
| 問題涉及 schema 變動 | 建議改用 /plan-writer，停止 |
| .test-baseline 遺失 | 停止，要求從步驟 3 重新執行 |
| impl_retry_count >= max_impl_retry | 停止，提示人工介入 |
