# AI Helper Plugin

將「需求 → 計畫 → 測試 → 實作 → 審查 → MR」的 AI 輔助開發流程，封裝成可跨專案安裝的 Claude Code plugin。

各階段 skill 彼此獨立，工程師自行決定執行哪些步驟與順序。

## 目錄結構

```
ai-helper/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── skills/
│   ├── brainstorm/          # 需求討論
│   ├── plan-writer/         # 實作計畫撰寫
│   ├── api-schema/          # API schema 設計（按需要執行）
│   ├── implement/           # TDD 實作（test-writer + implementer）
│   ├── bugfix/              # Bug 修復（跳過計畫階段）
│   ├── code-review/         # 程式碼審查
│   │   └── checklist.md     # 預設審查規則
│   ├── security-scan/       # 安全掃描
│   │   └── scripts/         # 掃描工具腳本
│   ├── mr-review/           # 外部 MR/PR 審查
│   ├── gitlab-mr/           # 建立 GitLab MR
│   └── release-tag/         # 打 release tag
├── agents/
│   ├── test-writer.md       # TDD Red 階段
│   ├── implementer.md       # TDD Green 階段
│   ├── reviewer.md          # 程式碼審查執行
│   └── security-auditor.md  # 安全語意判斷
├── commands/
│   ├── feature.md           # /feature：流程參考卡
│   ├── implement.md         # /implement：TDD 實作
│   ├── bugfix.md            # /bugfix：Bug 修復
│   ├── review-mr.md         # /review-mr：審查外部 MR
│   ├── security-scan.md     # /security-scan：安全掃描
│   └── release-tag.md       # /release-tag：打 tag
├── templates/               # 交接檔格式範本
└── config/
    └── settings.example.json  # Claude Code agent 權限設定範例
```

## 使用方式

### 安裝

```bash
# 本地安裝（測試用）
claude --plugin-dir /path/to/ai-helper
```

### 專案初始化（選用）

若有自訂審查規則，在目標專案中建立 `.pipeline/checklist.md`（追加審查規則，第一行寫 `override: true` 可完全取代預設規則）。

若有 coding style 規範，建立 `.pipeline/style_guide.md`。

### 指令

```
/brainstorm                        # 釐清需求，找出衝突與模糊地帶
/plan-writer                       # 制定實作計畫
/api-schema                        # 設計 API schema（按需要執行）
/implement                         # TDD 實作（test-writer → 人工確認 → implementer）
/bugfix <問題描述或 ticket 號碼>    # Bug 修復（跳過計畫階段）
/code-review                       # 程式碼審查（需求符合度 + coding style）
/security-scan                     # 安全掃描
/review-mr <MR 編號或連結>          # 審查外部 MR/PR
/gitlab-mr                         # 建立 GitLab MR
/release-tag                       # 打 release tag

/feature                           # 顯示完整流程參考卡
```

## 開發守則

1. 每個 skill 只負責一件事，各自獨立，不依賴其他 skill 的執行狀態。
2. Skill 間透過 `tmp/<ticket-id>/` 目錄的交接檔傳遞資訊，不依賴對話記憶。
3. Plugin 中不寫任何專案特定的業務邏輯，差異透過設定檔處理。
4. Plugin 中不寫任何憑證或 token。
5. Agent 權限變更需要 TL 審核。
6. 交接檔格式變更需同步更新 `templates/` 與 spec。
7. 人工關卡不可用參數關閉（`approve_plan` 與 `merged`）。
