# Changelog

版本格式遵循 [Semantic Versioning](https://semver.org/)：
- **MAJOR**：設定格式或交接檔格式不相容的變更
- **MINOR**：新增 skill、agent 或設定選項
- **PATCH**：修正 bug、調整規則文字

---

## [1.2.0] — 2026-11-23

### 修正

- **skills/bugfix**：重寫 root cause 驗證機制，以 reproduction test 取代純靜態推斷：
  - 新增 Phase 1–5 結構（理解症狀 → 形成假設 → 驗證假設 → 修復 → 審查）
  - 新增閘門 G1：非確定性 bug（flaky / prod-only）強制停止，不進入自動修復
  - 新增閘門 G2：非程式 bug 停止（原有邏輯，明確化）
  - 新增閘門 G3：假設無法表達為可驗證條件時停止
  - 新增步驟 6：Reproduction test — 在不改任何實作的前提下執行，FAIL（runtime assertion）才確認假設，PASS 代表假設被推翻
  - 新增閘門 G4：reproduction test PASS 時嘗試次優假設，最多 2 次仍 PASS 則停止交人工
  - `plan.md` 新增 `hypothesis_verified` 欄位與 Root Cause 假設區段（含可驗證條件、排除假設）
  - MR description 強制包含驗證過的 root cause 與 reproduction test 位置
  - 狀態定義新增 `stopped-g1`、`stopped-g2`、`stopped-g3`、`stopped-g4`

- **skills/security-scan**：工具未安裝行為從「繼續並標記 passed-incomplete」改為「停止並要求安裝」：
  - gitleaks / semgrep 缺少時立即停止，顯示安裝指令（semgrep 改為 `brew install semgrep`）
  - 移除 `passed-incomplete` status，security.md 只剩 `passed` 與 `blocked`

- **skills/pipeline**：移除 D 階段中 `passed-incomplete` 視為通過的例外邏輯
- **skills/gitlab-mr**：移除 `passed-incomplete` 相關的停止判斷與錯誤處理表列

---

## [1.1.0] — 2026-11-23

### 新功能

- **skills/bugfix**：重寫為完整自動化流程，整合 TDD 實作、Code Review 循環與 MR 提交，對齊 pipeline 的設計模式：
  - 新增步驟 5（TDD 實作）：test-writer agent → 人工確認測試 → implementer agent → 覆蓋率驗證
  - 新增步驟 6（Code Review + Security Scan 並行）：自動修復循環，最多 2 輪，blocker 未解決則停止
  - 新增步驟 7（提交 MR）：push bug branch + gitlab-mr skill
  - 新增問題非 bug 時立即終止（使用者操作問題、外部依賴問題）
  - 新增狀態定義表，對應各階段卡住時的錯誤代碼

---

## [1.0.0] — 2026-11-21

### 破壞性變更 ⚠️

- **移除共享狀態 `tmp/.current-ticket`**：所有 skill 與 agent 不再讀寫此檔案，改由呼叫方透過 `$ARGUMENTS` 明確傳入 ticket-id，支援多個 Claude CLI 並行執行不同 ticket。
- 所有 skill 指令語法改為 `/skill-name <ticket-id>`（`/release-tag`、`/review-mr`、`/bugfix` 原本即帶參數，不受影響）。

### 升級說明

若目標專案有任何腳本或說明文件引用 `tmp/.current-ticket`，請一併移除。

---

## [0.3.0] — 2026-11-13

### 新功能

- **skills/mr-review**：新增需求符合度驗證。從 MR 標題、描述、commit 訊息、分支名稱掃描 Jira ticket 編號，自動擷取 ticket 內容（支援 jira CLI 與 Jira REST API），依 Story/Task 或 Bug 類型輸出驗收條件表格，未滿足的 AC 或未修正的 bug 路徑列為 blocker

---

## [0.2.0] — 2026-11-12

### 新增

- **skills/bugfix**：Bug 修復流程（跳過 brainstorm/plan/schema，直接進 TDD）
- **skills/release-tag**：GitLab annotated tag 建立、changelog 自動分類、CHANGELOG.md 更新
- **commands/bugfix**：`/bugfix` 指令入口
- **commands/release-tag**：`/release-tag` 指令入口

---

## [0.1.0] — 2026-11-12

### 新增

- **skills/feature-pipeline**：完整功能開發流程編排（brainstorm → plan → schema → TDD → review → MR）
- **skills/brainstorm**：互動式需求討論
- **skills/plan-writer**：實作計畫撰寫，輸出 `tmp/plan.md`
- **skills/api-schema**：API schema 設計，輸出 `tmp/schema.md`
- **skills/code-review**：程式碼審查，含預設審查規則 `checklist.md`
- **skills/security-scan**：安全掃描（gitleaks + semgrep + 依賴漏洞），含掃描腳本
- **skills/mr-review**：外部 MR/PR 審查
- **skills/gitlab-mr**：GitLab MR 建立
- **agents/test-writer**：TDD Red 階段，只能寫入測試目錄
- **agents/implementer**：TDD Green 階段，禁止修改測試檔案
- **agents/reviewer**：程式碼審查執行，完全唯讀
- **agents/security-auditor**：安全語意判斷，完全唯讀
- **skills/release-tag**：GitLab annotated tag 建立、changelog 自動分類、CHANGELOG.md 更新
- **commands**：`/feature`、`/review-mr`、`/security-scan`、`/release-tag`
- **templates**：`plan.md`、`schema.md`、`test-report.md`、`review.md`、`security.md`
- **config/pipeline.example.yaml**：專案設定範例與說明
