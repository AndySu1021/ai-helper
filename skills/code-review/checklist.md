# 預設程式碼審查清單

此為 plugin 提供的預設審查規則。可由專案的 `.pipeline/checklist.md` 追加或覆寫。

---

## SQL 效能（blocker）

- [ ] 查詢是否有使用索引？（EXPLAIN 分析，或從查詢條件與索引定義判斷）
- [ ] 是否有 N+1 查詢問題？（迴圈內執行 DB 查詢）
- [ ] 是否有全表掃描風險？（無 WHERE 條件或 WHERE 條件欄位無索引）
- [ ] 分頁查詢是否有 OFFSET 效能問題？（大量資料時建議使用 cursor-based pagination）

## OOM 風險（blocker）

- [ ] 集合是否有上限？（無限制的 append、slice 擴長、map 增長）
- [ ] 大型檔案是否一次讀入記憶體？（應使用 streaming 或分批讀取）
- [ ] 批次處理是否有分批機制？（單次處理筆數是否有上界）

## Nil Pointer（blocker）

- [ ] 函式回傳的 pointer/interface 是否在使用前檢查 nil？
- [ ] map 存取前是否確認 key 存在？
- [ ] 型別斷言是否使用 `val, ok := x.(Type)` 形式？

## Panic 風險（blocker）

- [ ] 是否有未處理的錯誤回傳值（`_ = err`）？
- [ ] goroutine 中是否有 panic recovery？
- [ ] 陣列/slice 存取是否有越界風險？

## 邊界數值（blocker）

- [ ] 整數運算是否有溢位風險？
- [ ] 除法是否有除以零的情形？
- [ ] 時間計算是否考慮時區與 DST？

## 並發安全（blocker）

- [ ] goroutine 是否有明確的生命週期管理？（context cancel / WaitGroup / done channel）
- [ ] goroutine 中是否有 panic recovery，防止整個程序崩潰？
- [ ] 共享資料存取是否有鎖保護？（mutex、RWMutex、sync/atomic，或 channel-only 設計）
- [ ] channel 是否可能發生死鎖？（send/receive 配對、select 有 default 分支或 timeout）
- [ ] 是否有 goroutine 洩漏風險？（無限等待、context 未傳遞、無退出機制）
- [ ] map 並發存取是否使用 sync.Map 或加鎖？（Go 原生 map 並發讀寫會 panic）

## 安全性（blocker）

- [ ] 無硬編碼的憑證、API key、token（OWASP A02、A07）
- [ ] 無 SQL injection — 禁止字串拼接查詢，必須使用參數化查詢（OWASP A03）
- [ ] 無 NoSQL injection — MongoDB/Redis 查詢條件是否有使用者輸入未驗證就代入（OWASP A03）
- [ ] 無 XSS — 使用者輸入輸出前已跳脫或過濾（OWASP A03）
- [ ] 無 command injection — 禁止將使用者輸入傳入 shell 指令，使用 whitelist 而非 eval（OWASP A03）
- [ ] 存取控制是否正確？（水平越權：能否存取其他使用者的資源；垂直越權：低權限操作高權限功能）（OWASP A01）
- [ ] 敏感操作是否有身份驗證與授權驗證？（OWASP A01、A07）
- [ ] SSRF 防護 — 外部 URL 請求是否有 allowlist？禁止存取 169.254.x.x、10.x.x.x、127.x.x.x（OWASP A10）
- [ ] 加密演算法是否足夠強？（禁止 MD5/SHA1 用於密碼；禁止 DES/RC4；TLS 版本 ≥ 1.2）（OWASP A02）
- [ ] 安全設定是否正確？（無預設帳號密碼、無不必要的 debug 端點、CORS 不可設為 `*`）（OWASP A05）
- [ ] 日誌中不包含個資或敏感資訊（OWASP A09）

## 程式碼品質（warning）

- [ ] 函式行數 < 50 行
- [ ] 檔案行數 < 800 行
- [ ] 巢狀深度 <= 4 層
- [ ] 無空的 error handling（`catch {}` 或 `if err != nil {}`（空 block））
- [ ] 無未使用的 import 或變數
- [ ] 命名是否清楚、符合專案慣例

## 測試覆蓋（warning）

- [ ] 新增的公開函式是否有對應測試？
- [ ] 修改的邏輯是否有測試覆蓋到變更部分？
- [ ] 是否有測試 error path（非只有 happy path）？

## 其他（nit）

- [ ] TODO/FIXME 是否附有 ticket 號碼？
- [ ] 是否有多餘的 print/log 語句（除錯用的）？
- [ ] 格式與縮排是否一致？
