---
name: code-review
description: 審查 git diff，驗證是否符合 Ticket 需求，依預設規則與專案自訂規則產出 tmp/<ticket-id>/review.md。每個問題標示等級（blocker/warning/nit）、檔案、行號、說明與修正建議。reviewer 完全唯讀，不得修改程式碼。
tools: ["Read", "Bash", "Glob", "Grep"]
---

# Code Review — 程式碼審查

對目前分支的變更進行系統性審查，產出結構化的審查報告。

## 使用方式

```
/code-review <ticket-id>
```

---

## 步驟 0：讀取 ticket-id

```bash
TICKET_ID="${ARGUMENTS:-}"
if [ -z "${TICKET_ID}" ]; then
  # AskUserQuestion: 請提供 ticket ID（例如 PROJ-123）
fi
mkdir -p "tmp/${TICKET_ID}"
```

輸出路徑為 `tmp/${TICKET_ID}/review.md`。

---

## 步驟 0.5：讀取需求文件

平行嘗試讀取以下來源，取得 Ticket 需求：

1. `tmp/${TICKET_ID}/requirements.md` — brainstorm 產出的需求摘要
2. `tmp/${TICKET_ID}/plan.md` — plan-writer 產出的實作計畫（含目標與範圍）

**若兩者皆不存在**：在報告的需求符合度區段標注「找不到需求文件，略過需求符合度驗證」，不阻擋後續步驟。

---

## 步驟 1：取得 diff

若呼叫方傳入 `working_dir`，所有 git 指令加上 `-C "${WORKING_DIR}"`；否則在當前目錄執行。

```bash
# WORKING_DIR 由呼叫方傳入（pipeline worktree 情境），未傳入時為 "."
GIT="git -C ${WORKING_DIR:-.}"

# 推斷 base branch：優先從 remote HEAD 取，fallback 為 main
BASE_BRANCH=$(${GIT} symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")

${GIT} diff $(${GIT} merge-base HEAD origin/${BASE_BRANCH})...HEAD --name-only
${GIT} diff $(${GIT} merge-base HEAD origin/${BASE_BRANCH})...HEAD --stat
```

**大型 diff 判斷**（取得 name-only 與 stat 後執行）：

```bash
CHANGED_FILES=$(${GIT} diff $(${GIT} merge-base HEAD origin/${BASE_BRANCH})...HEAD --name-only | wc -l)
CHANGED_LINES=$(${GIT} diff $(${GIT} merge-base HEAD origin/${BASE_BRANCH})...HEAD --stat | tail -1 | awk '{print $4+$6}')
```

- 若 `CHANGED_FILES > 30` 或 `CHANGED_LINES > 1000`：啟動**分批審查模式**（見步驟 1.5）
- 否則：一次取得完整 diff，繼續步驟 2

---

## 步驟 1.5：分批審查模式（僅大型 diff 觸發）

將變更檔案依邏輯分批，每批不超過 **10 個檔案** 或 **300 行 diff**：

**分批原則**：
- 優先依目錄分組（`internal/`、`api/`、`pkg/`、`cmd/` 等）
- 測試檔與對應的實作檔歸同一批
- 生成的程式碼（`*.pb.go`、`*_gen.go`、`vendor/`）單獨一批，僅做輕量審查（不套用 blocker 規則）

對每一批執行步驟 2～4，產生各批的臨時結果清單。

**合批規則**（所有批次完成後）：
- 任意批次中出現的 blocker → 納入最終報告的 Blocker 區段
- 重複路徑的問題以最嚴重等級為準
- warning 與 nit 去重（相同檔案+行號只保留一筆）

合批完成後，直接進入步驟 5 輸出報告。

---

## 步驟 2：讀取審查規則

平行讀取：
1. `skills/code-review/checklist.md` — 預設審查規則（本 plugin 提供）
2. `.pipeline/checklist.md` — 專案自訂規則（選用）

規則合併邏輯：
- 若 `.pipeline/checklist.md` **第一行**為 `override: true`：完全取代預設規則
- 否則：自訂規則**追加**到預設規則（預設行為）

---

## 步驟 2.5：讀取 Coding Style 參考

搜尋專案中的 coding style 規範：
1. `CLAUDE.md` — 若有命名慣例、錯誤處理方式、格式規定
2. `.pipeline/style_guide.md` — 專案 style guide（若存在）
3. 透過 `Glob` 找出非測試檔中最有代表性的 3-5 個既有實作檔案，作為 coding style 的隱性參考

Coding style 驗證重點：
- 命名慣例（變數、函式、型別）是否與既有程式碼一致
- 錯誤處理模式是否符合專案慣例（`if err != nil`、error wrapping、自訂 error type）
- 注釋風格（有無、格式）是否一致
- 檔案結構與模組分層是否符合專案規範

---

## 步驟 3：讀取檔案上下文

對每個變更檔案，採用漸進策略取得上下文：

1. 以 `git diff -U50` 取得 diff 片段與前後各 50 行的上下文
2. 若涉及介面定義、型別宣告、全域常數、init 函式等需要整體脈絡的情形，才使用 `Read` 讀取完整檔案

（分批模式下：每批分別執行此步驟，僅讀取該批次的檔案。）

---

## 步驟 4：需求符合度驗證

（僅在步驟 0.5 成功取得需求文件時執行）

對照需求文件，逐項確認實作是否覆蓋所有需求，記錄結果：

```
[covered]   <需求項目> — 已在 <檔案>:<行號> 實作
[missing]   <需求項目> — 找不到對應實作
[partial]   <需求項目> — 部分實作，缺少：<具體說明>
[extra]     <實作內容> — 超出需求範圍，可能產生非預期副作用
```

- `missing` 與 `partial` 視為 **blocker**，納入步驟 5 的 Blocker 區段。
- `extra` 視為 **warning**，納入 Warning 區段。

---

## 步驟 5：程式碼審查

依照審查規則逐項檢查每個變更。

**提出問題前，必須先確認問題確實存在**：
- 引用觸發問題的具體程式碼片段（行號 + 內容）
- 說明為何這段程式碼有問題（邏輯推導或測試路徑）
- 若無法從程式碼直接確認，不得提出該問題

每個發現記錄為以下格式：

```
[等級] 檔案路徑:行號 — 問題說明
證明：<觸發此問題的具體程式碼或情境>
建議：<具體修正方式>
```

等級定義：
- **blocker**：必須修正才能繼續，包含安全漏洞、資料正確性問題、會導致 panic 或資源洩漏的問題
- **warning**：強烈建議修正，但不阻擋流程（效能問題、邊界條件未處理）
- **nit**：次要建議（命名、格式、風格）

---

## 步驟 6：輸出報告

將報告寫入 `tmp/${TICKET_ID}/review.md`：

```markdown
---
stage: review
status: <若有任何 blocker 則為 blocked，否則為 passed>
created: <YYYY-MM-DD>
source: <繼承自 plan.md 的 source，若有>
---

# 程式碼審查報告

審查範圍：<base_branch>...HEAD
檢查規則：<預設規則 / 預設 + 專案自訂 / 專案自訂>
變更檔案數：X
發現問題：X 個阻擋項，X 個警告，X 個建議

---

## 需求符合度

> 來源：`tmp/<TICKET_ID>/requirements.md` / `tmp/<TICKET_ID>/plan.md` / 找不到需求文件

| 狀態 | 需求項目 | 說明 |
|------|----------|------|
| ✅ covered | <需求> | <檔案>:<行號> |
| ❌ missing | <需求> | 找不到對應實作 |
| ⚠️ partial | <需求> | 缺少：<說明> |
| ℹ️ extra | <實作> | 超出需求範圍 |

---

## 阻擋項（必須修正）

### [阻擋] <檔案>:<行號> — <問題標題>
<問題說明>

**建議修正**：<具體做法>

---

## 警告（建議修正）

### [警告] <檔案>:<行號> — <問題標題>
<問題說明>

**建議修正**：<具體做法>

---

## 建議（次要）

- [建議] `<檔案>:<行號>` — <說明>

---

## Coding Style

> 參考來源：<CLAUDE.md / .pipeline/style_guide.md / 既有程式碼推斷>

| 狀態 | 項目 | 說明 |
|------|------|------|
| ✅ consistent | <項目> | 與專案慣例一致 |
| ⚠️ inconsistent | <項目> | 與 <參考檔案> 的做法不同：<說明> |

---

## 審查結論

**裁定：通過 / 需修正**

<1-2 句總結>
```

---

## 規則

- **完全唯讀**：不得修改任何程式碼或設定檔。
- **必須閱讀完整檔案**，不可只看 diff 片段。
- 每個 blocker 必須包含具體的修正建議，不可只說「需要修正」。
- 若無任何發現，明確輸出「無發現問題」，不可留白。
