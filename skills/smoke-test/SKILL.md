---
name: smoke-test
description: 以 Docker Compose 啟動本地服務（含 MySQL/Redis），注入假資料，以 curl 或 Postman CLI 驗證 API 實際行為，結果寫入 tmp/<ticket-id>/smoke.md。
tools: ["Read", "Write", "Bash", "Glob", "Grep"]
---

# Smoke Test — 本地服務驗證

啟動本地 Docker 環境，注入 seed 資料，對真正運行的服務發送請求，驗證 API 的 request/response 格式與行為。

## 使用方式

```
/smoke-test
```

執行前，`tmp/<ticket-id>/schema.md` 必須存在（至少有一個端點定義）。

---

## 步驟 0：讀取設定

```bash
TICKET_ID=$(cat tmp/.current-ticket)
```

平行讀取：
1. `tmp/${TICKET_ID}/schema.md` — 必須存在，取得端點定義
2. `tmp/${TICKET_ID}/plan.md` — 取得服務名稱與依賴資訊
3. `.pipeline/smoke.env`（若存在）— 專案自訂的環境變數（port、DB 名稱等）

---

## 步驟 1：偵測 Docker Compose 設定

```bash
# 依優先序尋找 compose 設定
for f in docker-compose.dev.yml docker-compose.yml docker-compose.yaml; do
  [ -f "$f" ] && COMPOSE_FILE="$f" && break
done

# 偵測 compose 命令版本
docker compose version > /dev/null 2>&1 && COMPOSE_CMD="docker compose" || COMPOSE_CMD="docker-compose"
```

若找不到任何 compose 設定，停止並回報：「找不到 docker-compose 設定，請在專案根目錄提供 docker-compose.dev.yml 或 docker-compose.yml。」

讀取 compose 設定，偵測以下服務：
- **應用服務**：通常是 `app`、`api`、`server`（取 port mapping）
- **MySQL/MariaDB**：偵測 `mysql`、`mariadb` 服務名稱，取得 host port 與 DB 名稱
- **Redis**：偵測 `redis` 服務名稱，取得 host port
- **其他依賴**：記錄但不特別處理

---

## 步驟 2：啟動服務

每次執行前必須從乾淨的環境開始，確保測試結果不受前次殘留資料影響：

```bash
# 完整清除既有容器、volume（含資料庫資料）與孤立容器
${COMPOSE_CMD} -f ${COMPOSE_FILE} down --volumes --remove-orphans 2>/dev/null || true

# 啟動全新服務（背景執行）
${COMPOSE_CMD} -f ${COMPOSE_FILE} up -d
```

等待服務就緒（最多 60 秒）：

```bash
APP_PORT=$(grep -A5 'app\|api\|server' ${COMPOSE_FILE} | grep -oP '"\K[0-9]+(?=:[0-9]+")' | head -1)
APP_PORT=${APP_PORT:-8080}

for i in $(seq 1 12); do
  curl -sf "http://localhost:${APP_PORT}/health" > /dev/null 2>&1 && break
  curl -sf "http://localhost:${APP_PORT}/ping"   > /dev/null 2>&1 && break
  curl -sf "http://localhost:${APP_PORT}/"        > /dev/null 2>&1 && break
  sleep 5
done
```

若 60 秒後服務仍無回應，取得容器日誌後停止：

```bash
${COMPOSE_CMD} -f ${COMPOSE_FILE} logs --tail=50
```

停止並回報：「服務啟動失敗，請查看上方容器日誌。」

---

## 步驟 3：注入 Seed 資料

### 3.1 尋找既有 seed

```bash
# 優先使用專案已有的 seed 腳本
for f in .pipeline/seeds.sql scripts/seed.sql db/seeds.sql fixtures/seed.sql; do
  [ -f "$f" ] && SEED_FILE="$f" && break
done
```

### 3.2 自動生成 seed（無既有 seed 時）

讀取 `tmp/${TICKET_ID}/schema.md` 與 `tmp/${TICKET_ID}/plan.md`，根據端點的請求參數，推斷需要的基礎資料並生成最小可用的 SQL：

**生成原則**：
- 每個關聯資源準備 **2 筆**：1 筆正常資料、1 筆用於邊界測試（如 inactive 狀態）
- 若 schema 有 user_id / account_id 等 owner 欄位，插入 `id = 1` 的基礎 user 記錄
- 若有 Redis 需求（session、cache），以 `redis-cli SET` 注入 key-value
- 生成的 SQL 寫入 `tmp/${TICKET_ID}/seeds.sql` 供事後審閱

### 3.3 執行 seed

**MySQL/MariaDB**：
```bash
# 取得 compose 中的 MySQL 設定
MYSQL_SERVICE=$(grep -oP '^  \K(mysql|mariadb)(?=:)' ${COMPOSE_FILE} | head -1)
MYSQL_PORT=$(${COMPOSE_CMD} port ${MYSQL_SERVICE} 3306 2>/dev/null | cut -d: -f2 || echo "3306")
DB_NAME=$(grep -A10 "${MYSQL_SERVICE}" ${COMPOSE_FILE} | grep -oP 'MYSQL_DATABASE=\K\S+' | head -1 || echo "app")
DB_PASS=$(grep -A10 "${MYSQL_SERVICE}" ${COMPOSE_FILE} | grep -oP 'MYSQL_ROOT_PASSWORD=\K\S+' | head -1 || echo "root")

mysql -h 127.0.0.1 -P ${MYSQL_PORT} -u root -p"${DB_PASS}" ${DB_NAME} < "${SEED_FILE:-tmp/${TICKET_ID}/seeds.sql}"
```

**Redis**：
```bash
REDIS_SERVICE=$(grep -oP '^  \Kredis(?=:)' ${COMPOSE_FILE} | head -1)
REDIS_PORT=$(${COMPOSE_CMD} port ${REDIS_SERVICE:-redis} 6379 2>/dev/null | cut -d: -f2 || echo "6379")

# 從生成的 seed 中找出 redis-cli 指令執行
grep "^redis-cli" "tmp/${TICKET_ID}/seeds.sql" 2>/dev/null | bash -s -- -p ${REDIS_PORT} || true
```

---

## 步驟 4：執行 Smoke Test

讀取 `tmp/${TICKET_ID}/schema.md`，依端點清單逐一發送請求。

### 4.1 優先使用 Postman CLI（若 collection 存在）

```bash
POSTMAN_BIN="/Users/andysu/.local/bin/postman"

for f in .pipeline/smoke.postman_collection.json postman/smoke.postman_collection.json; do
  [ -f "$f" ] && POSTMAN_COLLECTION="$f" && break
done

if [ -f "${POSTMAN_COLLECTION:-}" ] && [ -f "${POSTMAN_BIN}" ]; then
  ${POSTMAN_BIN} collection run "${POSTMAN_COLLECTION}" \
    --env-var "baseUrl=http://localhost:${APP_PORT}" \
    --reporter-cli \
    2>&1 | tee "tmp/${TICKET_ID}/.smoke-postman-output.txt"
  USED_POSTMAN=true
fi
```

### 4.2 Fallback：依 schema 自動生成 curl 請求

若未使用 Postman（無 collection 或 Postman CLI 不可用），依 schema.md 每個端點構造 curl 指令。

**請求生成規則**：
- 使用 step 3 注入的 seed 資料 ID
- 若端點需要 auth token，先對 login/token 端點取得 token，快取後傳入後續請求
- 每個端點至少測試：happy path（預期 2xx）、缺少必填欄位（預期 4xx）

```bash
BASE_URL="http://localhost:${APP_PORT}"

# 範例：每個請求記錄到 tmp/${TICKET_ID}/.smoke-curl-output.txt
curl -sf -w "\nHTTP_STATUS:%{http_code}" \
  -X <METHOD> "${BASE_URL}<PATH>" \
  -H "Content-Type: application/json" \
  -d '<REQUEST_BODY>' \
  >> "tmp/${TICKET_ID}/.smoke-curl-output.txt" 2>&1
```

### 4.3 驗證 Response

對每個請求，依 schema.md 的「回應」定義驗證：

**驗證項目**：
1. HTTP status code 是否符合 schema 定義（2xx / 4xx / 5xx）
2. Response body 的**必填欄位是否存在**（不驗值，只驗 key 存在）
3. 錯誤回應的 error code 欄位是否符合 schema 定義的錯誤碼
4. Content-Type header 是否為 `application/json`

**記錄格式**：

```
[PASS] POST /api/v1/users → 201, body has: id, name, email
[FAIL] GET  /api/v1/users/999 → 200 (expected 404)
[FAIL] POST /api/v1/users → missing field: id in response body
[SKIP] DELETE /api/v1/users/:id → 需要管理員權限，略過
```

---

## 步驟 5：清理環境

無論測試成功或失敗，必須完整清除容器與 volume，不留任何殘留資料：

```bash
${COMPOSE_CMD} -f ${COMPOSE_FILE} down --volumes --remove-orphans
```

---

## 步驟 6：輸出報告

將結果寫入 `tmp/${TICKET_ID}/smoke.md`：

```markdown
---
stage: smoke
status: <passed | failed | partial>
created: <YYYY-MM-DD>
source: <繼承自 plan.md 的 source>
tool: <postman | curl>
---

# Smoke Test 報告

服務：http://localhost:<PORT>
資料庫：<MySQL host:port db_name | 無>
Redis：<host:port | 無>
測試工具：<Postman CLI | curl>
結果：<X passed, X failed, X skipped>

---

## 端點測試結果

| 狀態 | 方法 | 端點 | 預期 | 實際 | 說明 |
|------|------|------|------|------|------|
| ✅ PASS | POST | /api/v1/users | 201 | 201 | body fields OK |
| ❌ FAIL | GET | /api/v1/users/999 | 404 | 200 | — |
| ⏭ SKIP | DELETE | /api/v1/users/:id | — | — | 需要管理員權限 |

---

## 失敗詳情

### ❌ GET /api/v1/users/999

**預期**：404
**實際**：200
**Response body**：
```json
<實際回應>
```
**Schema 定義**：<schema.md 中對應的回應定義>

---

## Seed 資料

注入方式：<使用 .pipeline/seeds.sql | 自動生成 tmp/<ticket-id>/seeds.sql>
注入資料摘要：
- users: 2 筆（id=1 正常, id=2 inactive）
- <其他資料表>

---

## 環境資訊

Compose 設定：<COMPOSE_FILE>
服務啟動耗時：<秒>
```

---

## 步驟 7：判斷是否阻擋後續流程

- `status: passed` — 所有端點測試通過，可繼續 code-review
- `status: partial` — 有 SKIP（非失敗），視為通過，繼續並在 review 中標注
- `status: failed` — 有任何 FAIL，停止並回報：

```
❌ Smoke test 失敗，請修正以下問題後重新執行 /smoke-test：

<失敗的端點清單>
```

---

## 規則

- 只對本 ticket 相關的端點發送請求，不觸碰其他端點。
- Seed 資料只使用固定的低 ID（1、2、3），避免與既有資料衝突。
- 驗證 response 只檢查欄位存在，不比較具體值（時間戳、ID 等每次不同）。
- 每次執行前必須 `down --volumes` 確保環境乾淨，不得沿用前次資料。
- 清理環境必須執行，即使測試失敗也要 `down --volumes`。
- 不得在 smoke.md 中記錄任何密碼或 token 的實際值。
