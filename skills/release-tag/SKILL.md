---
name: release-tag
description: 在指定的 release 分支上建立 annotated tag 並 push 到 GitLab。自動計算版號、從 Jira 取得 ticket 標題組成 tag message，確認後才執行。
argument-hint: "[release/rXXXX] [release|bugfix|hotfix]"
tools: ["Bash(git *)", "mcp__atlassian__getJiraIssue", "mcp__atlassian__getAccessibleAtlassianResources", "AskUserQuestion"]
---

你是這個專案的 Release Engineer，協助在 GitLab 上打 annotated tag。

## Tag 版號規則

格式：`v1.<sprint+2>.<hotfix>.<revision>`

- `sprint+2`：從分支名 `release/r00XX` 取出 sprint 號加 2（r0065 → 67）
- `release`：初次上 stage → 第三碼歸 0、第四碼歸 0（`v1.N.0.0`）
- `bugfix`：QA 測出 bug 修訂 → 第四碼 +1（`v1.N.0.X+1`）
- `hotfix`：上線後緊急修復 → 第三碼 +1、第四碼歸 0（`v1.N.X+1.0`）

## 執行步驟

### 1. 蒐集參數

從 `$ARGUMENTS` 解析分支名稱和類型。若缺少任一項，用 AskUserQuestion 分次詢問：

- 缺少分支：「請問要打 tag 的目標分支是哪一條？（例如 release/r0065）」
- 缺少類型：「請問這次是哪種類型？\n1. release - 初次上 stage\n2. bugfix - QA 修訂（第四碼 +1）\n3. hotfix - 上線緊急修復（第三碼 +1）」

### 2. 同步遠端、取得目標 ref

**一律以遠端為主**，不依賴本地 branch 狀態：

```bash
# 同步遠端分支與 tag
git fetch origin <target_branch>
git fetch --tags

# 後續所有操作均使用 origin/<target_branch>
```

### 3. 計算新版號

```bash
# 取得該 sprint 目前最新 tag（N = sprint+2）
git tag --list "v1.<N>.*" --sort=-version:refname | head -1
```

依類型計算新版號：
- **release** → `v1.N.0.0`
- **bugfix** → 第四碼 +1
- **hotfix** → 第三碼 +1，第四碼歸 0

若目前完全沒有 `v1.N.*` 的 tag，代表此 sprint 是首版，直接用 `v1.N.0.0`。

### 4. 撰寫 tag message

```bash
# 取前一個 tag 到遠端分支 HEAD 之間的所有 commit 標題（含 merge commit）
git log <prev_tag>..origin/<target_branch> --pretty=format:"%s"
```

**注意**：不加 `--no-merges`，因為 ticket ID 可能只出現在 merge commit 的標題中（例如 `Merge branch 'r0065/bug/CEX-23896' into 'release/r0065'`）。

1. 用 regex `<(CEX|PRD)-[0-9]+>` 或 `(CEX|PRD)-[0-9]+` 擷取所有 ticket ID，去重排序
2. 對每個 ticket ID 呼叫 `mcp__atlassian__getJiraIssue`（cloudId 用 `mcp__atlassian__getAccessibleAtlassianResources` 取得）
3. 組成每行格式：
   ```
   [CEX-XXXXX] <summary> https://hoyabit02.atlassian.net/browse/CEX-XXXXX
   ```
4. 若無任何 ticket，tag message 留空並告知使用者

### 5. 向使用者確認

用 AskUserQuestion 顯示完整摘要後詢問「確認打 tag？（yes / no）」：

```
即將執行以下操作，請確認：

分支：origin/<target_branch>
Tag ：<new_tag>
類型：<type>

Tag Message：
<message_preview>

確認打 tag？（yes / no）
```

若回答 no，停止並告知已取消，不執行任何 git 操作。

### 6. 建立 tag 並 push

確認後執行，tag 指向**遠端 HEAD**：

```bash
# 取得遠端 HEAD commit hash，確保 tag 打在遠端最新版本上
git rev-parse origin/<target_branch>

git tag -a <new_tag> -m "<message>" origin/<target_branch>
git push origin <new_tag>
```

完成後輸出：
- 新 tag 名稱與其指向的 commit hash
- GitLab tag 頁面連結（從 `git remote get-url origin` 推導）
