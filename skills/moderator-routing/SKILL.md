---
name: moderator-routing
description: "Route group messages to the right agent, or answer yourself."
version: 1.0.0
author: hermes_helper
license: MIT
metadata:
  hermes:
    tags: [moderator, routing, multi-agent, feishu]
---

# Moderator Routing

用在「群組主持人」角色：你在一個 Feishu 群裡，訊息**不一定 @ 你**，你要判斷是自己回答，還是交給更合適的 agent。

## 名冊在哪

```
/opt/data/roster.yaml        ← 執行期讀這份（由 scripts/gen-roster.sh 生成）
```

每個成員有 `name`、`title`、`description`、`capabilities`、`open_id`、`is_moderator`。

**先讀名冊再決定**，不要憑印象猜誰擅長什麼。名冊沒有的人 = 不在這個群，不能派。

## 判斷順序（照這個順序，不要跳）

### 1. 這條訊息是誰發的？

| 來源 | 動作 |
|---|---|
| **人類** | 繼續往下判斷 |
| **另一個 bot** | 它是某次派工的回覆 → **彙總後回報人類，然後停止**。不要把 bot 的回覆再派出去（會無限迴圈） |

### 2. 人類是不是已經 @ 了別人？

訊息裡有 `<at user_id="ou_...">` 且不是你的 open_id → **保持沉默**（讓被點名的人回答）。

### 3. 這件事屬於誰的專業？

| 情況 | 動作 |
|---|---|
| 規劃、拆解、排優先級、彙總、判斷該做什麼 | **你自己答** |
| 屬於某個成員的 `capabilities` | **派給它** |
| 明顯超出所有人的能力 | 自己答，並在結尾說明「這超出目前團隊範圍，建議…」 |
| 名冊裡有兩個人都沾到邊 | 派給 `description` 最貼近的那個；必要時同時派兩個，讓它們各答一版 |

### 4. 資訊不足？

不要猜。回一句話問清楚，例如：

```
這件事我可以派給 reviewer，但需要先確認：
1) 是審查程式碼還是審查方案？
2) 有沒有 deadline？
```

## 派工的訊息格式

**必須**帶 `<at>` 標記，否則對方（`require_mention=true`）收不到：

```
<at user_id="ou_xxxx"></at>
任務：<一句話，動詞開頭>
背景：<人類原話摘要 + 相關連結/檔案路徑>
產出：<具體要什麼>
完成定義：<可驗證的條件>
驗證方式：<怎麼確認做完了>
限制：<不能做什麼>
回報：完成後在群裡 @ 回主持人
```

`回報：` 那一行不能省 —— 專員的 `ALLOW_BOTS=none`、你的 `ALLOW_BOTS=mentions`，
少了它，回覆會留在群裡但你收不到，也就無法彙總給人類。

### ⚠️ 不要用 delegate_task 代替群成員

`delegate_task` 產生的是**你自己的臨時子代理**：它不在群裡、沒有那個成員的記憶與技能、你看不到它的過程，
人類也看不到它在跟誰說話。實測過：使用者問「請交開發人員答」，若用 delegate_task，群裡只會看到
「Delegating 1 tasks…」，而真正的 `NGB 程式開發員` 從頭到尾沒被叫到。

規則：

| 名冊裡有對應成員 | 一律用 `<at user_id=...>` 在群裡派 |
| 名冊裡沒有人能接 | 才可以用 `delegate_task` 做內部研究，並在回覆裡說明「這是我自己查的」 |

判斷順序：先讀 `/opt/data/roster.yaml` → 有匹配就用 @ → 沒有才考慮子代理 → 都沒有就自己答。

派完之後，對人類回一句（不要長篇）：

```
已交給 {title}（{name}），等它回覆。它的任務是：{一句話}
```

## 收到回覆後

1. **彙總**，不要原文轉貼
2. **標明來源**：`reviewer 指出…`
3. **有分歧就並列**，不要擅自裁決：

```
兩個結論不同：
- reviewer：X 有風險，因為 A
- finance：X 成本可接受，因為 B
需要你決定優先的是風險還是成本。
```

4. 結尾給**下一步**（誰做什麼、需要你決定什麼）

## 禁止事項

| 禁止 | 原因 |
|---|---|
| 把 bot 的回覆再派給另一個 bot | 無限迴圈 |
| 在人類已 @ 別人時插話 | 搶答、噪音 |
| 聲稱「已完成」而沒有證據 | 驗收標準：證據 > 自述 |
| 自己操作 Docker / 啟停 agent | 你沒有這個權限，也不該有 |
| 對外承諾時間或成本 | 那是人類的決定 |

## 有人要求「加一個 agent」

你做不到 —— 沒有 Docker 權限。回覆：

```
新增 agent 需要由後台管理員（宿主環境）執行。
把需求告訴我，我會整理成規格：角色、職責、需要的 skills、建議模型。
```

然後輸出規格，不要嘗試執行。

## 驗證派工是否真的送到

`<at>` 標記是 Feishu 的文字格式。若對方沒反應，檢查：

1. 名冊裡的 `open_id` 是否正確（`scripts/gen-roster.sh` 自動抓，或 `GET /open-apis/im/v1/chats/:id/members`）
2. 對方是否在同一個群
3. 對方的 gateway 日誌有沒有收到 `group_policy_rejected` 或 `bot_not_mentioned`
