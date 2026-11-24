---
name: bugfix
description: 自動化 bug 修復流程。理解症狀 → 形成可偽造假設 → 以 reproduction test 驗證假設 → 修復 → Code Review → MR。適用於症狀已知的 bug（生產環境緊急、QA 驗收票）。需要設計新 API 或不確定修法，請改用 /plan-writer。
tools: ["Read", "Write", "Bash", "AskUserQuestion"]
---

# Bugfix — 完整自動化 Bug 修復流程

從 bug 診斷到 MR 提交的全自動化流程。任一閘門失敗即停止，等待人工處理後繼續。

**適合使用 `/bugfix`**：症狀已知的 bug（生產環境緊急、QA 驗收票、測試補足）。  
**應改用 `/plan-writer` + `/implement`**：修復方式不確定、涉及 API 設計變動、需要跨模組架構調整。

## 使用方式

```
/bugfix <問題描述或 ticket 號碼>
```

---

## 核心規則（所有步驟均適用）

> **程式碼隔離**：Phase 3 開始（步驟 5）後，所有 `.go` 檔案的建立與修改**只能在 `${WORKTREE_PATH}` 下進行**。在主工作目錄直接修改程式碼是**嚴重違規**，等同於繞過 TDD 驗證流程。
>
> **閘門強制輸出**：G1–G5 每個閘門都**必須明確輸出評估區塊**，不得默默跳過。即使判斷為「通過」也要輸出，作為流程紀錄。
>
> **交接檔驅動**：每個步驟開始前必須確認前一步驟的交接檔存在才能繼續（見各步驟的「前置條件」）。

---

## Phase 1：理解症狀

### 步驟 1：前置作業

```bash
TICKET_ID="${ARGUMENTS:-}"
```

若 `$ARGUMENTS` 包含 ticket 格式（如 `PROJ-1234`），取該值；否則以 `AskUserQuestion` 詢問識別碼。

```bash
mkdir -p "tmp/${TICKET_ID}"
```

---

### 步驟 2：解析症狀

若 `$ARGUMENTS` 包含 ticket 格式，讀取 ticket 內容（描述、重現步驟、預期行為、母票、所有評論）。

從 `$ARGUMENTS`、ticket 內容與錯誤訊息中**自動解析**以下四項：

1. 觀察到的錯誤行為
2. 預期的正確行為
3. 重現條件（route / input / 環境）
4. 錯誤的穩定性（always / sometimes / only on prod）

**只對確實缺少的項目**以 `AskUserQuestion` 詢問，不批量詢問全部四項。

---

**閘門 G1：錯誤能穩定重現嗎？**

**必須輸出閘門評估**（無論結果為何）：

```
🔍 閘門 G1 — 可重現性
穩定性：[always / sometimes / only on prod]
判斷：[通過 ✅ | 停止 ❌]
原因：[說明]
```

若穩定性為 `sometimes` 或 `only on prod`（非確定性 bug）：

```
❌ 無法自動修復

此 bug 無法在本地穩定重現（flaky / prod-only）。
自動修復流程依賴 reproduction test 驗證假設，
無法穩定重現代表無法客觀確認假設是否正確。

診斷摘要已寫入 tmp/<ticket-id>/plan.md。
建議：人工在 prod 環境收集更多 log 後再執行 /bugfix。
```

停止流程，不繼續。

---

**閘門 G2：確認是程式 bug？**

**必須輸出閘門評估**（無論結果為何）：

```
🔍 閘門 G2 — 問題分類
分類：[程式 bug / 使用者操作 / 外部依賴 / 設定錯誤]
判斷：[通過 ✅ | 停止 ❌]
原因：[說明]
```

若判斷為以下情況則停止，說明原因：
- 使用者操作問題
- 外部依賴問題（第三方服務、基礎設施）
- 設定錯誤（環境變數、config 檔）

確認為程式 bug 才繼續。

---

## Phase 2：形成假設

### 步驟 3：靜態探索與假設形成

使用 `Glob` 和 `Grep` 追蹤症狀：錯誤訊息字串 → function 名稱 → call stack → 相關模組 → 既有測試。

根據探索結果，形成 **1–3 個 root cause 假設**。每個假設**必須寫成可偽造的形式**：

```
假設 A（信心度：高）
  陳述：service.go:142 的 nil check 在 user_id = 0 時被跳過
  可驗證條件：呼叫 CreateOrder(ctx, userID=0, ...) 應回傳 ErrInvalidUser，
              但目前回傳 nil
  排除的假設：DB constraint 問題 — 排除，error log 在 DB call 之前出現

假設 B（信心度：低）
  陳述：...
  可驗證條件：...
```

信心度由高至低排列，步驟 6 優先驗證信心度最高的假設。

---

**閘門 G3：至少有一個假設可以寫成可驗證條件嗎？**

**必須輸出閘門評估**（無論結果為何）：

```
🔍 閘門 G3 — 假設可驗證性
假設數量：[N 個]
最高信心度假設：[假設 A 摘要]
可驗證條件：[能明確描述 ✅ | 無法描述 ❌]
判斷：[通過 ✅ | 停止 ❌]
```

若所有假設的「可驗證條件」都無法明確描述（例如 race condition 無法透過單一呼叫重現）：

```
❌ 假設無法自動驗證

找不到可以寫成 reproduction test 的可驗證條件。
此類 bug 需要人工介入（例如加 instrumentation、在 staging 觀察）。

假設清單已寫入 tmp/<ticket-id>/plan.md。
```

停止流程，不繼續。

---

### 步驟 4：產出 plan.md

> **前置條件**：G1、G2、G3 三個閘門均已輸出「通過 ✅」。**若任一閘門未輸出評估或未通過，不得執行本步驟。**

根據步驟 3 的探索與假設，寫入 `tmp/${TICKET_ID}/plan.md`：

```markdown
---
stage: plan
created: <YYYY-MM-DD>
source: <ticket 連結或描述>
bugfix: true
fix_version: <fix_version>
bug_branch: <待步驟 5 填入>
base_branch: <待步驟 5 填入>
hypothesis_verified: false
---

# 修復計畫：<簡短描述>

## 問題描述

<觀察到的錯誤行為>

## Root Cause 假設

### 假設 A（信心度：高）★ 優先驗證

**陳述**：<根本原因的具體描述，包含檔案與行號>

**可驗證條件**：
- 呼叫：`<function 名稱與輸入>`
- 目前行為：`<錯誤的回傳值或副作用>`
- 預期行為：`<正確的回傳值或副作用>`

**排除的其他假設**：
- <假設 X>：排除，因為 <理由>

### 假設 B（信心度：低）

**陳述**：...
**可驗證條件**：...

## 預期行為

<正確行為的完整描述>

## 修復方式

<根據假設推斷的修復做法；步驟 6 驗證後才算確認>

## 影響檔案

| 檔案路徑 | 變更類型 | 說明 |
|---------|---------|------|

## API 變更

無

## 測試策略

- Reproduction test（`TestBug_<ticket>_Reproduce`）：先驗證假設，後驗證修復
- 修復後確認 reproduction test 通過（Green）
- 確認未破壞既有測試

## 風險

| 風險 | 影響 | 緩解方式 |
|-----|------|---------|
```

---

## Phase 3：驗證假設

### 步驟 5：建立 Worktree

> **前置條件**：`tmp/${TICKET_ID}/plan.md` 必須存在且 `hypothesis_verified: false`（即步驟 4 已完成）。若檔案不存在，**立即停止**並提示：
> ```
> ❌ 缺少 tmp/<ticket-id>/plan.md
> 請先完成步驟 4（產出 plan.md）後再繼續。
> ```

> **隔離規則**：步驟 5 以後的所有程式碼操作（包含測試檔、實作檔）**只能在 `${WORKTREE_PATH}` 下進行**，絕對不可在主工作目錄（主 repo）直接修改任何 `.go` 檔案。

從 `tmp/${TICKET_ID}/plan.md` 的 frontmatter 讀取 `fix_version`（若未填入則以 `AskUserQuestion` 詢問）。從 ticket 標題自動選出 3–5 個英文單字作為 `short_desc`（全小寫、底線連接），不詢問使用者。

```bash
FIX_VERSION=$(grep '^fix_version:' "tmp/${TICKET_ID}/plan.md" | awk '{print $2}')
SHORT_DESC="<short_description>"
BUG_BRANCH="${FIX_VERSION}/bug/${TICKET_ID}_${SHORT_DESC}"
BASE_BRANCH="release/${FIX_VERSION}"
WORKTREE_PATH="tmp/worktrees/${TICKET_ID}"
```

確認 base branch 存在：

```bash
git fetch origin "${BASE_BRANCH}" 2>/dev/null
if ! git ls-remote --heads origin "${BASE_BRANCH}" | grep -q "${BASE_BRANCH}"; then
  echo "❌ base branch '${BASE_BRANCH}' 不存在，請確認 fix_version 是否正確。"
  exit 1
fi
```

建立 worktree：

```bash
mkdir -p tmp/worktrees
git worktree remove "${WORKTREE_PATH}" --force 2>/dev/null || true
git worktree add "${WORKTREE_PATH}" -b "${BUG_BRANCH}" "origin/${BASE_BRANCH}"
```

將分支資訊回寫至 `tmp/${TICKET_ID}/plan.md` 的 frontmatter（`bug_branch` 與 `base_branch` 欄位），並寫入 worktree 資訊：

```bash
cat > "tmp/${TICKET_ID}/.worktree" <<EOF
path: ${WORKTREE_PATH}
branch: ${BUG_BRANCH}
base: ${BASE_BRANCH}
EOF
```

確認 `tmp/${TICKET_ID}/.worktree` 已寫入後繼續步驟 6。

---

### 步驟 6：Reproduction Test — 驗證假設

> **前置條件**：`tmp/${TICKET_ID}/.worktree` 必須存在（即步驟 5 已完成）。若檔案不存在，**立即停止**並提示：
> ```
> ❌ 缺少 tmp/<ticket-id>/.worktree
> 請先完成步驟 5（建立 worktree）後再繼續。
> ```

讀取 `tmp/${TICKET_ID}/.worktree`，取得 `WORKTREE_PATH`。

依 plan.md 信心度最高的假設，**在 `${WORKTREE_PATH}` 中**撰寫 reproduction test：

- 命名：`TestBug_<ticket>_Reproduce`（例：`TestBug_CEX123_Reproduce`）
- **只呼叫現有 interface，不寫任何新實作**
- 斷言「目前錯誤的行為」（例如：期待 `err != nil`，斷言目前 `err == nil`）
- 測試通過 = bug 重現成功（反直覺，此處 PASS = 假設確認）

**測試放置規則**：將 reproduction test 加入與受測程式碼**同一 package 的既有測試檔案**（例如 `service_test.go`、`handler_test.go`）。若該 package 下尚無測試檔案，才建立新檔案，並以被測模組命名（例如 `service_test.go`），**不得以 ticket id 命名**（例如 `bug_cex123_test.go` 是錯誤的）。

在 **不改任何實作程式碼** 的前提下執行：

```bash
go -C "${WORKTREE_PATH}" test ./... -run TestBug_<ticket>_Reproduce -v
```

---

**閘門 G4：Reproduction test 的失敗類型**

| 結果 | 說明 | 處理 |
|------|------|------|
| **FAIL（runtime assertion）** | ✅ 假設確認：bug 能重現，繼續 Phase 4 | 更新 plan.md `hypothesis_verified: true` |
| **FAIL（compile error）** | ⚠️ interface 不存在，無法確認行為假設 | 標記信心度為低，以 `AskUserQuestion` 詢問是否繼續 |
| **PASS** | ❌ 假設被推翻：此條件無法重現 bug | 嘗試次優假設（最多 2 次）；2 次仍 PASS → 停止，交人工 |

**G4 PASS 時的停止訊息：**

```
❌ Root cause 假設被推翻

Reproduction test 通過（bug 未能重現），代表假設 A 並非此 bug 的根因。
已嘗試 <N> 個假設，均無法重現 bug。

假設清單與排除理由已更新至 tmp/<ticket-id>/plan.md。
建議：重新收集 log 或在 staging 加 instrumentation 後再執行 /bugfix。
```

---

## Phase 4：修復

### 步驟 6.5：Blast Radius 排查

假設確認後，使用 `Grep` 與 `Glob` 在整個 codebase 搜尋相同的 bug pattern（例如相同的 nil check 缺失、相同的錯誤邏輯、同一段被複製到多處的程式碼）。

對每個搜尋結果逐一判斷：
- **相同 root cause，且會觸發相同錯誤行為** → 確認為 bug，加入修復清單
- **相似寫法，但情境不同不會觸發** → 記錄為「潛在風險，本次不修」

將結果更新至 `tmp/${TICKET_ID}/plan.md`：

```markdown
## Blast Radius

### 一併修復
| 檔案路徑 | 位置 | 說明 |
|---------|------|------|
| <路徑>  | <行號或 function> | <為何確認為同一 bug> |

### 潛在風險（本次不修）
| 檔案路徑 | 位置 | 說明 |
|---------|------|------|
| <路徑>  | <行號或 function> | <相似但不影響的原因> |
```

同時將「一併修復」的檔案追加至 `plan.md` 的「影響檔案」表格，讓 implementer 知道修復範圍。

若無其他受影響位置，在「Blast Radius」區段填寫「無」後繼續。

---

### 步驟 7：Implementer 修復

讀取 `tmp/${TICKET_ID}/.worktree`，取得 `WORKTREE_PATH`。

以 **implementer** agent 執行，傳入：
- `tmp/${TICKET_ID}/plan.md`（含已確認的假設、reproduction test 名稱、**Blast Radius 一併修復清單**）
- ticket-id：`${TICKET_ID}`
- `working_dir: ${WORKTREE_PATH}`
- 明確指示：**修復 plan.md「影響檔案」與「Blast Radius 一併修復」中所有確認的 bug 位置，不重構，不修潛在風險項目**

**驗證 1：Reproduction test 必須 PASS**

```bash
go -C "${WORKTREE_PATH}" test ./... -run TestBug_<ticket>_Reproduce -v
```

若 FAIL，implementer 重試；連續失敗超過 3 次 → 停止（`blocked-impl`），保留 worktree。

**驗證 2：完整 test suite 無 regression**

```bash
go -C "${WORKTREE_PATH}" test ./...
```

若有既有測試失敗，implementer 修正（重試上限同上）。

---

**閘門 G5：覆蓋率是否退步？**

```bash
CHANGED_PACKAGES=$(git -C "${WORKTREE_PATH}" diff "origin/${BASE_BRANCH}"...HEAD \
  --name-only | grep '\.go$' | grep -v '_test\.go$' \
  | xargs -I{} dirname {} | sort -u | sed 's|^|./|' | tr '\n' ',' | sed 's/,$//')

go -C "${WORKTREE_PATH}" test -coverprofile="tmp/${TICKET_ID}/.coverage.out" \
  -coverpkg="${CHANGED_PACKAGES}" ./...
COVERAGE=$(go tool cover -func="tmp/${TICKET_ID}/.coverage.out" \
  | grep "^total:" | awk '{print $3}' | tr -d '%')
echo "${COVERAGE}" > "tmp/${TICKET_ID}/.coverage-baseline"
```

若與修復前基準值相比退步超過 2%，停止並提示補充測試後重試。

---

## Phase 5：審查 → MR

### 步驟 8：Code Review + Security Scan（並行）

讀取 `tmp/${TICKET_ID}/.worktree`，取得 `WORKTREE_PATH` 與 `BASE_BRANCH`。

並行執行兩個 skill，diff 來源為 worktree 的 bug branch：

```bash
git -C "${WORKTREE_PATH}" diff "origin/${BASE_BRANCH}"...HEAD
```

傳入：
- `working_dir: ${WORKTREE_PATH}`
- `base_branch: origin/${BASE_BRANCH}`

等待結果寫入：
- `tmp/${TICKET_ID}/review.md`（code-review 寫入）
- `tmp/${TICKET_ID}/security.md`（security-scan 寫入）

```bash
REVIEW_STATUS=$(grep '^status:' "tmp/${TICKET_ID}/review.md"   | awk '{print $2}')
SECURITY_STATUS=$(grep '^status:' "tmp/${TICKET_ID}/security.md" | awk '{print $2}')
```

**兩者均非 `blocked`** → 繼續步驟 9。

**任一為 `blocked`** → 自動修復循環（最多 2 輪）：

1. 讀取所有 blocker 項目
2. 以 **implementer** agent 修正（傳入 `working_dir: ${WORKTREE_PATH}` 與 blocker 清單）
3. 修正後重新執行步驟 8
4. 2 輪後仍有 blocker → 停止（`blocked-review`），列出未解決項目，保留 worktree

---

### 步驟 9：提交 MR

讀取 `tmp/${TICKET_ID}/.worktree`，取得 `BUG_BRANCH` 與 `BASE_BRANCH`。

Push bug branch：

```bash
git -C "${WORKTREE_PATH}" push -u origin "${BUG_BRANCH}"
```

依照 **gitlab-mr** skill 完整流程執行，傳入：
- `working_dir: ${WORKTREE_PATH}`
- `source_branch: ${BUG_BRANCH}`
- `target_branch: ${BASE_BRANCH}`

MR 標題格式：直接使用 `${BUG_BRANCH}`（分支名稱）。

MR 建立成功後移除 worktree：

```bash
git worktree remove "${WORKTREE_PATH}" --force
```

顯示完成訊息：

```
══════════════════════════════════
✅ Bug 修復完成 — <ticket-id>
══════════════════════════════════
Bug branch：<BUG_BRANCH>
Base branch：<BASE_BRANCH>
MR：<MR URL>

Root cause：<一行摘要>
Reproduction test：<TestBug_xxx_Reproduce 位置>

下一步：人工 review 並 merge。
══════════════════════════════════
```

---

## 狀態定義

| 狀態 | 說明 |
|------|------|
| `done` | 完成，worktree 已清除，MR 已建立 |
| `stopped-g1` | 非確定性 bug，無法自動重現，交人工 |
| `stopped-g2` | 非程式 bug，停止 |
| `stopped-g3` | 假設無法表達為可驗證條件，交人工 |
| `stopped-g4` | 所有假設均被 reproduction test 推翻，交人工 |
| `blocked-impl` | implementer 重試超限，worktree 保留 |
| `blocked-review` | review/security blocker 未解決，worktree 保留 |

---

## 規則

- 探索根因必須查看實際程式碼，不可憑空假設影響範圍。
- 假設必須寫成可偽造形式（有具體的可驗證條件），不可只寫模糊陳述。
- Reproduction test 必須在**不改任何實作**的前提下執行，FAIL 才算假設確認。
- Reproduction test PASS（bug 無法重現）= 假設被推翻，不可繼續修復。
- Implementer 只修 plan.md 指出的 root cause，不重構其他程式碼。
- 若問題非程式 bug 或涉及 API 設計變動，立即停止。
- Ticket 若有母票或評論，均須納入問題理解。
- Worktree 透過 `git worktree add` 建立，所有程式碼操作在 `${WORKTREE_PATH}` 下執行；`tmp/${TICKET_ID}/` 交接檔保留在主 repo。
- 步驟間以 `tmp/${TICKET_ID}/` 下的交接檔銜接：`.worktree` → `.coverage-baseline` → `review.md` → `security.md`。每步驟開始前讀取前一步的交接檔，結束後確認當前步驟的交接檔已寫入再繼續。
- 不得自動 merge MR，merge 由人工在 GitLab 操作。
