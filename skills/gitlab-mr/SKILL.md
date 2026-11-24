---
name: gitlab-mr
description: 在 tmp/review.md 與 tmp/security.md 無 blocker 的前提下，使用 glab CLI 建立 GitLab Merge Request。不得自動 merge，merge 必須由人工操作。
tools: ["Read", "Bash", "AskUserQuestion"]
---

# GitLab MR — 建立 Merge Request

在審查通過後建立 GitLab MR，回傳 MR 連結供人工 merge。

## 使用方式

```
/gitlab-mr <ticket-id>
```

---

## 步驟 1：前置條件驗證

```bash
TICKET_ID="${ARGUMENTS:-}"
if [ -z "${TICKET_ID}" ]; then
  # AskUserQuestion: 請提供 ticket ID（例如 PROJ-123）
fi
```

平行執行：

```bash
# 確認 glab 已安裝並登入
glab auth status

# 取得目前分支
git branch --show-current

# 確認有 commit
git log HEAD --oneline -1
```

檢查 `tmp/${TICKET_ID}/review.md` 與 `tmp/${TICKET_ID}/security.md`：

**狀態驗證**：
- 若任一檔案 `status: blocked`，立即停止：

```
❌ 無法建立 MR：審查發現 blocker

tmp/<ticket-id>/review.md：<blocked / passed>
tmp/<ticket-id>/security.md：<blocked / passed>

請先解決所有 blocker 後再建立 MR。
```


**報告時效驗證**：

```bash
LAST_COMMIT_TIME=$(git log -1 --format="%ct")
REVIEW_CREATED=$(grep '^created:' "tmp/${TICKET_ID}/review.md" | head -1 | awk '{print $2}')
SECURITY_CREATED=$(grep '^created:' "tmp/${TICKET_ID}/security.md" | head -1 | awk '{print $2}')
REVIEW_TS=$(date -d "${REVIEW_CREATED}" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "${REVIEW_CREATED}" +%s)
SECURITY_TS=$(date -d "${SECURITY_CREATED}" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "${SECURITY_CREATED}" +%s)
```

若 `REVIEW_TS` 或 `SECURITY_TS` 早於 `LAST_COMMIT_TIME`（報告產生時間早於最新 commit），停止並警告：

```
⚠️ 無法建立 MR：審查報告可能已過期

最新 commit：<YYYY-MM-DD HH:MM>
review.md 產生時間：<YYYY-MM-DD>
security.md 產生時間：<YYYY-MM-DD>

有新的 commit 在報告產生後才提交，審查結果可能不反映目前程式碼。
請重新執行 /code-review 與 /security-scan 後再建立 MR。
```

---

## 步驟 2：收集資訊

平行執行：

```bash
CURRENT_BRANCH=$(git branch --show-current)
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")

# 從分支名稱解析 Jira Ticket（格式如 feature/PROJ-123-xxx 或 v1.2.0/feat/PROJ-123_xxx）
JIRA_TICKET=$(echo "${CURRENT_BRANCH}" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1)
```

**自動推斷規則**：
- `BASE_BRANCH`：直接使用 `origin/HEAD` 推斷值，不詢問
- `JIRA_TICKET`：能從分支名稱解析就直接使用

僅在以下情況才以 `AskUserQuestion` 詢問：
- 分支名稱無法解析出任何 Jira Ticket 格式（`[A-Z][A-Z0-9]+-[0-9]+`），且 `$ARGUMENTS` 中也無 ticket ID → 詢問 Jira Ticket

```bash
git log "${BASE_BRANCH}...HEAD" --oneline
git diff "${BASE_BRANCH}...HEAD" --stat
```

---

## 步驟 3：草擬 MR 內容

閱讀實際的 `git diff <base_branch>...HEAD`，根據變更內容草擬：

- **標題**：直接使用分支名稱 `${CURRENT_BRANCH}`，不另行摘要
- **Description**：**必須**讀取 `templates/mr-description.md` 作為模板，依格式填寫，所有欄位使用中文

**格式規則（嚴格遵守）：**
- Description 只能包含 `## Ticket`、`## Description`、`## Changes` 三個 section
- 禁止使用 `## Summary`、`## Test Plan`、`## Test plan`、`## Background` 或任何其他 section 名稱
- 禁止在 description 末尾加入任何署名或生成標記（例如 `🤖 Generated with ...`）
- 禁止憑空捏造 MR 內容，必須根據實際 diff 撰寫

---

## 步驟 4：Push 分支

若分支無上游：

```bash
git push -u origin HEAD
```

若已有上游且有未推送的 commit：

```bash
git push
```

---

## 步驟 5：建立 MR

```bash
glab mr create \
  --title "${CURRENT_BRANCH}" \
  --target-branch "<目標分支>" \
  --description "$(cat <<'EOF'
## Ticket

<TICKET>

## Description

<中文說明：為何做這個變更>

## Changes

- <主要變更項目（中文）>
EOF
)" \
  --yes
```

description 必須嚴格遵照 `templates/mr-description.md` 的三個 section 結構，不得增減 section。

---

## 步驟 6：確認 MR 狀態（G3）

建立後執行：

```bash
glab mr view --output json | grep '"state"'
```

確認 MR 狀態為 `opened`。若狀態非 `opened`（例如建立失敗），顯示錯誤並停止。

**G3 只要求 MR 為開啟狀態，不等待 merge。** merge 由人工在 GitLab 介面操作，與此流程無關。

---

## 步驟 7：回報結果

顯示 MR URL，並提示：

```
✅ MR 已建立：<MR_URL>
狀態：opened

下一步：人工 review 並 merge。
注意：此 MR 不會自動 merge，需由 reviewer 手動操作。
```

---

## 規則

- **不得自動 merge**，merge 必須由人工在 GitLab 介面操作。
- **不得推送至 `main` 或 `release/*`**。
- 若 `glab mr create` 失敗且該分支已有 MR，回報現有 MR URL，不重試。
- 標題直接使用分支名稱，細節放在 description。

## 錯誤處理

| 情況 | 處理方式 |
|------|---------|
| glab 未安裝 | 提示安裝或使用 `glab auth login` |
| glab 未登入 | 提示執行 `glab auth login --hostname <hostname>` |
| 分支已有 MR | 顯示現有 MR URL，不重試 |
| Push 失敗 | 顯示 git 錯誤，停止 |
| review.md 或 security.md 有 blocker | 停止，列出 blocker |
| review.md 或 security.md 早於最新 commit | 停止，要求重新執行審查 |
