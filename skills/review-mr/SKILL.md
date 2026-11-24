---
name: review-mr
description: 審查外部 MR/PR。取得 diff 後偵測 Jira ticket 或需求文件，呼叫 code-review 與 security-scan，並驗證實作是否滿足需求，合併結果寫入 tmp/mr-review/<編號>.md。不發佈評論至 MR/PR，僅保留本地報告。
tools: ["Read", "Write", "Bash", "Glob", "Grep", "AskUserQuestion"]
---

# MR Review — 外部 MR/PR 審查

對已存在的 MR 或 PR 進行程式碼審查、安全掃描，以及需求符合度驗證，不直接修改分支。

## 使用方式

```
/review-mr <MR/PR 編號或連結>
```

---

## 步驟 1：解析輸入

從 `$ARGUMENTS` 判斷輸入類型：

先從 remote URL 判斷 git host：

```bash
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
echo "$REMOTE_URL" | grep -q "github.com" && GIT_HOST=github || GIT_HOST=gitlab
```

依 `GIT_HOST` 決定指令：
- **GitLab MR 編號**（純數字，`GIT_HOST=gitlab`）：使用 `glab mr diff <編號>`
- **GitLab MR 連結**（包含 `gitlab`）：從連結解析編號後同上
- **GitHub PR 編號**（純數字，`GIT_HOST=github`）：使用 `gh pr diff <編號>`
- **GitHub PR 連結**（包含 `github.com`）：從連結解析編號後同上

若輸入含完整 URL，URL 本身即可判斷 host，無視 remote 推斷結果。

若工具未安裝，停止並回報，不可繼續。

---

## 步驟 2：取得 diff 與 commit 訊息

依解析結果執行：

```bash
# GitLab
glab mr diff <MR_ID>

# GitHub
gh pr diff <PR_NUMBER>
```

同時取得 MR metadata 與 commit 列表：
```bash
# GitLab
glab mr view <MR_ID> --output json
glab mr commits <MR_ID>

# GitHub
gh pr view <PR_NUMBER> --json title,body,headRefName,baseRefName,commits
```

---

## 步驟 2.5：偵測需求來源

從以下位置以正規表達式 `[A-Z][A-Z0-9]+-\d+` 掃描 Jira ticket 編號：

1. MR/PR **標題**
2. MR/PR **描述（body）**
3. 所有 **commit 訊息**
4. **分支名稱**（來源分支，例如 `feature/PROJ-123-add-login`）

將所有找到的 ticket 編號去重後，依以下流程處理：

### 若有找到 ticket 編號

若有找到 ticket 編號，嘗試以下方式擷取 ticket 內容：

```bash
# 方法 A：jira CLI（若已安裝）
jira issue view <TICKET_ID> --raw 2>/dev/null

# 方法 B：curl Jira REST API（若設有 JIRA_BASE_URL 環境變數）
curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
  "$JIRA_BASE_URL/rest/api/2/issue/<TICKET_ID>" 2>/dev/null
```

從回應中擷取：
- **Issue Type**：Story / Bug / Task / Sub-task
- **Summary**（標題）
- **Description**（需求描述）
- **Acceptance Criteria**（驗收條件，通常在 description 或 customfield 中）
- **Fix Version / Sprint**（選用，提供上下文）

若兩種方法皆失敗，記錄「無法取得 Jira 內容（工具未安裝或 token 未設定）」，繼續後續流程，**不可中止**。

### 若未找到 ticket 編號

檢查 MR/PR 描述中是否有其他需求文件連結（Confluence URL、Notion URL、Google Docs URL 等）。若有，使用 `WebFetch` 嘗試擷取標題與摘要供參考。若無任何需求來源，在報告中標示「未偵測到需求來源」，跳過需求符合度檢查。

---

## 步驟 3：顯示摘要並確認

向使用者呈現 MR/PR 的基本資訊：

```
══════════════════════════════════
MR/PR 摘要
══════════════════════════════════
編號：<編號>
標題：<標題>
分支：<來源分支> → <目標分支>
作者：<作者>
變更檔案數：<X>

變更摘要：
<列出主要變更的檔案與說明>

需求來源：
  Jira：<PROJ-123 — 標題> 或 <未偵測到>
  類型：<Story / Bug / Task> 或 <N/A>
══════════════════════════════════
```

使用 `AskUserQuestion` 詢問：

> 是否開始審查？有需要特別關注或略過的地方嗎？

---

## 步驟 4：執行審查

```bash
# 以 mr-<編號> 作為隔離用的 ticket-id，與其他進行中的票互不干擾
MR_TICKET_ID="mr-${MR_ID}"
mkdir -p "tmp/${MR_TICKET_ID}"
```

在暫存分支或直接使用 diff 內容，**同時**呼叫：
- `/code-review ${MR_TICKET_ID}`（傳入 diff 內容）
- `/security-scan ${MR_TICKET_ID}`（傳入 diff 內容）

> code-review 與 security-scan 的輸出會寫入 `tmp/mr-<MR_ID>/review.md` 與 `tmp/mr-<MR_ID>/security.md`。
> 步驟 5 合併結果時從此路徑讀取。

---

## 步驟 4.5：需求符合度檢查

**僅在步驟 2.5 成功取得需求內容時執行。**

依據取得的 Issue Type，採用對應的驗證策略：

### Story / Task

逐條列出驗收條件（Acceptance Criteria），對每一條判斷 diff 中是否有對應實作：

| 驗收條件 | 狀態 | 佐證（檔案:行號） |
|---------|------|----------------|
| AC1：<描述> | ✅ 已實作 / ❌ 未發現 | <路徑:行號> 或 — |

判斷原則：
- 若 diff 中有明確對應該條件的程式變更 → ✅ 已實作
- 若 diff 中無對應跡象，且非框架/配置層面可自動滿足 → ❌ 未發現，列為 **blocker**
- 若需求描述模糊無法判斷 → ⚠️ 無法驗證，列為 **warning**

### Bug

從需求描述中找出：
- **重現步驟**（Reproduction Steps）
- **預期行為**（Expected Behavior）
- **實際行為**（Actual Behavior）

在 diff 中尋找：
1. 修正觸發 bug 的程式碼路徑
2. 是否有對應的測試（regression test）覆蓋此 bug 場景

| 驗證項目 | 狀態 | 說明 |
|---------|------|------|
| 錯誤路徑已修正 | ✅ / ❌ | <佐證或說明> |
| Regression test 存在 | ✅ / ❌ / ⚠️ 無法判斷 | <測試檔路徑> 或 — |

若錯誤路徑修正無法在 diff 中辨識 → 列為 **blocker**。
若缺少 regression test → 列為 **warning**。

---

## 步驟 5：合併結果並儲存

將所有審查結果合併，去重後寫入 `tmp/mr-review/<編號>.md`：

```markdown
---
stage: mr
status: <blocked / passed>
created: <YYYY-MM-DD>
source: <MR/PR URL>
tickets: <PROJ-123, PROJ-456 或 none>
---

# MR/PR 審查報告：<標題>

**編號**：<編號>
**分支**：<來源> → <目標>
**審查時間**：<YYYY-MM-DD HH:MM>

---

## 需求符合度

> 若未偵測到需求來源，此區段顯示「未偵測到需求來源，略過需求符合度檢查」。
> 若 Jira 工具未安裝且環境變數未設，顯示「Jira 擷取略過（工具未安裝）」。
> 若工具失敗，顯示具體錯誤訊息。

**Jira**：<PROJ-123> — <標題>
**類型**：<Story / Bug / Task>

<依步驟 4.5 的對應格式輸出驗收條件表格或 Bug 驗證表格>

**需求符合度裁定**：PASS / FAIL（X 條未滿足）

---

## 阻擋項（必須修正後才能 merge）

<合併 code-review、security-scan 與需求符合度的阻擋項結果>

## 警告（建議修正）

<合併警告結果>

## 建議（次要）

<合併建議結果>

---

## Coding Style

> 參考來源：<CLAUDE.md / .pipeline/style_guide.md / 既有程式碼推斷>

<從 code-review 報告的 Coding Style 區段複製>

---

## 審查結論

**裁定：通過 / 需修正**
**程式碼審查**：<通過 / X 個阻擋項>
**安全掃描**：<通過 / X 個阻擋項>
**需求符合度**：<通過 / X 條未滿足 / 略過>
**Coding Style**：<一致 / X 項不符合團隊規範>
```

---

## 規則

- **不發佈任何評論**到 MR/PR，僅保留本地報告。
- 若 `glab` 或 `gh` 未登入，停止並提示使用者登入，不可繼續。
- diff 若超出單次 context 範圍，分批審查並在報告中標示。
- 需求來源擷取失敗時**不可中止流程**，降級為略過需求符合度檢查並在報告中說明原因。
- 需求符合度的阻擋項與 code-review/security-scan 的阻擋項**同等權重**，皆會導致裁定為「需修正」。
- 若同一 MR 關聯多個 ticket，每個 ticket 各自產生一份需求符合度表格。
