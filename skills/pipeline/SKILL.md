---
name: pipeline
description: 自動化單張 ticket 的完整開發流程：建立 git worktree 隔離實作環境，plan（多 agent 並行審查）→ implement（test-reviewer 預審）→ smoke-test（Docker + curl/Postman）→ code-review + security-scan → gitlab-mr。Feature branch 從 release/<fix_version> checkout，不影響本地工作目錄。
tools: ["Read", "Write", "Bash", "Glob", "Grep", "AskUserQuestion"]
---

# Pipeline — 全自動開發流程

單張 ticket 從計畫一路到 MR，所有程式碼變更在獨立的 git worktree 中進行。任一階段失敗即停止，說明原因後等待人工處理。

**前置條件**：`tmp/<ticket-id>/requirements.md` 必須存在。需求未確認時請先執行 `/brainstorm`。

## 使用方式

```
/pipeline TICKET-123
```

---

## 步驟 0：載入 Ticket

```bash
TICKET_ID="${ARGUMENTS:-}"
```

若未傳入 ticket ID，以 `AskUserQuestion` 詢問。

```bash
mkdir -p "tmp/${TICKET_ID}"
```

---

## 步驟 1：前置確認

確認 `tmp/${TICKET_ID}/requirements.md` 存在，否則立即停止：

```
❌ Pipeline 無法啟動

tmp/<ticket-id>/requirements.md 不存在。
請執行 /brainstorm 或手動建立 requirements.md 後再試。
```

讀取 requirements.md，嘗試自動解析 `fix_version`。

**若 fix_version 無法從 requirements.md 解析**，以 `AskUserQuestion` 詢問：「請提供 fix version（例：v1.2.0）：」

其餘資訊（目標分支、feature branch 名稱）自動產生，不詢問使用者：

```bash
FIX_VERSION="<使用者確認或自動解析的 fix_version>"
# short_desc 自動從 ticket 標題產生（3–5 個英文單字，底線連接，小寫）
FEATURE_BRANCH="${FIX_VERSION}/feat/${TICKET_ID}_${SHORT_DESC}"
BASE_BRANCH="release/${FIX_VERSION}"
WORKTREE_PATH="tmp/worktrees/${TICKET_ID}"
```

---

## 步驟 1.5：建立 Git Worktree

確認 base branch 存在：

```bash
git fetch origin "${BASE_BRANCH}" 2>/dev/null
if ! git ls-remote --heads origin "${BASE_BRANCH}" | grep -q "${BASE_BRANCH}"; then
  echo "❌ base branch '${BASE_BRANCH}' 不存在於 remote，請確認 fix_version 是否正確。"
  exit 1
fi
```

建立 worktree：

```bash
mkdir -p tmp/worktrees
git worktree remove "${WORKTREE_PATH}" --force 2>/dev/null || true
if ! git worktree add "${WORKTREE_PATH}" -b "${FEATURE_BRANCH}" "origin/${BASE_BRANCH}"; then
  echo "❌ worktree 建立失敗，停止 pipeline。"
  echo "請確認 base branch '${BASE_BRANCH}' 是否存在，以及 feature branch '${FEATURE_BRANCH}' 是否已被使用。"
  exit 1
fi
if [ ! -d "${WORKTREE_PATH}" ]; then
  echo "❌ worktree 目錄不存在（${WORKTREE_PATH}），停止 pipeline。"
  exit 1
fi
```

寫入 worktree 資訊供後續各階段讀取：

```bash
cat > "tmp/${TICKET_ID}/.worktree" <<EOF
path: ${WORKTREE_PATH}
branch: ${FEATURE_BRANCH}
base: ${BASE_BRANCH}
EOF
```

**後續所有程式碼操作在 `${WORKTREE_PATH}` 下執行；`tmp/${TICKET_ID}/` 交接檔保留在主 repo。**

---

## 步驟 2：執行各階段

---

### 階段 A：Plan（多 Agent 並行審查）

在主 repo 執行（不涉及 worktree）。

讀取 `tmp/${TICKET_ID}/requirements.md` 的 `complexity` 欄位（由 brainstorm 填寫）：

```bash
COMPLEXITY=$(grep '^complexity:' "tmp/${TICKET_ID}/requirements.md" | awk '{print $2}' || echo "medium")
```

**`complexity: low`** → 只執行 1 個 plan-writer agent（預設視角），直接輸出 `tmp/${TICKET_ID}/plan.md`，跳過 A.2 整合步驟。

**`complexity: medium` 或 `high`** → 並行執行 3 個 plan-writer agent：

**A.1 並行執行 3 個 plan-writer agent**，傳入相同的 ticket-id，附加不同視角：

- **Agent 1**：`perspective: default`，`output: tmp/${TICKET_ID}/plan-draft-1.md`
- **Agent 2**：`perspective: critical`，`output: tmp/${TICKET_ID}/plan-draft-2.md`
- **Agent 3**：`perspective: minimal`，`output: tmp/${TICKET_ID}/plan-draft-3.md`

**A.2 整合計畫**：
1. 以 plan-draft-1.md 為基礎
2. 將 plan-draft-2.md 中的遺漏/潛在問題納入風險表或影響範圍
3. 將 plan-draft-3.md 中標為「可 defer」的項目移入「排除」區段並備注原因
4. 生成 `tmp/${TICKET_ID}/plan.md`，frontmatter 加入：`reviewed_by: plan-draft-1, plan-draft-2, plan-draft-3`

**A.3 判斷是否需要 API schema**

讀取 `tmp/${TICKET_ID}/plan.md` 的「API 變更」區段：
- 有任何端點的新增、刪除、路徑變更、請求/回應欄位變更 → 自動執行 `/api-schema ${TICKET_ID}`，輸出 `schema.md`
- 確認完全無 API 異動 → 跳過

---

### 階段 B：Implement（TDD + 自動測試預審）

**進入前驗證**：讀取 `tmp/${TICKET_ID}/.worktree`，確認 `path:` 欄位的目錄存在，否則立即停止（`❌ worktree 不存在，請重新執行 pipeline`）。

**所有程式碼操作在 `${WORKTREE_PATH}` 執行。**

**B.1 test-writer agent**

依 implement skill（`skills/implement/SKILL.md`）步驟 0～2 執行（語言偵測、test-writer agent、取得 test-report.md），傳入：
- `working_dir: ${WORKTREE_PATH}`
- `artifact_dir: tmp/${TICKET_ID}`

**B.2 test-reviewer agent 預審**

以 **test-reviewer** agent 執行，傳入 ticket-id、`paths.test`、`working_dir: ${WORKTREE_PATH}`。

等待 test-reviewer 寫入 `tmp/${TICKET_ID}/test-review.md`，讀取 `verdict`：

**`verdict: auto`** → 直接進入實作，不詢問使用者。

**`verdict: human`** → 以 `AskUserQuestion` 顯示 test-review.md 的「人工審查建議」區段，請使用者選擇：
1. 確認通過 — 繼續實作
2. 重跑測試 — 要求 test-writer 修正（最多 2 次，仍需人工確認後再繼續）

**B.3 implementer agent**

依 implement skill 步驟 3～5 執行（implementer agent → 測試檔不可變驗證 → 覆蓋率驗證），傳入：
- `working_dir: ${WORKTREE_PATH}`
- `artifact_dir: tmp/${TICKET_ID}`

implementer 重試超過 3 次仍無法通過 → 停止（`blocked-impl`），保留 worktree 供偵錯。

---

### 階段 C：Smoke Test

**進入前驗證**：讀取 `tmp/${TICKET_ID}/.worktree`，取得 `WORKTREE_PATH`、`FEATURE_BRANCH`、`BASE_BRANCH`。確認 `path:` 欄位的目錄存在，否則立即停止（`❌ worktree 不存在，請重新執行 pipeline`）。

依照 **smoke-test** skill（`skills/smoke-test/SKILL.md`）完整流程執行，傳入：
- `working_dir: ${WORKTREE_PATH}`

讀取 `tmp/${TICKET_ID}/smoke.md` 的 `status`：
- `passed` / `partial` → 繼續
- `failed` → 自動修復循環（最多 2 輪）：
  1. 分析 smoke.md 失敗詳情，推斷是實作問題還是 seed 資料問題
  2. seed 資料問題：修正 `seeds.sql` 後重新執行 smoke-test
  3. 實作問題：以 implementer agent 修正（`working_dir: ${WORKTREE_PATH}`）後重新執行 smoke-test
  4. 2 輪後仍失敗 → 停止（`blocked-smoke`），保留 worktree 供偵錯

---

### 階段 D：Code Review + Security Scan（並行）

**進入前驗證**：讀取 `tmp/${TICKET_ID}/.worktree`，取得 `WORKTREE_PATH`、`FEATURE_BRANCH`、`BASE_BRANCH`。確認 `path:` 欄位的目錄存在，否則立即停止（`❌ worktree 不存在，請重新執行 pipeline`）。

依照 **code-review** skill 與 **security-scan** skill 完整流程執行，diff 來源：

```bash
git -C "${WORKTREE_PATH}" diff "origin/${BASE_BRANCH}"...HEAD
```

傳入：
- `working_dir: ${WORKTREE_PATH}`
- `base_branch: origin/${BASE_BRANCH}`

**兩份報告均無 blocker**（`passed`）→ 繼續覆蓋率重驗後進入階段 E。

**有 blocker** → 自動修復循環（最多 2 輪）：
1. 以 implementer agent 修正（傳入 blocker 清單）
2. 修正後重新執行階段 C（smoke-test）與階段 D
3. 2 輪後仍有 blocker → 停止（`blocked-review`），列出未解決的 blocker，保留 worktree

**覆蓋率重驗**（code-review 無 blocker 後執行）：

```bash
# 以修復前的覆蓋率基準值（來自 implement 階段寫入的 .coverage-baseline）比對
BASELINE=$(cat "tmp/${TICKET_ID}/.coverage-baseline" 2>/dev/null || echo "0")
PACKAGES=$(git -C "${WORKTREE_PATH}" diff "origin/${BASE_BRANCH}"...HEAD --name-only \
  | grep '\.go$' | grep -v '_test\.go$' \
  | xargs -I{} dirname {} | sort -u | sed 's|^|./|' | tr '\n' ',' | sed 's/,$//')

go -C "${WORKTREE_PATH}" test -coverprofile="tmp/${TICKET_ID}/.coverage-recheck.out" \
  -coverpkg="${PACKAGES}" ./... 2>/dev/null
CURRENT=$(go tool cover -func="tmp/${TICKET_ID}/.coverage-recheck.out" | grep "^total:" | awk '{print $3}' | tr -d '%')

if awk "BEGIN {exit !($CURRENT < $BASELINE - 2)}"; then
  echo "❌ 覆蓋率退步：修復前 ${BASELINE}%，現在 ${CURRENT}%，停止流程。"
  exit 1
fi
```

---

### 階段 E：建立 MR

**進入前驗證**：讀取 `tmp/${TICKET_ID}/.worktree`，取得 `WORKTREE_PATH`、`FEATURE_BRANCH`、`BASE_BRANCH`。確認 `path:` 欄位的目錄存在，否則立即停止（`❌ worktree 不存在，請重新執行 pipeline`）。

```bash
git -C "${WORKTREE_PATH}" push -u origin "${FEATURE_BRANCH}"
```

依照 **gitlab-mr** skill 完整流程執行，傳入：
- `working_dir: ${WORKTREE_PATH}`
- `source_branch: ${FEATURE_BRANCH}`
- `target_branch: ${BASE_BRANCH}`

MR 標題格式：直接使用 `${FEATURE_BRANCH}`（分支名稱）。

---

## 步驟 3：清理與完成

MR 建立成功後，讀取 `tmp/${TICKET_ID}/.worktree` 取得 `WORKTREE_PATH`，移除 worktree：

```bash
git worktree remove "${WORKTREE_PATH}" --force
```

顯示完成訊息：

```
══════════════════════════════════
✅ Pipeline 完成 — <ticket-id>
══════════════════════════════════
Feature branch：<FEATURE_BRANCH>
Base branch：<BASE_BRANCH>
MR：<MR URL>

下一步：人工 review 並 merge。
══════════════════════════════════
```

---

## 狀態定義

| 狀態 | 說明 |
|------|------|
| `planning` | 執行 plan-writer（多 agent） |
| `implementing` | 執行 test-writer + implementer |
| `smoke-testing` | 執行 smoke-test |
| `reviewing` | 執行 code-review + security-scan |
| `creating-mr` | push feature branch + 執行 gitlab-mr |
| `done` | 完成，worktree 已清除，MR 已建立 |
| `blocked-impl` | implementer 重試超限，worktree 保留 |
| `blocked-smoke` | smoke-test 自動修復失敗，worktree 保留 |
| `blocked-review` | review/security blocker 未解決，worktree 保留 |

---

## 規則

- 所有程式碼變更在 `tmp/worktrees/<ticket-id>/` worktree 執行，不修改主工作目錄。
- Feature branch 必須從 `origin/release/<fix_version>` checkout，不得從 main 或其他分支建立。
- 自動修復循環上限：smoke = 2 輪，review/security = 2 輪，impl = 3 次。
- 人工關卡僅在 `verdict: human` 時觸發，`verdict: auto` 時完全跳過。
- 任一階段 blocked，立即停止，worktree 保留供偵錯，不自動清除。
- 不得自動 merge MR，merge 由人工在 GitLab 操作。