# Changelog

版本格式遵循 [Semantic Versioning](https://semver.org/)：
- **MAJOR**：設定格式或交接檔格式不相容的變更
- **MINOR**：新增 skill、agent 或設定選項
- **PATCH**：修正 bug、調整規則文字

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
