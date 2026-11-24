---
name: security-scan
description: 執行靜態分析工具（gitleaks、semgrep、依語言的依賴掃描）並以 security-auditor agent 進行語意判斷，輸出至 tmp/<ticket-id>/security.md。報告中禁止顯示敏感值。security-auditor 完全唯讀。
tools: ["Read", "Bash", "Glob"]
---

# Security Scan — 安全掃描

結合確定性工具與 LLM 語意判斷，對目前分支的變更進行安全掃描。

## 使用方式

```
/security-scan <ticket-id>
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

輸出路徑為 `tmp/${TICKET_ID}/security.md`。

---

## 步驟 1：掃描工具設定

固定設定：
- 依賴掃描：`govulncheck ./...`
- semgrep 規則集：`p/golang`、`p/security-audit`

**必要工具安裝確認**（執行掃描前）：

```bash
MISSING_TOOLS=""
command -v gitleaks >/dev/null 2>&1 || MISSING_TOOLS="${MISSING_TOOLS} gitleaks"
command -v semgrep  >/dev/null 2>&1 || MISSING_TOOLS="${MISSING_TOOLS} semgrep"
```

若 `MISSING_TOOLS` 不為空，**立即停止**並顯示以下訊息，不可繼續執行：

```
❌ 安全掃描無法執行：必要工具未安裝

以下工具為必要工具，請安裝完成後重新執行 /security-scan：

  gitleaks：brew install gitleaks
            https://github.com/gitleaks/gitleaks

  semgrep ：brew install semgrep
            https://semgrep.dev/docs/getting-started

安裝完成後請重新執行：/security-scan <ticket-id>
```

停止，不執行步驟 2 以後的任何動作。

---

## 步驟 2：執行掃描工具

執行 `skills/security-scan/scripts/run-scanners.sh`：

```bash
bash skills/security-scan/scripts/run-scanners.sh
```

腳本會執行以下工具並將結果輸出至 `tmp/.security-raw/`：
- `gitleaks` — 敏感資訊掃描（工作目錄 + git history）
- `semgrep` — 靜態分析（步驟 1 推斷的規則集）
- 步驟 1 推斷的依賴漏洞掃描指令

若工具未安裝，記錄「工具未安裝，略過」，繼續執行其他工具，不可中止整體流程。

腳本完成後，讀取 `tmp/.security-raw/scan-status.txt`：
- 若 `scan_error: true`：在最終報告的「工具執行摘要」中標示受影響的工具，並在審查結論前加入警告：「部分掃描工具執行失敗，以下結果可能不完整，建議修復工具後重新執行。」**不可因工具失敗而略過整個安全掃描階段**，仍需繼續執行 security-auditor 的語意判斷。

---

## 步驟 2.5：大型 diff 判斷

若呼叫方傳入 `working_dir`，所有 git 指令加上 `-C "${WORKING_DIR}"`；否則在當前目錄執行。

```bash
GIT="git -C ${WORKING_DIR:-.}"
BASE_BRANCH=$(${GIT} symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")
CHANGED_FILES=$(${GIT} diff $(${GIT} merge-base HEAD origin/${BASE_BRANCH})...HEAD --name-only | wc -l)
CHANGED_LINES=$(${GIT} diff $(${GIT} merge-base HEAD origin/${BASE_BRANCH})...HEAD --stat | tail -1 | awk '{print $4+$6}')
```

- 若 `CHANGED_FILES > 30` 或 `CHANGED_LINES > 1000`：啟動**分批語意審查**（見下方）
- 否則：一次取得完整 diff，傳入 security-auditor

**分批語意審查**：
- 將變更檔案依目錄分批，每批不超過 10 個檔案或 300 行
- 生成的程式碼（`*.pb.go`、`*_gen.go`、`vendor/`）單獨一批，僅掃描硬編碼憑證，不進行完整語意分析
- 對每批分別呼叫 security-auditor agent
- **合批規則**：任意批次中的 blocker 均納入最終報告；相同位置的重複發現只保留最嚴重等級

---

## 步驟 3：LLM 語意判斷（security-auditor agent）

以 **security-auditor** agent 執行，傳入：
- 掃描工具結果（`tmp/.security-raw/` 內容）
- 目前分支的 git diff（或分批的 diff 片段）

security-auditor 負責：
1. 判斷工具結果的嚴重性與誤報（False Positive）
2. 檢查工具未涵蓋的項目：
   - 存取控制漏洞：API 是否正確驗證使用者身份與資源所有權（OWASP A01）
   - 加密強度：是否使用過時演算法（MD5/SHA1 用於密碼、DES/RC4）（OWASP A02）
   - NoSQL injection：MongoDB/Redis 查詢是否有未驗證輸入（OWASP A03）
   - 安全設定錯誤：CORS `*`、debug 端點暴露、預設帳密（OWASP A05）
   - SSRF：外部 URL 請求是否有 allowlist 限制（OWASP A10）
   - log 中是否有個資（email、電話、IP、使用者 ID）（OWASP A09）
   - 錯誤訊息是否洩漏內部資訊（stack trace、DB schema、路徑）（OWASP A09）
   - API 回應是否包含不應暴露的欄位

---

## 步驟 4：輸出報告

將報告寫入 `tmp/${TICKET_ID}/security.md`：

```markdown
---
stage: security
status: <若有任何 blocker 則為 blocked；所有工具完整執行且無 blocker 則為 passed>
created: <YYYY-MM-DD>
source: <繼承自 plan.md 的 source，若有>
---

# 安全掃描報告

掃描工具：<已執行的工具清單>
工具版本：<各工具版本>
發現問題：X 個阻擋項，X 個警告

---

## 阻擋項（必須修正）

### [阻擋] <問題類型>
**位置**：`<檔案>:<行號>`
**類型**：<敏感資訊洩漏 / SQL injection / ...>
**說明**：<問題說明，不得顯示敏感值本身>
**建議修正**：<具體做法>

---

## 警告（建議修正）

### [警告] <問題類型>
**位置**：`<檔案>:<行號>`
**說明**：<問題說明>
**建議修正**：<具體做法>

---

## 工具執行摘要

| 工具 | 狀態 | 發現數 |
|-----|------|--------|
| gitleaks | 已執行 | X |
| semgrep | 已執行 | X |
| <依賴掃描> | 已執行 / 未安裝 | X |

---

## 審查結論

**裁定：通過 / 需修正**
```

---

## 敏感資訊報告規則

**絕對禁止在報告中顯示敏感值本身**：
- API key、token、密碼：只顯示檔案與行號，不顯示值
- 若敏感資訊出現在 git history 中（非只在最新 commit）：標為 blocker，並在報告中加入以下警示：

```
⚠️ 敏感資訊存在於 git history 中
僅刪除最新 commit 無法解決此問題。
必須：1) 撤銷受影響的憑證  2) 請聯繫團隊進行 git history rewrite
```

## 規則

- **security-auditor 完全唯讀**：不得修改任何檔案或執行寫入指令。
- 工具未安裝時記錄並繼續，不可中止整體流程。
- `tmp/.security-raw/` 目錄為暫存，掃描完成後可清除，不加入版本控制。
