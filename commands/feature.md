---
description: 功能需求開發流程參考。列出各階段可用的 skill，由工程師自行決定執行順序與範圍。
---

# Feature 開發流程

以下是完整的功能開發建議步驟。每個 skill 均可獨立執行，不需要按順序全部跑完。

## 階段一：釐清需求

```
/brainstorm
```

與 PM 需求進行結構化討論，找出：
- PM 未定義清楚的部分
- 與當前程式碼有衝突的假設
- 範圍邊界與排除項目

輸出：`tmp/<ticket-id>/requirements.md`

---

## 階段二：制定計畫

```
/plan-writer
```

依需求摘要分析影響範圍，產出可供後續階段使用的結構化實作計畫。

輸出：`tmp/<ticket-id>/plan.md`（審閱後若有需要調整直接修改檔案即可）

```
/api-schema        # 按需要執行，非強制
```

若此次需求涉及 API 新增或修改，執行 api-schema 設計端點輸入輸出、錯誤碼與相容性。

輸出：`tmp/<ticket-id>/schema.md`

---

## 階段三：TDD 實作

```
/implement
```

以 TDD 方式進行實作。test-writer agent 與 implementer agent 分開執行：
1. test-writer 先撰寫失敗測試（Red）
2. 人工確認測試正確後，implementer 寫最少量實作使測試通過（Green）
3. 直到所有測試通過才算完成

---

## 階段四：程式碼審查

```
/code-review
```

審查本分支的 git diff，驗證：
- 程式碼品質與 coding style
- 是否符合需求（對照 requirements.md / plan.md）
- 安全問題

輸出：`tmp/<ticket-id>/review.md`

```
/security-scan     # 可與 code-review 分開或一起執行
```

執行 gitleaks、semgrep 等靜態分析工具並進行語意判斷。

輸出：`tmp/<ticket-id>/security.md`

---

## 階段五：提交 MR

```
/gitlab-mr
```

建立 GitLab MR，自動草擬標題與 description（根據 git diff 內容），等待人工 merge。

---

## 階段六：MR 審查（由審查者執行）

```
/review-mr <MR 編號或連結>
```

審查者從 GitLab / GitHub 取得 MR/PR diff，驗證：
- 程式碼品質與 coding style
- 是否符合需求（自動偵測關聯 Jira ticket）
- 安全問題

輸出：`tmp/mr-review/<編號>.md`
