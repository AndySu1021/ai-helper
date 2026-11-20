---
name: pipeline
description: 自動化單張 ticket 的完整開發流程：建立 git worktree 隔離實作環境，plan（多 agent 並行審查）→ implement（test-reviewer 預審）→ smoke-test（Docker + curl/Postman）→ code-review + security-scan → gitlab-mr。Feature branch 從 release/<fix_version> checkout，不影響本地工作目錄。
tools: ["Read", "Write", "Bash", "AskUserQuestion"]
---

# Pipeline — 全自動開發流程

單張 ticket 從計畫一路到 MR。所有程式碼變更在獨立的 git worktree 中進行，不影響本地工作目錄。任一階段失敗即停止，等待人工處理後重新執行。

**前置條件**：需求必須已確認完畢，`tmp/<ticket-id>/requirements.md` 必須存在。需求尚未釐清時，請先執行 `/brainstorm`，不屬於本流程範圍。

## 使用方式

```
/pipeline TICKET-123
```

---

## 步驟 0：載入 Ticket

```bash
TICKET_ID="<使用者傳入的 ticket ID>"
echo "${TICKET_ID}" > tmp/.current-ticket
```

若未傳入 ticket ID，使用 `AskUserQuestion` 詢問：「請提供要執行的 ticket ID。」

---

## 步驟 1：前置確認

確認 `tmp/${TICKET_ID}/requirements.md` 存在。若不存在，立即停止並回報：

```
❌ Pipeline 無法啟動

tmp/<ticket-id>/requirements.md 不存在。

需求必須先確認才能進入 Pipeline。
請執行 /brainstorm 或手動建立 requirements.md 後再試。
```

讀取 requirements.md 的「目標」欄位，同時從 requirements.md 嘗試解析 `fix_version`（`source` 欄位或內文中的 fix version 資訊）。

使用 `AskUserQuestion` 一次詢問以下資訊：

```
══════════════════════════════════
Pipeline 確認 — <ticket-id>
══════════════════════════════════
目標：<requirements.md 的目標欄位>

預計步驟：plan-writer → implement → smoke-test → code-review + security-scan → gitlab-mr

請確認以下資訊：
1. Fix version（例：v1.2.0）：<自動解析的值，若無法解析則留空請填寫>
2. 分支描述（short_desc，英文小寫 + 底線，例：add_user_auth）：

產生的 feature branch：<fix_version>/feat/<ticket-id>_<short_desc>
Base branch：release/<fix_version>

回覆「確認」或提供修正後的值。
══════════════════════════════════
```

確認後儲存：
```bash
FIX_VERSION="<使用者確認的 fix_version>"
SHORT_DESC="<使用者確認的 short_desc>"
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

# 若先前有殘留的同名 worktree，先清除
git worktree remove "${WORKTREE_PATH}" --force 2>/dev/null || true

git worktree add "${WORKTREE_PATH}" -b "${FEATURE_BRANCH}" "origin/${BASE_BRANCH}"
```

建立後將 worktree 資訊寫入 `tmp/${TICKET_ID}/.worktree`，供後續各階段讀取：

```bash
cat > "tmp/${TICKET_ID}/.worktree" <<EOF
path: ${WORKTREE_PATH}
branch: ${FEATURE_BRANCH}
base: ${BASE_BRANCH}
EOF
```

**後續所有程式碼操作（test-writer、implementer、smoke-test、code-review）均在 `${WORKTREE_PATH}` 下執行，pipeline 的 `tmp/${TICKET_ID}/` 交接檔仍保留在主 repo。**

---

## 步驟 2：執行各階段

---

### 階段 A：Plan（多 Agent 並行審查）

此階段在主 repo 執行（讀寫 `tmp/${TICKET_ID}/`），不涉及 worktree。

**A.1 並行執行 3 個 plan-writer agent**，傳入相同的 requirements.md，附加不同視角 prompt：

- **Agent 1（預設視角）**：依 plan-writer SKILL.md 標準流程執行，輸出至 `tmp/${TICKET_ID}/plan-draft-1.md`
- **Agent 2（批判視角）**：執行同樣流程，額外要求：「在每個影響範圍與風險項目，以質疑的角度指出遺漏與潛在問題」，輸出至 `tmp/${TICKET_ID}/plan-draft-2.md`
- **Agent 3（簡化視角）**：執行同樣流程，額外要求：「以最小實作範圍的原則���刪去非必要步驟，指出哪些計畫項目可以 defer」，輸出至 `tmp/${TICKET_ID}/plan-draft-3.md`

**A.2 整合計畫**（3 個 agent 完成後）

讀取 3 份草稿，執行以下整合邏輯：
1. 以 plan-draft-1.md 為基礎
2. 將 plan-draft-2.md 中標為「遺漏」或「潛在問題」的項目，納入風險表或影響範圍
3. 將 plan-draft-3.md 中標為「可 defer」的項目，移入「排除」區段並備注原因
4. 生成最終 `tmp/${TICKET_ID}/plan.md`，frontmatter 加入：`reviewed_by: plan-draft-1, plan-draft-2, plan-draft-3`

**A.3 判斷是否需要 API schema**

讀取 `tmp/${TICKET_ID}/plan.md` 的「API 變更」區段：
- 若有任何端點列出（非「無」）→ 自動執行 `/api-schema`，輸出 `tmp/${TICKET_ID}/schema.md`
- 若無 API 變更 → 跳過此步驟

---

### 階段 B：Implement（TDD + 自動測試預審）

**所有程式碼操作在 `${WORKTREE_PATH}` 執行。** `tmp/${TICKET_ID}/` 交接檔仍寫入主 repo。

**B.1 test-writer agent**

依 `/implement` SKILL.md 的步驟 0～2 執行（語言偵測、test-writer agent 執行、取得 test-report.md）。

傳入額外參數：
- `working_dir: ${WORKTREE_PATH}` — test-writer 在此目錄讀寫測試檔案
- `artifact_dir: tmp/${TICKET_ID}` — test-report.md 寫入主 repo 的交接目錄

**B.2 test-reviewer agent 預審**

以 **test-reviewer** agent 執行，傳入：
- ticket-id
- `paths.test`（由語言推斷）
- `working_dir: ${WORKTREE_PATH}`

等待 test-reviewer 寫入 `tmp/${TICKET_ID}/test-review.md`。

讀取 `verdict`：

**若 `verdict: auto`**：
```
✅ 測試自動放行（test-reviewer 確認覆蓋率完整）
   跳過人工確認，直接進入實作。
```

**若 `verdict: human`**：
顯示以下訊息後使用 `AskUserQuestion` 等待確認：

```
══════════════════════════════════
人工關卡：測試需要確認 — <ticket-id>
══════════════════════════════════
test-reviewer 發現以下問題需要人工判斷：

<test-review.md 的「人工審查建議」區段內容>

請審閱：tmp/<ticket-id>/test-report.md
測試檔位置：<WORKTREE_PATH>

選擇：
  1. 確認通過 — 繼續實作
  2. 重跑測試 — 要求 test-writer 修正後重新審查
══════════════════════════════════
```

若選擇「重跑測試」，重新執行 test-writer → test-reviewer，最多 2 次，仍需人工確認後再繼續。

**B.3 implementer agent**

依 `/implement` SKILL.md 的步驟 3～5 執行（implementer agent → 測試檔不可變驗證 → 覆蓋率驗證）。

傳入額外參數：
- `working_dir: ${WORKTREE_PATH}`
- `artifact_dir: tmp/${TICKET_ID}`

若 implementer 重試超過上限（max_impl_retry = 3），停止並回報：

```
❌ Pipeline 中止 — blocked-impl

implementer 已重試 3 次仍無法通過測試。
請人工介入後重新執行 /pipeline。

Worktree 路徑：<WORKTREE_PATH>（保留供偵錯，請手動執行 git worktree remove 清除）
交接檔：tmp/<ticket-id>/
```

---

### 階段 C：Smoke Test

執行 `/smoke-test` SKILL.md 完整流程。

傳入額外參數：
- `working_dir: ${WORKTREE_PATH}` — smoke-test 在此目錄尋找 docker-compose 設定

讀取 `tmp/${TICKET_ID}/smoke.md` 的 `status`：
- `passed` / `partial` → 繼續
- `failed` → **自動修復循環**（最多 2 輪）：
  1. 分析 smoke.md 的失敗詳情，推斷是實作問題還是 seed 資料問題
  2. 若是 seed 資料問題：修正 `tmp/${TICKET_ID}/seeds.sql` 後重新執行 smoke-test
  3. 若是實作問題：回到 implementer agent（`working_dir: ${WORKTREE_PATH}`，不需重跑測試），修正後重新執行 smoke-test
  4. 2 輪後仍失敗 → 停止並回報：

```
❌ Pipeline 中止 — blocked-smoke

Smoke test 自動修復 2 輪後仍失敗。
請查看 tmp/<ticket-id>/smoke.md 失敗詳情，人工修正後重新執行 /pipeline。

Worktree 路徑：<WORKTREE_PATH>（保留供偵錯）
```

---

### 階段 D：Code Review + Security Scan（並行）

**並行執行**，diff 來源為 worktree 的 feature branch：

```bash
# 在 worktree 內取得相對於 base branch 的 diff
cd "${WORKTREE_PATH}" && git diff "origin/${BASE_BRANCH}"...HEAD
```

- `/code-review` → `tmp/${TICKET_ID}/review.md`
- `/security-scan` → `tmp/${TICKET_ID}/security.md`

傳入額外參數：
- `working_dir: ${WORKTREE_PATH}`
- `base_branch: origin/${BASE_BRANCH}`

等待兩者完成後讀取結果：

**若兩份報告均無 blocker** → 繼續階段 E

**若有 blocker** → **自動修復循環**（最多 2 輪）：
1. 讀取所有 blocker 項目
2. 以 implementer agent 修正（`working_dir: ${WORKTREE_PATH}`，傳入 review.md 與 security.md 的 blocker 清單）
3. 修正後重新執行階段 C（smoke-test）與階段 D（review + security）
4. 2 輪後仍有 blocker → 停止並回報：

```
❌ Pipeline 中止 — blocked-review

以下 blocker 在 2 輪自動修復後仍未解決：
<未解決的 blocker 清單>

請查看 tmp/<ticket-id>/review.md 與 tmp/<ticket-id>/security.md，人工修正後重新執行 /pipeline。

Worktree 路徑：<WORKTREE_PATH>（保留供偵錯）
```

---

### 階段 E：建立 MR

在 worktree 內 push feature branch：

```bash
cd "${WORKTREE_PATH}"
git push -u origin "${FEATURE_BRANCH}"
```

執行 `/gitlab-mr` SKILL.md 完整流程，傳入：
- `working_dir: ${WORKTREE_PATH}`
- `source_branch: ${FEATURE_BRANCH}`
- `target_branch: ${BASE_BRANCH}`（即 `release/<fix_version>`）

Jira ticket ID 自動從 `${TICKET_ID}` 取得，不再詢問。MR 標題格式：`${TICKET_ID}: <簡短描述>`。

---

## 步驟 3：清理與完成

MR 建立成功後，移除 worktree（程式碼已 push 至 remote，本地 worktree 不再需要）：

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
| `implementing` | 執行 test-writer + implementer（worktree 內） |
| `smoke-testing` | 執行 smoke-test（worktree 內） |
| `reviewing` | 執行 code-review + security-scan（worktree diff） |
| `creating-mr` | push feature branch + 執行 gitlab-mr |
| `done` | 完成，worktree 已清除，MR 已建立 |
| `blocked-impl` | implementer 重試超限，worktree 保留供偵錯 |
| `blocked-smoke` | smoke-test 自動修復失敗，worktree 保留供偵錯 |
| `blocked-review` | review/security blocker 未解決，worktree 保留供偵錯 |

---

## 規則

- 所有程式碼變更在 `tmp/worktrees/<ticket-id>/` worktree 執行，不修改主工作目錄的任何檔案。
- Pipeline 交接檔（plan.md、review.md 等）保留在主 repo 的 `tmp/<ticket-id>/`。
- Feature branch 必須從 `origin/release/<fix_version>` checkout，不得從 main 或其他分支建立。
- 任一階段 blocked，立即停止並清楚說明原因，worktree 保留供偵錯，不自動清除。
- 自動修復循環上限：smoke = 2 輪，review/security = 2 輪，impl = 3 次（由 implement SKILL 控制）。
- 人工關卡（測試確認）僅在 `verdict: human` 時觸發，`verdict: auto` 時完全跳過。
- 不得自動 merge MR，merge 由人工在 GitLab 操作。
