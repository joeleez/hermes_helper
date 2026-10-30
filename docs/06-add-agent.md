# 06 — 加第二個 agent（NGB 程式開發員為例）

一個 agent = 一個 Feishu 自建應用 + 一個 container + 一個 named volume + 一個 `agents/<name>/`。

## 1. 飛書後台建應用

- 名稱：`NGB 程式開發員`
- 權限：`im:message`、`im:message:send_as_bot`、`im:chat:readonly`、`im:resource`
- 事件：`im.message.receive_v1`（長連線）
- 能力：機器人 → 發布 → 審核

拿到 `App ID` / `App Secret`。

## 2. 寫憑證（不要貼聊天）

```bash
cd /home/projects/hermes_helper
read -rsp "App ID: " ID; echo
read -rsp "App Secret: " SEC; echo
printf 'AGENT_NAME=developer\nFEISHU_APP_ID=%s\nFEISHU_APP_SECRET=%s\n' "$ID" "$SEC" > .env.developer
unset ID SEC
chmod 600 .env.developer
```

## 3. 加 agent 定義

```
agents/developer/agent.yml   # title / description / capabilities / cannot
agents/developer/SOUL.md     # 行為準則
```

`agent.yml` 的 `description` 是主持人判斷「該不該派給它」的依據 —— 一句話講清楚專長。

## 4. 加 container

`docker-compose.yml` 複製 `pm` 的 service，改三個地方：

| 欄位 | pm | developer |
|---|---|---|
| `container_name` | `hermes-pm` | `hermes-developer` |
| `AGENT_NAME` | `pm` | `developer` |
| volume | `pm-data` | `developer-data` |
| `env_file` | `.env` | `.env` + `.env.developer` |

## 5. 啟動

```bash
docker compose up -d developer
docker compose logs -f developer
```

首次啟動會看到 `[seed:developer] 首次啟動…` 與 `SOUL.md ← agents/developer/SOUL.md`。

## 6. 拉進群 + 更新名冊

在飛書把新 bot 拉進 `ngb測試用` 群，然後：

```bash
./scripts/gen-roster.sh oc_0de516cac9ef4b6d213464b7b601fcd8
docker compose restart pm        # 主持人重新載入名冊
```

名冊裡應該出現 developer 的 `open_id`。若顯示「⚠ 缺 open_id」，代表 bot 還沒進群。

## 7. 驗證派工

在群裡請主持人派一件事給它：

```
叫 developer 用 pm-orchestration 的格式，把「新增一個 /health endpoint」寫成任務卡
```

預期：主持人回「已交給 NGB 程式開發員」，然後 developer 在群裡回覆（因為被 @）。

## 注意

- 兩個 agent 用**不同的 App**。同一個 App ID 不能被兩個 gateway 同時長連線。
- developer 的 `require_mention: true` —— 它只在被 @ 時回應，不會插嘴。
- 如果要讓 agent 之間互相討論：主持人的群規則已設 `require_mention: false`，
  且雙方 `FEISHU_ALLOW_BOTS=mentions`。
