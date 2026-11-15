---
stage: security
status: draft
created: YYYY-MM-DD
source: ""
---

# 安全掃描報告

掃描工具：gitleaks, semgrep, govulncheck
發現問題：X blocker, X warning

---

## Blocker（必須修正）

### [blocker] <問題類型>

**位置**：`<檔案>:<行號>`
**類型**：<敏感資訊洩漏 / SQL injection / ...>
**說明**：<問題說明，不顯示敏感值>
**建議修正**：<具體做法>

---

## Warning（建議修正）

### [warning] <問題類型>

**位置**：`<檔案>:<行號>`
**說明**：<問題說明>
**建議修正**：<具體做法>

---

## 工具執行摘要

| 工具 | 狀態 | 發現數 |
|-----|------|--------|
| gitleaks | 已執行 | X |
| semgrep | 已執行 | X |
| govulncheck | 已執行 | X |

---

## 審查結論

**裁定：APPROVE / REQUEST CHANGES**
