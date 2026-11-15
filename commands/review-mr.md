---
description: 審查外部 MR/PR。輸入 MR/PR 編號或連結，自動偵測關聯 Jira ticket 並驗證需求符合度，同時執行程式碼審查與安全掃描，結果寫入 tmp/mr-review/。未確認前不發佈評論。
---

啟動 **mr-review** skill，審查指定的 MR 或 PR。

將以下內容傳入 skill：`$ARGUMENTS`
