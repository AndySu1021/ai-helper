---
name: bugfix
description: Bug 修復流程。負責診斷問題、產出 bug 格式的 plan.md、建立 worktree，然後交給 /implement 執行 TDD 實作。適用於：已知症狀的 bug（生產環境緊急修復、QA 驗收後開出的 bug ticket）。需要設計新 API 或不確定修法，請改用 /plan-writer + /implement。
tools: ["Read", "Write", "Bash", "AskUserQuestion", "EnterWorktree"]
---

# Bugfix — Bug 診斷與計畫

負責到 plan.md 為止。**TDD 實作交由 `/implement` 執行。**

## 適用情境

**適合使用 `/bugfix`**：
- 生產環境緊急 bug，症狀已知
- QA 驗收後開出的 bug ticket，重現步驟清楚
- 測試補足、已知邊界條件遺漏的修復

**應改用 `/plan-writer` + `/implement`**：
- 修復方式不確定，需要方案比較
- 涉及 API 設計變動
- 需要跨多個模組的架構調整

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

## 步驟 1：診斷問題

若 `$ARGUMENTS` 包含 ticket 格式，先讀取 ticket 內容：
- ticket 本身的描述、重現步驟、預期行為
- 若有母票（parent ticket / epic），一併讀取母票描述與驗收條件
- 若 ticket 有評論（comments），一併讀取所有評論（開發者補充、QA 備注、PM 說明等，均視為需求的一部分）

整合以上資訊後，判斷是否需要補充資訊。若 ticket 資訊已足夠理解問題，跳過詢問；否則使用 `AskUserQuestion`：

> 請描述：
> 1. 觀察到的錯誤行為是什麼？
> 2. 預期的正確行為是什麼？
> 3. 是否有重現步驟或錯誤訊息？
> 4. 修復方式是否已有方向？（若完全不確定，建議改用 `/plan-writer`）

**判斷問題性質**：

- 若屬於**使用者操作問題**（非程式缺陷），輸出說明並停止：

  ```
  ══════════════════════════════════
  ℹ️ 非 bug，無需修復
  ══════════════════════════════════
  根據描述，這是使用方式的問題，而非程式缺陷。

  建議操作：<正確使用方式說明>
  ══════════════════════════════════
  ```

- 若屬於**外部依賴問題**（第三方未呼叫、呼叫失敗），立即停止：

  ```
  ══════════════════════════════════
  ⚠️ 無法排查：疑似外部依賴問題
  ══════════════════════════════════
  根據描述，問題可能來自第三方，請先向對方確認：
  1. 對方是否有如期呼叫 API？
  2. 呼叫的 request / response 是否正常？
  3. 對方的錯誤日誌是否有相關記錄？

  確認後若確實為我方程式碼問題，請再次執行 /bugfix。
  ══════════════════════════════════
  ```

- 若確認為程式 bug，繼續步驟 2。

---

## 步驟 2：探索根因

使用 `Glob` 和 `Grep` 找出與問題相關的程式碼：
- 錯誤訊息、function 名稱、API 路徑等關鍵字
- 相關的測試檔案（了解原本預期的行為）
- 相依的模組

目的是確認**哪裡壞了**，以及**修改哪些檔案可以修復**。

---

## 步驟 3：產出 plan.md

根據診斷結果，寫入 `tmp/${TICKET_ID}/plan.md`：

```markdown
---
stage: plan
created: <YYYY-MM-DD>
source: <ticket 連結或描述>
bugfix: true
---

# 修復計畫：<簡短描述>

## 問題描述

<觀察到的錯誤行為>

## 根因

<診斷出的根本原因，包含相關檔案與行號>

## 預期行為

<正確行為>

## 修復方式

<已確認的修復做法>

## 影響範圍

| 檔案路徑 | 變更類型 | 說明 |
|---------|---------|------|
| <路徑>  | 修改/新增 | <說明> |

## API 變更

無

## 測試策略

- 撰寫重現 bug 的失敗測試（Red）
- 修復後確認測試通過（Green）
- 確認未破壞既有測試

## 風險

| 風險 | 影響 | 緩解方式 |
|-----|------|---------|
| <風險描述> | 高/中/低 | <如何降低> |
```

---

## 步驟 4：建立 Worktree

從 ticket 取得以下資訊：
- **Fix version**：ticket 的 Fix Version / Target Version 欄位
- **Short description**：從 ticket 標題自行選出最能描述問題的 3–5 個英文單字，以底線連接，全部小寫（如 `null_pointer_on_login`），不詢問使用者。

分支命名規則：

```
<fix_version>/bug/<ticket_no>_<short_description>
```

範例：`v1.2.3/bug/PROJ-1234_null_pointer_on_login`

若 Fix version 欄位不存在，使用 `AskUserQuestion` 詢問：「Ticket 無 Fix Version，請提供目標版本（例如 v1.2.3）。」

確認後建立 worktree：

```
EnterWorktree(branch: "<branch_name>")
```

---

## 步驟 5：交給 /implement

顯示以下訊息後結束：

```
══════════════════════════════════
✅ 診斷完成，準備進入實作
══════════════════════════════════
plan.md：tmp/<ticket-id>/plan.md
分支：<branch_name>

下一步：
  /implement    開始 TDD 實作（test-writer → 人工確認 → implementer）
══════════════════════════════════
```

---

## 規則

- 只負責到 plan.md 為止，TDD 實作交給 `/implement`。
- 探索根因必須查看實際程式碼，不可憑空假設影響範圍。
- 若問題涉及 API 設計變動，停止並建議改用 `/plan-writer`。
- Ticket 若有母票或評論，均須納入問題理解，不可忽略。
- 修復前必須先建立符合命名規則的分支，不可在預設分支（main/master/develop）上直接修復。
