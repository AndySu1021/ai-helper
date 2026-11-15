---
name: gitlab-mr
description: 在 tmp/review.md 與 tmp/security.md 無 blocker 的前提下，使用 glab CLI 建立 GitLab Merge Request。不得自動 merge，merge 必須由人工操作。
tools: ["Read", "Bash", "AskUserQuestion"]
---

# GitLab MR — 建立 Merge Request

在審查通過後建立 GitLab MR，回傳 MR 連結供人工 merge。

## 使用方式

```
/gitlab-mr
```

---

## 步驟 1：前置條件驗證

```bash
TICKET_ID=$(cat tmp/.current-ticket)
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
- 若任一檔案 `status: blocked`，立即停止並顯示：

```
❌ 無法建立 MR：審查發現 blocker

tmp/<ticket-id>/review.md：<blocked / passed>
tmp/<ticket-id>/security.md：<blocked / passed>

請先解決所有 blocker 後再建立 MR。
```

---

## 步驟 2：收集資訊並確認

平行執行：

```bash
git branch --show-current
git log <base_branch>...HEAD --oneline
git diff <base_branch>...HEAD --stat
```

```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")
```

使用 `AskUserQuestion` 一次詢問以下問題，等待使用者全部回覆後再繼續：

1. **目標分支**：預設為設定中的 `base_branch`（`<值>`），是否確認？
2. **Jira Ticket**：從分支名稱自動解析（如 `CEX-1234`）；若無法解析，請提供 ticket 號碼。

---

## 步驟 3：草擬 MR 內容

閱讀實際的 `git diff <base_branch>...HEAD`，根據變更內容草擬：

- **標題**：格式 `<TICKET>: <簡短描述>`，少於 70 字元
- **Description**：說明「為何」做與「做了什麼」

**禁止憑空捏造 MR 內容，必須根據實際 diff 撰寫。**

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
  --title "<TICKET>: <簡短描述>" \
  --target-branch "<目標分支>" \
  --description "$(cat <<'EOF'
## Ticket

<TICKET>

## Description

<說明>

## Changes

- <主要變更>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)" \
  --yes
```

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
- 標題不超過 70 字元，細節放在 description。

## 錯誤處理

| 情況 | 處理方式 |
|------|---------|
| glab 未安裝 | 提示安裝或使用 `glab auth login` |
| glab 未登入 | 提示執行 `glab auth login --hostname <hostname>` |
| 分支已有 MR | 顯示現有 MR URL，不重試 |
| Push 失敗 | 顯示 git 錯誤，停止 |
| review.md 或 security.md 有 blocker | 停止，列出 blocker |
