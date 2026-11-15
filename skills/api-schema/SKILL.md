---
name: api-schema
description: 依 tmp/<ticket-id>/plan.md 設計 API schema，輸出至 tmp/<ticket-id>/schema.md。包含端點、請求與回應結構、錯誤碼、相容性說明。
tools: ["Read", "Write", "Glob", "Grep"]
---

# API Schema — API Schema 設計

依實作計畫設計 API 的輸入輸出結構、錯誤碼與相容性說明。

## 使用方式

```
/api-schema
```

---

## 步驟 0：讀取 ticket-id

```bash
TICKET_ID=$(cat tmp/.current-ticket)
```

輸出路徑為 `tmp/${TICKET_ID}/schema.md`。

---

## 步驟 1：讀取輸入

平行讀取：

1. `tmp/${TICKET_ID}/plan.md` — 必須存在，若不存在則停止並提示先執行 `/plan-writer`。
2. `CLAUDE.md` — 專案規範（API 格式、錯誤碼慣例）
3. 既有 API 定義檔（`Glob` 找 `.proto`、`openapi.yaml`、路由定義等）

---

## 步驟 2：設計 Schema

根據 plan.md 的「API 變更」與「影響檔案」章節，為每個端點設計完整的 schema。

**必須包含**：

- 端點路徑與 HTTP 方法
- 請求結構（Query params、Path params、Request body）
- 回應結構（成功與失敗）
- 錯誤碼清單
- 與既有 API 的相容性說明（若為修改現有端點）

---

## 步驟 3：輸出 Schema

將 schema 寫入 `tmp/${TICKET_ID}/schema.md`，frontmatter 格式：

```
---
stage: schema
created: <YYYY-MM-DD>
source: <繼承自 plan.md 的 source>
---
```

每個端點依以下結構撰寫：

**端點清單**（文件開頭）

| 端點 | 方法 | 說明 |
|------|------|------|
| /api/v1/... | POST | ... |

**各端點詳細定義**

```
## <端點名稱>

### 請求

Path params（若有）：
| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|

Query params（若有）：
| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|

Request body（若有）：
{
  "field": "type // description"
}

### 回應

成功（200/201）：
{
  "field": "type // description"
}

錯誤：
| 狀態碼 | 錯誤碼        | 說明           |
|--------|---------------|----------------|
| 400    | INVALID_INPUT | 輸入格式錯誤   |
| 404    | NOT_FOUND     | 資源不存在     |

### 相容性

<說明此端點是否為新增，或修改既有端點。若修改，說明向後相容策略。>
```

完成後輸出：

```
tmp/<ticket-id>/schema.md 已產生。

建議後續步驟：
  /implement        進入 TDD 實作
```

---

## 規則

- 若 `tmp/${TICKET_ID}/plan.md` 不存在，立即停止並回報，不可繼續。
- 修改既有端點時，必須說明向後相容性，不可略去相容性章節。
- 無法確定的欄位型別，標示為「待確認」而非自行假設。
