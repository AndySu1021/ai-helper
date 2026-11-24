---
name: smoke-test
description: 以 Docker Compose 啟動本地服務，注入 seed 資料，驗證 API response 或 worker/consumer 執行後的 DB 狀態，結果寫入 tmp/<ticket-id>/smoke.md。
tools: ["Read", "Write", "Bash", "Glob", "Grep"]
---

# Smoke Test — 本地服務驗證

啟動本地 Docker 環境，注入 seed 資料，對真正運行的服務驗證行為：
- **API 模式**：發送 HTTP 請求，驗證 response status 與 body 欄位
- **Worker 模式**：等待定時任務執行完畢，查詢 DB 確認結果
- **Consumer 模式**：注入 queue 訊息，等待消費完畢，查詢 DB 確認結果

三種模式可並存（同一個 ticket 可能同時改了 API 和 worker）。

## 使用方式

```
/smoke-test <ticket-id>
```

---

## 步驟 0：讀取設定

```bash
TICKET_ID="${ARGUMENTS:-}"
if [ -z "${TICKET_ID}" ]; then
  # AskUserQuestion: 請提供 ticket ID（例如 PROJ-123）
fi
mkdir -p "tmp/${TICKET_ID}"
```

平行讀取：
1. `tmp/${TICKET_ID}/plan.md` — 必須存在，取得測試策略與期望驗證結果
2. `tmp/${TICKET_ID}/schema.md` — 若存在，啟用 API 模式
3. `.pipeline/smoke.env`（若存在）— 專案自訂環境變數（port、timeout 等）

若 `plan.md` 不存在，停止並回報：「找不到 plan.md，請先執行 /plan-writer。」

---

## 步驟 0.5：偵測測試模式

讀取 `tmp/${TICKET_ID}/plan.md` 的「測試策略」區段，依以下規則設定模式旗標：

```bash
HAS_API=false
HAS_WORKER=false
HAS_CONSUMER=false
```

- **`HAS_API=true`**：`schema.md` 存在，或測試策略提到 API endpoint、HTTP 請求
- **`HAS_WORKER=true`**：測試策略提到定時、排程、cron、worker、report 生成等關鍵字
- **`HAS_CONSUMER=true`**：測試策略提到 consumer、queue、message、事件消費等關鍵字

至少一個旗標必須為 `true`，否則停止並回報：「無法從 plan.md 判斷測試模式，請在測試策略區段描述要驗證的行為。」

從 `.pipeline/smoke.env` 或 plan.md 讀取以下設定（提供預設值）：

```bash
WORKER_TIMEOUT=${WORKER_TIMEOUT:-90}    # 等待 worker 執行的秒數上限
CONSUMER_TIMEOUT=${CONSUMER_TIMEOUT:-30} # 等待 consumer 消費的秒數上限
```

---

## 步驟 1：偵測 Docker Compose 設定

```bash
for f in docker-compose.dev.yml docker-compose.yml docker-compose.yaml; do
  [ -f "$f" ] && COMPOSE_FILE="$f" && break
done

docker compose version > /dev/null 2>&1 && COMPOSE_CMD="docker compose" || COMPOSE_CMD="docker-compose"
```

若找不到任何 compose 設定，停止並回報。

讀取 compose 設定，偵測服務：

- **API 服務**（`HAS_API=true` 時）：`app`、`api`、`server`（取 port mapping）
- **Worker/Consumer 服務**（`HAS_WORKER` 或 `HAS_CONSUMER` 時）：無 port mapping 的服務，名稱含 `worker`、`consumer`、`scheduler`、`job`；若無符合名稱，取所有無 port mapping 的服務
- **MySQL/MariaDB**：偵測 `mysql`、`mariadb` 服務，取 host port 與 DB 名稱
- **Redis**：偵測 `redis` 服務，取 host port
- **其他依賴**：記錄但不特別處理

---

## 步驟 2：啟動服務

讀取 `--reuse-env` 旗標（預設 false，可在 `.pipeline/smoke.env` 中設定 `REUSE_ENV=true`）：

```bash
REUSE_ENV=$(grep '^REUSE_ENV=' ".pipeline/smoke.env" 2>/dev/null | cut -d= -f2 || echo "false")
```

**`REUSE_ENV=false`**（預設）：清除既有環境後重啟，確保乾淨：

```bash
${COMPOSE_CMD} -f ${COMPOSE_FILE} down --volumes --remove-orphans 2>/dev/null || true
${COMPOSE_CMD} -f ${COMPOSE_FILE} up -d
```

**`REUSE_ENV=true`**：只做健康檢查，服務已在線則直接繼續（適用於開發迭代階段的快速重跑）：

```bash
# 確認服務在線
curl -sf "http://localhost:${APP_PORT}/health" > /dev/null 2>&1 || \
  curl -sf "http://localhost:${APP_PORT}/ping"  > /dev/null 2>&1 || {
    echo "[INFO] 服務未啟動，自動啟動..."
    ${COMPOSE_CMD} -f ${COMPOSE_FILE} up -d
  }
```

注意：`REUSE_ENV=true` 時不重注入 seed 資料，直接使用既有資料庫狀態執行測試。

**就緒確認**（依模式並行執行）：

**API 服務就緒**（`HAS_API=true`，最多 60 秒）：
```bash
APP_PORT=$(grep -A5 'app\|api\|server' ${COMPOSE_FILE} | grep -oP '"\K[0-9]+(?=:[0-9]+")' | head -1)
APP_PORT=${APP_PORT:-8080}

for i in $(seq 1 12); do
  curl -sf "http://localhost:${APP_PORT}/health" > /dev/null 2>&1 && break
  curl -sf "http://localhost:${APP_PORT}/ping"   > /dev/null 2>&1 && break
  sleep 5
done
```

**Worker/Consumer 服務就緒**（`HAS_WORKER` 或 `HAS_CONSUMER`，最多 30 秒）：
```bash
# Worker/Consumer 無 HTTP endpoint，改確認 container 狀態為 running（非 exited）
for i in $(seq 1 6); do
  STATUS=$(${COMPOSE_CMD} -f ${COMPOSE_FILE} ps --format json | \
    grep -E '"worker"|"consumer"|"scheduler"' | grep -oP '"State":"?\K[^",]+' | head -1)
  [ "${STATUS}" = "running" ] && break
  sleep 5
done

if [ "${STATUS}" != "running" ]; then
  ${COMPOSE_CMD} -f ${COMPOSE_FILE} logs --tail=30
  # 停止並回報：「Worker/Consumer 容器未能進入 running 狀態，請查看上方日誌。」
fi
```

---

## 步驟 3：注入 Seed 資料

### 3.1 尋找既有 seed

```bash
for f in .pipeline/seeds.sql scripts/seed.sql db/seeds.sql fixtures/seed.sql; do
  [ -f "$f" ] && SEED_FILE="$f" && break
done
```

### 3.2 自動生成 seed（無既有 seed 時）

讀取 `tmp/${TICKET_ID}/plan.md`（與 `schema.md` 若存在），推斷需要的基礎資料，生成最小可用的 SQL：

**生成原則**：
- 每個關聯資源準備 **2 筆**：1 筆正常資料、1 筆用於邊界測試（如 inactive 狀態）
- 若有 user_id / account_id 等 owner 欄位，插入 `id = 1` 的基礎 user 記錄
- Worker 模式：依 plan.md 測試策略產生 worker 執行所需的前置資料（例如定時報表需要的原始交易記錄）
- Consumer 模式：DB seed 只插入 consumer 處理後需要查詢的前置資料；queue 訊息在步驟 4.B 注入
- 生成的 SQL 寫入 `tmp/${TICKET_ID}/seeds.sql`

### 3.3 執行 seed

**MySQL/MariaDB**：
```bash
MYSQL_SERVICE=$(grep -oP '^  \K(mysql|mariadb)(?=:)' ${COMPOSE_FILE} | head -1)
MYSQL_PORT=$(${COMPOSE_CMD} port ${MYSQL_SERVICE} 3306 2>/dev/null | cut -d: -f2 || echo "3306")
DB_NAME=$(grep -A10 "${MYSQL_SERVICE}" ${COMPOSE_FILE} | grep -oP 'MYSQL_DATABASE=\K\S+' | head -1 || echo "app")
DB_PASS=$(grep -A10 "${MYSQL_SERVICE}" ${COMPOSE_FILE} | grep -oP 'MYSQL_ROOT_PASSWORD=\K\S+' | head -1 || echo "root")

mysql -h 127.0.0.1 -P ${MYSQL_PORT} -u root -p"${DB_PASS}" ${DB_NAME} < "${SEED_FILE:-tmp/${TICKET_ID}/seeds.sql}"
```

**Redis**：
```bash
REDIS_PORT=$(${COMPOSE_CMD} port ${REDIS_SERVICE:-redis} 6379 2>/dev/null | cut -d: -f2 || echo "6379")
grep "^redis-cli" "tmp/${TICKET_ID}/seeds.sql" 2>/dev/null | bash -s -- -p ${REDIS_PORT} || true
```

---

## 步驟 4.A：API 測試（`HAS_API=true` 時執行）

讀取 `schema.md`，依端點清單逐一發送請求。

### 優先使用 Postman CLI（若 collection 存在）

```bash
POSTMAN_BIN="${POSTMAN_BIN:-$(which postman 2>/dev/null)}"

for f in .pipeline/smoke.postman_collection.json postman/smoke.postman_collection.json; do
  [ -f "$f" ] && POSTMAN_COLLECTION="$f" && break
done

if [ -f "${POSTMAN_COLLECTION:-}" ] && [ -n "${POSTMAN_BIN}" ]; then
  ${POSTMAN_BIN} collection run "${POSTMAN_COLLECTION}" \
    --env-var "baseUrl=http://localhost:${APP_PORT}" \
    --reporter-cli \
    2>&1 | tee "tmp/${TICKET_ID}/.smoke-postman-output.txt"
  USED_POSTMAN=true
fi
```

### Fallback：依 schema 自動生成 curl 請求

**請求生成規則**：
- 使用 step 3 注入的 seed 資料 ID
- 若端點需要 auth token，先對 login/token 端點取得後快取
- 每個端點至少測試：happy path（預期 2xx）、缺少必填欄位（預期 4xx）

### 驗證 Response

對每個請求，依 schema.md 的「回應」定義驗證：
1. HTTP status code 是否符合 schema 定義
2. Response body 的**必填欄位是否存在**（不驗值，只驗 key 存在）
3. 錯誤回應的 error code 是否符合 schema 定義
4. Content-Type header 是否為 `application/json`

```
[PASS] POST /api/v1/users → 201, body has: id, name, email
[FAIL] GET  /api/v1/users/999 → 200 (expected 404)
[SKIP] DELETE /api/v1/users/:id → 需要管理員權限，略過
```

### 邊界資料驗證

對 seed 資料中標記為邊界狀態的資料（第 2 筆，通常為 inactive / disabled / 餘額不足等），發送對應請求並驗證錯誤回應符合 schema 定義：

```
[PASS] GET /api/v1/users/2 → 403 FORBIDDEN (user is inactive, expected 403)
[FAIL] POST /api/v1/orders → 200 (expected 402 INSUFFICIENT_BALANCE for user_id=2)
```

驗證邏輯：
- 對每個在 schema 中定義了業務錯誤碼（非純格式錯誤）的端點，使用邊界狀態的 seed 資料 ID 發送請求
- 驗證回應的 HTTP status code 與 error code 是否符合 schema 的錯誤定義
- 不符合則標記為 `[FAIL]`，納入 smoke.md 的失敗詳情

---

## 步驟 4.B：Worker / Consumer 測試（`HAS_WORKER` 或 `HAS_CONSUMER` 時執行）

### 4.B.1 Consumer 模式：注入 queue 訊息（`HAS_CONSUMER=true`）

讀取 plan.md 測試策略，推斷 queue 訊息格式，依偵測到的 queue 服務自動注入：

**Redis（LPUSH / RPUSH）**：
```bash
QUEUE_KEY="<從 plan.md 測試策略推斷的 queue key>"
MESSAGE='<從 plan.md 推斷的 JSON 訊息>'

redis-cli -p ${REDIS_PORT} LPUSH "${QUEUE_KEY}" "${MESSAGE}"
echo "[INFO] 已注入訊息到 ${QUEUE_KEY}"
```

**RabbitMQ**（compose 中有 `rabbitmq` 服務時）：
```bash
RABBITMQ_PORT=$(${COMPOSE_CMD} port rabbitmq 15672 2>/dev/null | cut -d: -f2 || echo "15672")
RABBITMQ_USER=$(grep -A10 'rabbitmq' ${COMPOSE_FILE} | grep -oP 'RABBITMQ_DEFAULT_USER=\K\S+' | head -1 || echo "guest")
RABBITMQ_PASS=$(grep -A10 'rabbitmq' ${COMPOSE_FILE} | grep -oP 'RABBITMQ_DEFAULT_PASS=\K\S+' | head -1 || echo "guest")
EXCHANGE="<從 plan.md 推斷的 exchange，預設為空字串>"
ROUTING_KEY="<從 plan.md 推斷的 routing key>"

# 等待 RabbitMQ management API 就緒（最多 30 秒）
for i in $(seq 1 6); do
  curl -sf "http://localhost:${RABBITMQ_PORT}/api/overview" \
    -u "${RABBITMQ_USER}:${RABBITMQ_PASS}" > /dev/null 2>&1 && break
  sleep 5
done

curl -s -X POST "http://localhost:${RABBITMQ_PORT}/api/exchanges/%2F/${EXCHANGE}/publish" \
  -u "${RABBITMQ_USER}:${RABBITMQ_PASS}" \
  -H "Content-Type: application/json" \
  -d "{\"routing_key\":\"${ROUTING_KEY}\",\"payload\":${MESSAGE},\"payload_encoding\":\"string\",\"properties\":{}}"
echo "[INFO] 已注入 RabbitMQ 訊息到 exchange=${EXCHANGE} routing_key=${ROUTING_KEY}"
```

**Kafka**（compose 中有 `kafka` 或 `broker` 服務時）：
```bash
KAFKA_PORT=$(${COMPOSE_CMD} port kafka 9092 2>/dev/null | cut -d: -f2 || \
             ${COMPOSE_CMD} port broker 9092 2>/dev/null | cut -d: -f2 || echo "9092")
KAFKA_TOPIC="<從 plan.md 推斷的 topic>"

echo "${MESSAGE}" | ${COMPOSE_CMD} exec -T kafka \
  kafka-console-producer --bootstrap-server localhost:9092 --topic "${KAFKA_TOPIC}" 2>/dev/null || \
echo "${MESSAGE}" | ${COMPOSE_CMD} exec -T broker \
  kafka-console-producer --bootstrap-server localhost:9092 --topic "${KAFKA_TOPIC}"
echo "[INFO] 已注入 Kafka 訊息到 topic=${KAFKA_TOPIC}"
```

### 4.B.2 等待執行完畢

**Worker 模式（cron）**：

等待 worker container log 出現「執行完成」相關訊息，或等待固定時間：

```bash
echo "[INFO] 等待 worker 執行（上限 ${WORKER_TIMEOUT} 秒）..."
ELAPSED=0
INTERVAL=5

while [ $ELAPSED -lt $WORKER_TIMEOUT ]; do
  # 從 plan.md 推斷成功標誌關鍵字（例如 "job completed"、"report generated"）
  DONE=$(${COMPOSE_CMD} -f ${COMPOSE_FILE} logs worker 2>/dev/null | \
    grep -iE "completed|finished|done|success|generated" | tail -1)
  if [ -n "${DONE}" ]; then
    echo "[INFO] Worker 執行完成：${DONE}"
    break
  fi
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $WORKER_TIMEOUT ]; then
  ${COMPOSE_CMD} -f ${COMPOSE_FILE} logs worker --tail=30
  # 記錄為 FAIL：「Worker 在 ${WORKER_TIMEOUT} 秒內未出現完成訊號，請查看上方日誌。」
fi
```

**Consumer 模式**：

等待 queue 長度歸零（訊息已被消費）：

```bash
echo "[INFO] 等待 consumer 消費訊息（上限 ${CONSUMER_TIMEOUT} 秒）..."
ELAPSED=0

while [ $ELAPSED -lt $CONSUMER_TIMEOUT ]; do
  QUEUE_LEN=$(redis-cli -p ${REDIS_PORT} LLEN "${QUEUE_KEY}" 2>/dev/null || echo "-1")
  [ "${QUEUE_LEN}" = "0" ] && echo "[INFO] 訊息已被消費" && break
  sleep 3
  ELAPSED=$((ELAPSED + 3))
done

if [ $ELAPSED -ge $CONSUMER_TIMEOUT ]; then
  # 記錄為 FAIL：「Consumer 在 ${CONSUMER_TIMEOUT} 秒內未消費訊息（queue 長度仍為 ${QUEUE_LEN}）。」
fi
```

### 4.B.3 DB 驗證

讀取 plan.md 測試策略，依「預期的 DB 狀態變化」生成 SQL 驗證查詢。

**驗證邏輯**：
- 測試策略中描述的每一個期望結果，轉換成一條 SQL `SELECT` 查詢
- 比對實際查詢結果與期望值
- 只驗「是否存在」或「筆數是否符合」，不驗具體欄位值（時間戳、自增 ID 等每次不同）

範例：
```bash
# 期望：reports 表新增 1 筆今日的報表記錄
ACTUAL=$(mysql -h 127.0.0.1 -P ${MYSQL_PORT} -u root -p"${DB_PASS}" ${DB_NAME} \
  -se "SELECT COUNT(*) FROM reports WHERE DATE(created_at) = CURDATE();")
EXPECTED=1

if [ "${ACTUAL}" = "${EXPECTED}" ]; then
  echo "[PASS] reports 表今日新增 ${ACTUAL} 筆（預期 ${EXPECTED}）"
else
  echo "[FAIL] reports 表今日新增 ${ACTUAL} 筆（預期 ${EXPECTED}）"
fi
```

每個驗證項目記錄為：
```
[PASS] <描述> — 預期: <值>, 實際: <值>
[FAIL] <描述> — 預期: <值>, 實際: <值>
```

---

## 步驟 5：清理環境

無論測試成功或失敗，必須完整清除容器與 volume：

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
mode: <api | worker | consumer | hybrid>
---

# Smoke Test 報告

模式：<API | Worker | Consumer | Hybrid>
服務：<http://localhost:<PORT> | worker container>
資料庫：<MySQL host:port db_name>
Redis：<host:port | 無>
結果：<X passed, X failed, X skipped>

---

## API 測試結果（API 模式）

| 狀態 | 方法 | 端點 | 預期 | 實際 | 說明 |
|------|------|------|------|------|------|
| ✅ PASS | POST | /api/v1/users | 201 | 201 | body fields OK |
| ❌ FAIL | GET  | /api/v1/users/999 | 404 | 200 | — |

---

## Worker / Consumer 執行結果（Worker/Consumer 模式）

執行等待：<X 秒>
觸發方式：<cron 自動執行 | Redis LPUSH queue_key>

| 狀態 | 驗證項目 | 預期 | 實際 |
|------|---------|------|------|
| ✅ PASS | reports 表今日筆數 | 1 | 1 |
| ❌ FAIL | notifications 表新增筆數 | 2 | 0 |

---

## 失敗詳情

### ❌ <失敗項目>
**預期**：<值>
**實際**：<值>
**SQL / 請求**：`<執行的查詢或 curl 指令>`

---

## Seed 資料

注入方式：<使用 .pipeline/seeds.sql | 自動生成 tmp/<ticket-id>/seeds.sql>
注入資料摘要：
- <資料表>: <N> 筆

---

## 環境資訊

Compose 設定：<COMPOSE_FILE>
服務啟動耗時：<秒>
```

---

## 步驟 7：判斷是否阻擋後續流程

- `status: passed` — 所有驗證項目通過
- `status: partial` — 有 SKIP（非失敗），視為通過
- `status: failed` — 有任何 FAIL，停止並列出失敗項目

---

## 規則

- 只驗本 ticket 相關的端點與 DB 狀態，不觸碰其他端點或資料表。
- Seed 資料只使用固定的低 ID（1、2、3），避免與既有資料衝突。
- DB 驗證只檢查「是否存在」或「筆數」，不比較時間戳、自增 ID 等每次不同的值。
- 每次執行前必須 `down --volumes` 確保環境乾淨。
- 清理環境必須執行，即使測試失敗也要 `down --volumes`。
- 不得在 smoke.md 中記錄任何密碼、token 或訊息的實際敏感值。
- Worker 完成標誌關鍵字（`completed`、`finished` 等）從 plan.md 推斷，若無法推斷則等到 `WORKER_TIMEOUT` 後以 log 末行判斷。