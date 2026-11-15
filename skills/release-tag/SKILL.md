---
name: release-tag
description: 在 GitLab 上打 annotated tag，自動從 git log 產生 changelog（依 commit message 分類）並寫入 CHANGELOG.md。使用語意化版本（semver），版號由使用者確認後才 push。
tools: ["Read", "Write", "Edit", "Bash", "AskUserQuestion"]
---

# Release Tag — 版本 Tag 與 Changelog

依語意化版本在 GitLab 打 annotated tag，並自動產生或更新 `CHANGELOG.md`。

## 適用對象

此 skill 適用於**任何對目標 repository 有 push 權限的人**，包含開發人員、SRE、DevOps 工程師等。不限於功能開發者，擁有 repo access 的人即可操作。

## 使用方式

```
/release-tag [patch|minor|major|<版號>]
```

- `patch`：修正 bug，第三碼 +1（`1.2.3` → `1.2.4`）
- `minor`：新功能，第二碼 +1，第三碼歸零（`1.2.3` → `1.3.0`）
- `major`：破壞性變更，第一碼 +1，後兩碼歸零（`1.2.3` → `2.0.0`）
- `<版號>`：直接指定版號（例如 `1.5.0`），需符合 `v?X.Y.Z` 格式
- 不帶參數：列出目前 tag 與 commit 後詢問使用者

---

## 步驟 1：確認目前狀態

平行執行：

```bash
# 最新的 tag
git describe --tags --abbrev=0 2>/dev/null || echo "（尚無 tag）"

# 目前分支
git branch --show-current

# 目前 HEAD 的 commit hash（短）
git rev-parse --short HEAD

# 有無未 push 的 commit
git status --short
```

```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")
```

---

## 步驟 2：推算下一個版號

### 若有既有 tag

從最新 tag 解析目前版號（去除前綴 `v`），依 `$ARGUMENTS` 推算：

| 參數 | 範例（目前 `v1.2.3`） | 結果 |
|------|----------------------|------|
| `patch` | `v1.2.3` | `v1.2.4` |
| `minor` | `v1.2.3` | `v1.3.0` |
| `major` | `v1.2.3` | `v2.0.0` |
| `1.5.0` | 直接使用 | `v1.5.0` |
| 未提供 | 顯示選項詢問 | — |

### 若無既有 tag

建議版號 `v0.1.0`，或依 `$ARGUMENTS` 決定：
- `patch` / `minor` → `v0.1.0`
- `major` → `v1.0.0`
- 直接指定 → 使用指定值

---

## 步驟 3：收集 commit log

取得上一個 tag 到 HEAD 的所有 commit（若無 tag 則取全部）：

```bash
# 有上一個 tag
git log <last-tag>..HEAD --oneline --no-merges

# 無 tag
git log HEAD --oneline --no-merges
```

若輸出為空（無新 commit），告知使用者並停止：

```
目前沒有新的 commit（HEAD 已在最新 tag 上），無需打 tag。
```

---

## 步驟 4：分類 commit

將 commit message 依慣例分類（支援 Conventional Commits 與一般格式）：

| 類別 | 偵測關鍵字 | Changelog 標題 |
|------|-----------|--------------|
| 新功能 | `feat:`、`feature:`、`add ` | `### 新功能` |
| Bug 修正 | `fix:`、`bugfix:`、`hotfix:` | `### Bug 修正` |
| 效能改善 | `perf:`、`refactor:` | `### 改善` |
| 文件 | `docs:`、`doc:` | `### 文件` |
| 破壞性變更 | `BREAKING CHANGE`、`!:` | `### 破壞性變更 ⚠️` |
| 其他 | 其餘 | `### 其他` |

**若 commit message 包含 ticket 號碼**（格式 `#123`、`PROJ-123`、`[PROJ-123]`），保留在 changelog 條目中。

---

## 步驟 5：草擬 changelog 條目

草擬本次版本的 changelog，格式：

```markdown
## [<版號>] — <YYYY-MM-DD>

### 破壞性變更 ⚠️
- <commit message>

### 新功能
- <commit message>

### Bug 修正
- <commit message>

### 改善
- <commit message>

### 其他
- <commit message>
```

空的分類不顯示。

---

## 步驟 6：與使用者確認

顯示確認資訊，**等待使用者明確回覆後才繼續**：

```
══════════════════════════════════
準備打 Tag
══════════════════════════════════
Tag 版號：  v<版號>
目標：      目前分支（<branch>），commit <hash>
Commit 數：<N> 個新 commit

Changelog 預覽：
─────────────────
<草擬的 changelog 內容>
─────────────────

確認後將：
  1. 更新 CHANGELOG.md
  2. Commit changelog
  3. 建立 annotated tag
  4. Push tag 到 GitLab

確認打 tag 嗎？若要調整版號或 changelog 內容，請直接說明。
══════════════════════════════════
```

使用 `AskUserQuestion` 等待使用者確認。若使用者要求調整，修改後重新顯示預覽，再次確認。

---

## 步驟 7：更新 CHANGELOG.md

讀取現有的 `CHANGELOG.md`（若不存在則建立），將新版本的條目插入到最頂部的現有版本**之前**（維持新版本在最上方的慣例）。

格式範例（插入後）：

```markdown
# Changelog

## [v1.3.0] — 2026-11-12

### 新功能
- feat: 新增 API rate limiting

### Bug 修正
- fix: 修正 token 過期後的 refresh 邏輯

---

## [v1.2.0] — 2026-10-01
...（既有內容保留不動）
```

---

## 步驟 8：Commit changelog

```bash
git add CHANGELOG.md
git commit -m "chore: release <版號>"
```

---

## 步驟 9：建立並 push tag

### 9a. 建立 annotated tag

Tag message 使用本次 changelog 內容：

```bash
git tag -a <tag-name> HEAD -m "$(cat <<'EOF'
<changelog 內容>
EOF
)"
```

### 9b. 驗證 tag

```bash
git cat-file -p <tag-name>
```

確認 object、tag name、message 正確。

### 9c. Push tag

```bash
git push origin <tag-name>
```

若有需要也 push 分支（changelog commit）：

```bash
git push
```

---

## 步驟 10：回報結果

```
══════════════════════════════════
✅ Tag 已建立
══════════════════════════════════
Tag：       <tag-name>
Commit：    <hash>
CHANGELOG.md 已更新

GitLab tag 頁面：
<glab 輸出的連結，或提示使用者至 GitLab 查看>
══════════════════════════════════
```

---

## 規則

- **絕不在未與使用者確認前直接 push tag**。
- 版號必須遵循 semver（`vX.Y.Z`），不接受任意格式。
- **不得打在非 base branch 的分支上**（base branch 由 `git symbolic-ref refs/remotes/origin/HEAD` 推斷，fallback 為 `main`）。若目前分支不符，停止並提示使用者切換分支。
- `CHANGELOG.md` 只更新，不重寫既有內容。
- 若 tag 已存在，告知使用者並停止，不覆寫。

## 錯誤處理

| 情況 | 處理方式 |
|------|---------|
| 無新 commit | 告知使用者，停止 |
| Tag 已存在 | 顯示現有 tag 內容，停止，不覆寫 |
| 不在 base_branch 上 | 停止，提示切換至正確分支 |
| git push 失敗 | 顯示錯誤，tag 已建立於本地，提示手動 push |
| 版號格式錯誤 | 顯示正確格式範例，停止 |
