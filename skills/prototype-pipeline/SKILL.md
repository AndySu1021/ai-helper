---
name: prototype-pipeline
description: 將 requirements.md 轉為經過審查、設計一致、並與需求逐條對齊的原型。依序執行設計方向確認、需求審查、原型建置、自我檢查循環四個階段，每個確認點都需使用者同意後才能進入下一階段。當使用者要求從需求文件開始建立原型、執行完整的需求到原型流程，或要求依 pipeline 處理專案時使用。
---

# 需求到原型的 Pipeline

## 核心原則
- 每個階段的輸出是下一階段的輸入，透過檔案交接，不依賴對話記憶
- 確認點不可跳過：階段 0 的設計方向、階段 1 的需求定稿、階段 3 每輪的需求修改，都必須取得使用者同意
- 每次開始前先檢查交接檔案是否存在，若缺漏，回到對應階段，不要跳過
- 每個階段完成後，明確告知使用者結果，並說明下一步

## 專案檔案結構
- `requirements.md`：需求來源（唯一功能依據）
- `design_direction.md`：設計方向（階段 0 產出）
- `review.md`：需求審查報告（階段 1 產出）
- `requirements_checklist.md`：需求追蹤表（階段 1 建立，階段 3 維護）
- `prototype/`：原型程式碼（階段 2 建立，階段 3 修改）
- `loop_log.md`：自我檢查紀錄（階段 3 產出）

## 執行前檢查
1. 確認 `frontend-design` skill 已安裝：在可用 skill 清單中尋找 `frontend-design:frontend-design`。
   若找不到，停止並顯示以下訊息，等使用者安裝後再繼續：
   ```
   prototype-pipeline 依賴 frontend-design plugin 來建立原型。
   請先安裝：

     claude --plugin-dir /path/to/frontend-design

   安裝完成後重新執行此指令。
   ```
2. 確認 requirements.md 存在；若不存在，停止並請使用者提供
3. 檢查上述各檔案的狀態，判斷目前位於哪個階段
4. 告知使用者目前的階段，並詢問是否從該階段繼續

## 階段 0：設計方向確認
若 `design_direction.md` 已存在且使用者確認過，跳過此階段。

1. 閱讀 requirements.md，理解產品性質與目標使用者
2. 提出 2 到 3 個視覺方向，每個方向包含：風格描述、配色、字體建議、適用情境
3. 使用 AskUserQuestion 讓使用者選擇，建議選項標註「(Recommended)」
4. 依選定方向產出 `design_direction.md`，內容包含：風格定義、配色（CSS 變數）、字體、參考網址、禁止事項
5. 等使用者確認 design_direction.md 後，進入階段 1

## 階段 1：需求審查與定稿
若 requirements.md 已由使用者定稿，跳過此階段。

1. 平行啟動 5 個 agent，各自負責一個角度，互不重複：
    - 使用者與流程：目標使用者、使用情境、流程斷點
    - 功能與邊界：遺漏功能、異常情況、權限
    - 資料與狀態：資料需求、欄位定義、狀態轉換
    - 技術可行性：技術限制、外部依賴、風險
    - 驗收標準：每項功能是否可驗證
2. 每個 agent 的問題需標示嚴重度（阻礙開發 / 需要釐清 / 建議補充），並對應到 requirements.md 的段落
3. 彙整為 `review.md`：依嚴重度排序、合併重複問題、列出需使用者回答的問題清單
4. 使用 AskUserQuestion 分批提問（每次最多 4 題），將回答整理為 requirements.md 的修改提案
5. 等使用者同意修改後才寫入 requirements.md
6. 產出 `requirements_checklist.md`：每條需求含編號（REQ-xxx）、類別、原文摘錄、驗收條件、狀態
7. 使用者確認定稿後，進入階段 2

注意：agent 不得修改 requirements.md；不確定的答案一律列為問題，不可自行假設。

## 階段 2：原型初版建置
1. 載入 frontend-design skill，依 design_direction.md 與 requirements.md 建立原型
2. 原型存放於 `prototype/`
3. 只需完成主要頁面與主要流程，不要求完整
4. 完成後說明目前涵蓋的 REQ，以及尚未實作的部分
5. 進入階段 3 前，請使用者確認初版方向大致正確

## 階段 3：自我檢查循環
1. 呼叫 prototype-req-loop skill，以 requirements.md 檢查 prototype/
2. 每輪的需求修改都需使用者確認後才寫入
3. 每輪結束更新 loop_log.md
4. 結束條件：所有 REQ 為「已實作」且已驗證；本輪無新待確認問題；本輪無需求變更
5. 輪數上限 5 輪，超過時停止並列出未解決問題，交由使用者決定

## 設計一致性
- 所有 UI 修改都必須遵循 design_direction.md，不得在修復時臨時改變風格
- 若發現設計方向需要調整，回到階段 0 更新 design_direction.md，取得確認後再修改原型

## 輸出規範
每個階段結束時，請輸出：
- 目前階段與完成狀態
- 產出的檔案清單
- 需要使用者處理的事項
- 下一步建議