# AI Helper

將「需求 → 計畫 → 測試 → 實作 → 審查 → MR」的 AI 輔助開發流程，封裝成可跨專案安裝的 Claude Code plugin。

## 功能

| 指令 | 說明 |
|------|------|
| `/feature <需求描述或 Jira 連結>` | 完整功能開發流程（需求討論、計畫、Schema、TDD、審查、MR） |
| `/bugfix <bug 描述或 ticket 號碼>` | Bug 修復流程（跳過需求討論與 Schema，直接 TDD + 審查） |
| `/review-mr <MR 編號或連結>` | 審查外部 MR/PR（code review + security scan） |
| `/security-scan` | 單獨執行安全掃描 |
| `/release-tag [patch\|minor\|major\|<版號>]` | 打 semver tag 並產生 CHANGELOG |

## 安裝

### 方式一：正式安裝（推薦）

透過 Claude Code 的 plugin marketplace 機制安裝，支援版本管理與跨專案使用。

#### 1. 下載 plugin

```bash
git clone https://github.com/AndySu/ai-helper.git /path/to/ai-helper
```

或下載 zip 後解壓縮至任意目錄。

#### 2. 將 ai-helper 加為 marketplace（全域，一次性）

```bash
claude plugin marketplace add /path/to/ai-helper --scope user
```

#### 3. 在目標專案中安裝 forge plugin

```bash
cd /path/to/your-project
claude plugin install forge --scope project
```

`--scope project` 會將設定寫入專案的 `.claude/settings.json`，僅對該專案生效。

#### 更新 plugin

安裝後的 plugin 會複製到 cache，本地修改不會自動反映。若有更新：

1. 修改 `.claude-plugin/plugin.json` 中的 `version`（例如 `0.1.0` → `0.1.1`）
2. 在目標專案目錄執行：

```bash
claude plugin update forge
```

---

### 方式二：開發模式（本地即時生效）

開發或測試 plugin 時使用，每次啟動直接讀取原始目錄，不需版本號或手動更新：

```bash
claude --plugin-dir /path/to/ai-helper
```

### 3. 初始化專案設定（選用）

Plugin 會自動偵測語言（`go.mod` / `package.json` / `requirements.txt` / `Cargo.toml`）並推斷測試指令與路徑，**不需要設定檔即可使用**。

若有自訂需求，可在目標專案建立以下檔案：

```
.pipeline/
├── checklist.md      # 追加審查規則（第一行 override: true 可完全取代預設）
└── style_guide.md    # Coding style 規範
```

### 4. 安裝外部工具（選用）

部分功能依賴以下工具，未安裝時該功能會略過，不影響整體流程：

| 工具 | 用途 | 安裝 |
|------|------|------|
| `glab` | 建立 GitLab MR、打 tag | [gitlab.com/gitlab-org/cli](https://gitlab.com/gitlab-org/cli) |
| `gh` | 建立 GitHub PR | [cli.github.com](https://cli.github.com) |
| `gitleaks` | 敏感資訊掃描 | `brew install gitleaks` |
| `semgrep` | 靜態安全分析 | `pip install semgrep` |
| `govulncheck` | Go 依賴漏洞掃描 | `go install golang.org/x/vuln/cmd/govulncheck@latest` |

## 使用方式

### 開發新功能

```
/feature CEX-1234 實作使用者登出 API
```

流程：需求討論 → 計畫（人工核准）→ API Schema（人工確認）→ 測試撰寫（人工確認）→ 實作 → 審查 → 建立 MR

### 修復 bug

```
/bugfix CEX-5678 登入後 token 未正確刷新
```

流程：問題確認 → 測試撰寫（人工確認）→ 實作 → 審查 → 建立 MR

### 自訂審查規則

在專案中建立 `.pipeline/checklist.md`，追加專案特定的審查項目：

```markdown
## 專案規則（blocker）

- [ ] 所有 API 回應必須包含 request_id 欄位
- [ ] 禁止直接回傳資料庫 model，必須使用 DTO
```

預設規則與自訂規則會合併套用。若要完全取代預設規則，在 `config.yaml` 設定 `review.checklist_override: true`。

## 人工關卡

流程中有以下強制人工確認點，不可跳過：

| 關卡 | 時機 | 動作 |
|------|------|------|
| G1 | 計畫產生後 | 審閱 `tmp/<ticket-id>/plan.md`，將 `status` 改為 `approved` |
| G1.5 | API Schema 產生後 | 確認 `tmp/<ticket-id>/schema.md` 的端點與欄位正確 |
| G2 | 測試撰寫後 | 確認測試重現了需求（預期全部失敗） |

## 目錄結構

```
ai-helper/
├── .claude-plugin/plugin.json   # Plugin manifest
├── commands/                    # Slash command 定義
├── skills/                      # 各階段 skill（各自獨立）
│   ├── brainstorm/              # 需求討論
│   ├── plan-writer/             # 實作計畫
│   ├── api-schema/              # API Schema 設計（按需）
│   ├── implement/               # TDD 實作
│   ├── bugfix/                  # Bug 修復流程
│   ├── code-review/             # 程式碼審查
│   ├── security-scan/           # 安全掃描
│   ├── gitlab-mr/               # 建立 GitLab MR
│   ├── mr-review/               # 審查外部 MR/PR
│   └── release-tag/             # 版本 tag 與 changelog
├── agents/                      # 執行具體工作的 agent
│   ├── test-writer.md           # TDD Red 階段
│   ├── implementer.md           # TDD Green 階段
│   ├── reviewer.md              # 程式碼審查執行
│   └── security-auditor.md     # 安全語意判斷
└── config/
    └── settings.example.json    # Claude Code agent 權限設定範例
```
