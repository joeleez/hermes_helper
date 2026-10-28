# 02 — 接上 Feishu

一個 agent 對一個自建應用（App）。要第二個 agent 獨立對話，就得建第二個 App。

## 1. 建應用

https://open.feishu.cn/app → **创建企业自建应用**

| 步驟 | 位置 | 做什麼 |
|---|---|---|
| 1 | 凭证与基础信息 | 記下 `App ID` / `App Secret` |
| 2 | 权限管理 | 加 `im:message`、`im:message:send_as_bot`、`im:chat:readonly`、`im:resource` |
| 3 | 事件订阅 | 訂閱 `im.message.receive_v1`，模式選**长连接** |
| 4 | 添加应用能力 | 開啟**机器人** |
| 5 | 版本管理 | 创建版本 → 申请发布 → 管理員審核 |
| 6 | 可用范围 | 確認包含你（否則搜不到這個 bot） |

## 2. 填進 .env

```bash
FEISHU_APP_ID=cli_aXXXXXXXX
FEISHU_APP_SECRET=xxxxxxxx
FEISHU_CONNECTION_MODE=websocket
FEISHU_GROUP_POLICY=open
FEISHU_REQUIRE_MENTION=true
FEISHU_ALLOW_BOTS=none      # PM 只跟你對話，不理其他 bot
```

## 3. 重啟並驗證

```bash
docker compose up -d
docker compose logs -f pm | grep -i feishu
```

日誌應出現 Feishu 連線成功。然後在 Feishu 私訊這個 bot：`你是誰？`

## 4. 之後要讓 PM 跟其他 bot 對話

改 `FEISHU_ALLOW_BOTS=mentions`（只回應 @ 到自己的 bot 訊息），重啟。
`gateway.bot_loop_guard` 已經預設開啟（20 事件 / 5 分鐘 → 冷卻 10 分鐘），防止互刷。

## 常見問題

| 症狀 | 原因 |
|---|---|
| 搜不到 bot | App 未發布／可用範圍不含你／機器人能力沒開 |
| 私訊沒回應 | `FEISHU_ALLOWED_USERS` 空值時的配對流程，或 gateway 沒起來 |
| 群裡沒回應 | `FEISHU_REQUIRE_MENTION=true` 但你沒 @ 它 |
| 一直重連 | App Secret 錯，或同一個 App 被兩個容器同時連（一 App 只能用一處） |

> ⚠️ **同一個 App ID 不能同時給兩個 agent 用** —— 會互搶長連線。第二個 agent 要建第二個 App。
