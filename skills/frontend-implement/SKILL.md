---
name: frontend-implement
description: 前端 React TDD 實作流程。frontend-test-writer agent 先撰寫失敗測試，人工確認後 frontend-implementer agent 寫實作，直到所有測試通過，並包含視覺確認人工關卡。test-writer 與 implementer 分開執行，測試檔案不可被 implementer 修改。從 requirements.md 開始，不需要先執行 plan-writer。
tools: ["Read", "Write", "Bash", "Glob", "Grep", "AskUserQuestion"]
---

# Frontend Implement — React TDD 實作

以 TDD 方式進行前端 React 功能實作。**frontend-test-writer 與 frontend-implementer 是分開的 agent**，職責嚴格隔離。

## 使用方式

```
/frontend-implement <ticket-id>
```

執行前，`tmp/<ticket-id>/requirements.md` 必須已存在。

---

## 步驟 0：讀取 ticket-id 與專案設定

```bash
TICKET_ID="${ARGUMENTS:-}"
if [ -z "${TICKET_ID}" ]; then
  # AskUserQuestion: 請提供 ticket ID（例如 PROJ-123）
fi
mkdir -p "tmp/${TICKET_ID}"
```

**偵測測試框架**：

```bash
PKG_JSON=$(find . -maxdepth 3 -name "package.json" ! -path "*/node_modules/*" | head -1)

if grep -q '"vitest"' "${PKG_JSON}" 2>/dev/null; then
  TEST_COMMAND="npx vitest run"
  TEST_GLOB="**/*.{test,spec}.{ts,tsx}"
elif grep -q '"jest"' "${PKG_JSON}" 2>/dev/null; then
  TEST_COMMAND="npx jest --passWithNoTests"
  TEST_GLOB="**/*.{test,spec}.{ts,tsx,js,jsx}"
else
  TEST_COMMAND="npx vitest run"
  TEST_GLOB="**/*.{test,spec}.{ts,tsx}"
fi

IMPL_GLOB="src/**/*.{ts,tsx}"
MAX_IMPL_RETRY=3
```

**偵測 CSS 框架**：

```bash
if grep -q '"tailwindcss"' "${PKG_JSON}" 2>/dev/null; then
  CSS_FRAMEWORK="tailwind"
elif grep -q '"styled-components"' "${PKG_JSON}" 2>/dev/null; then
  CSS_FRAMEWORK="styled-components"
elif grep -q '"@emotion' "${PKG_JSON}" 2>/dev/null; then
  CSS_FRAMEWORK="emotion"
else
  CSS_FRAMEWORK="css-modules"  # 預設
fi
```

讀取 `min_coverage` 覆蓋邏輯：

```bash
PLAN_COVERAGE=$(grep '^min_coverage:' "tmp/${TICKET_ID}/requirements.md" 2>/dev/null | awk '{print $2}')
MIN_COVERAGE=${PLAN_COVERAGE:-80}
```

---

## 步驟 1：前置確認

確認 `tmp/${TICKET_ID}/requirements.md` 存在，否則立即停止：

```
❌ Frontend Implement 無法啟動

tmp/<ticket-id>/requirements.md 不存在。
請執行 /brainstorm 或手動建立 requirements.md 後再試。
```

讀取 `tmp/${TICKET_ID}/requirements.md`，了解功能範圍。

若存在 `tmp/${TICKET_ID}/plan.md`，同時讀取作為補充上下文（非必要）。

**偵測設計參考（優先序）**：

依序檢查以下來源，取第一個存在的：

1. `tmp/${TICKET_ID}/design_direction.md` — prototype-pipeline 產出的設計方向（含配色、字體、CSS 變數）
2. `prototype/` 目錄 — 本地 HTML/CSS prototype
3. requirements.md 中的 `figma_url:` 欄位 — Figma 設計稿連結

```bash
if [ -f "tmp/${TICKET_ID}/design_direction.md" ]; then
  DESIGN_REF="design_direction"
  DESIGN_REF_PATH="tmp/${TICKET_ID}/design_direction.md"
elif [ -d "prototype" ]; then
  DESIGN_REF="prototype"
  DESIGN_REF_PATH="prototype/"
else
  FIGMA_URL=$(grep '^figma_url:' "tmp/${TICKET_ID}/requirements.md" 2>/dev/null | awk '{print $2}')
  if [ -n "${FIGMA_URL}" ]; then
    DESIGN_REF="figma"
    DESIGN_REF_PATH="${FIGMA_URL}"
  else
    DESIGN_REF="none"
    DESIGN_REF_PATH=""
  fi
fi
```

**若 `DESIGN_REF="none"`**，以 `AskUserQuestion` 詢問：

```
未偵測到設計參考。是否有以下任一項可提供？

1. Figma 設計稿 URL
2. prototype/ 目錄（本地 HTML 原型）
3. design_direction.md（設計方向文件）
4. 無設計稿，僅依 requirements.md 實作功能（樣式自行決定）

請輸入選項編號或直接貼上 Figma URL：
```

- 使用者提供 → 儲存至對應位置，更新 `DESIGN_REF` 與 `DESIGN_REF_PATH`
- 使用者選 4 → `DESIGN_REF="none"`，繼續執行，implementer 自行決定視覺樣式
- 任何情況都不阻擋流程

---

## 步驟 2：測試撰寫（frontend-test-writer agent）

記錄測試基準點：

```bash
git rev-parse HEAD > "tmp/${TICKET_ID}/.test-baseline"
```

以 **frontend-test-writer** agent 執行，傳入：
- `tmp/${TICKET_ID}/requirements.md`
- `tmp/${TICKET_ID}/plan.md`（若存在）
- ticket-id
- `TEST_GLOB`、`TEST_COMMAND`

frontend-test-writer 完成後執行以下驗證：

```bash
# 1. 確認 test-report.md 已產生
[ -f "tmp/${TICKET_ID}/test-report.md" ] || { echo "ERROR: test-report.md 未產生"; exit 1; }

# 2. 確認有實際的測試檔案被寫入（相較基準點有新增或修改）
TEST_BASELINE=$(cat "tmp/${TICKET_ID}/.test-baseline")
CHANGED_TEST_FILES=$(git diff --name-only "${TEST_BASELINE}" -- "*.test.ts" "*.test.tsx" "*.spec.ts" "*.spec.tsx")
if [ -z "${CHANGED_TEST_FILES}" ]; then
  echo "ERROR: frontend-test-writer 未產生任何測試檔案。請重新執行。"
  exit 1
fi
echo "測試檔案已產生：${CHANGED_TEST_FILES}"
```

若驗證失敗，重新執行 frontend-test-writer agent。

**test-reviewer 預審**：

以 **test-reviewer** agent 執行，傳入 ticket-id、`TEST_GLOB`。等待 test-reviewer 寫入 `tmp/${TICKET_ID}/test-review.md`，讀取 `verdict`：

**`verdict: auto`** → 直接進入實作，不詢問使用者。

**`verdict: human`** → 顯示人工關卡：

```
══════════════════════════════════
人工關卡：測試確認
══════════════════════════════════
測試撰寫完成，請審閱：

tmp/<ticket-id>/test-report.md
tmp/<ticket-id>/test-review.md（審查建議）

確認以下事項：
- 測試案例是否涵蓋 requirements.md 中所有需求
- 元件 render、props、互動事件是否齊全
- 非同步行為（API call、loading/error state）是否有測試
- 測試失敗原因是否正確（元件未實作，非語法錯誤）

回覆「確認」繼續，或說明需要調整的測試。
══════════════════════════════════
```

使用 `AskUserQuestion` 等待確認。若使用者要求調整，重新執行 frontend-test-writer agent（最多 2 次，仍需人工確認後再繼續）。

---

## 步驟 3：實作（frontend-implementer agent）

以 **frontend-implementer** agent 執行，傳入：
- `tmp/${TICKET_ID}/requirements.md`
- `tmp/${TICKET_ID}/plan.md`（若存在）
- ticket-id
- `TEST_GLOB`、`IMPL_GLOB`、`TEST_COMMAND`
- `CSS_FRAMEWORK`
- `DESIGN_REF`、`DESIGN_REF_PATH`（告知設計參考來源與路徑）

---

## 步驟 4：測試檔不可變驗證

frontend-implementer 完成後執行：

```bash
TEST_BASELINE=$(cat "tmp/${TICKET_ID}/.test-baseline")
git diff --name-only "${TEST_BASELINE}" -- "*.test.ts" "*.test.tsx" "*.spec.ts" "*.spec.tsx"
```

若 `.test-baseline` 不存在或為空，停止並回報：「測試基準點遺失，請從步驟 2 重新執行。」

若輸出非空（測試檔被修改）：
- 顯示錯誤：「測試檔案已被修改，請人工確認後從步驟 2 重新執行。」
- 停止，不可自動繼續。

---

## 步驟 5：覆蓋率驗證

執行測試並收集覆蓋率（需 vitest coverage 或 jest --coverage）：

```bash
# vitest
npx vitest run --coverage --reporter=json 2>/dev/null \
  && COVERAGE=$(cat coverage/coverage-summary.json 2>/dev/null \
      | grep -o '"pct":[0-9.]*' | head -1 | grep -o '[0-9.]*')

[ -z "${COVERAGE}" ] && COVERAGE="N/A"
echo "${COVERAGE}" > "tmp/${TICKET_ID}/.coverage-baseline"
```

**計數器**：`impl_retry_count`（初始為 0）

若覆蓋率 < `min_coverage` 且覆蓋率非 N/A：
- `impl_retry_count += 1`
- 若 `impl_retry_count >= MAX_IMPL_RETRY`：停止，提示人工介入。
- 否則顯示：「測試覆蓋率不足（目前 X%，要求 ≥ N%），請補充測試後重新實作。」，回到步驟 2 test-reviewer 預審。

若測試失敗（非覆蓋率問題）：
- `impl_retry_count += 1`
- 若 `impl_retry_count >= MAX_IMPL_RETRY`：停止，提示人工介入。
- 否則回到 frontend-implementer agent 重新實作。

---

## 步驟 5.5：視覺確認（人工關卡）

測試與覆蓋率均通過後，**若 `DESIGN_REF != "none"`**，顯示視覺確認關卡：

```
══════════════════════════════════
人工關卡：視覺確認
══════════════════════════════════
功能測試已全部通過。請啟動 dev server 目視確認 UI 是否符合設計。

設計參考：<DESIGN_REF_PATH>

啟動方式（請依專案調整）：
  npm run dev  /  yarn dev  /  pnpm dev

確認以下事項：
- 整體版面與設計參考一致（間距、排版、色彩）
- 互動狀態正確（hover、focus、disabled、loading、error）
- 文字內容與 requirements 吻合
- RWD/斷點行為符合預期

回覆「確認」繼續，或描述需要調整的視覺問題。
══════════════════════════════════
```

使用 `AskUserQuestion` 等待確認。

若使用者回報視覺問題：
- 將問題描述傳給 **frontend-implementer** agent，要求修正樣式（不重跑測試撰寫階段）
- 修正後重新顯示此視覺確認關卡
- 最多循環 3 次；超過時停止，提示人工接手

**若 `DESIGN_REF="none"`**：跳過此關卡，直接進入步驟 6。

---

## 步驟 6：完成

實作通過後輸出：

```
══════════════════════════════════
✅ 前端實作完成
══════════════════════════════════
所有測試通過，覆蓋率：<X%>
視覺確認：<已確認 / 無設計參考（略過）>

建議後續步驟：
  /ui-ux-review     UI/UX 審查
  /code-review      程式碼審查
  /security-scan    安全掃描

交接檔：tmp/<ticket-id>/
══════════════════════════════════
```

---

## 規則

- requirements.md 必須存在才可執行。
- 人工關卡（測試確認、視覺確認）不可跳過。
- 測試檔被修改時必須停止，不可繼續。
- 覆蓋率與測試失敗的 retry 上限各自獨立計算。
- 覆蓋率為 N/A（專案未設定 coverage reporter）時，只要測試全部通過即視為通過。
- 有設計參考時，視覺確認為必要關卡；`DESIGN_REF="none"` 時才可略過。
