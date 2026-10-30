# 05 — 三層結構：操作者 / 主持人 / 功能 agent

```
第 1 層  操作者（宿主，有 Docker）      建 agent、啟停、改 repo
   │  你下指令
   ▼
第 2 層  主持人（容器內，無 Docker）     讀名冊 → 自己答或派工
   │  @ 目標
   ▼
第 3 層  功能 agent（各自容器）          只在被 @ 時回應
```

## 各層的權限

| | 第 1 層 操作者 | 第 2 層 主持人 | 第 3 層 功能 agent |
|---|---|---|---|
| Docker | ✅ | ❌ | ❌ |
| 改 repo | ✅ | ❌ | ❌ |
| 讀名冊 | ✅ | ✅ | ❌ |
| 對人類說話 | ❌（不進群） | ✅ | ✅（被 @ 時） |
| 建立 agent | ✅ | ❌（只能寫規格） | ❌ |

**agent 永遠不能往上叫。** 要新增 agent，永遠是人類 → 操作者。

## 名冊怎麼來

每個 agent 一個 `agents/<name>/agent.yml`：

```yaml
name: reviewer
title: 審查員
description: 審查方案與程式碼，專找漏洞與邊界條件
capabilities: [風險清單, 邊界條件, 測試缺口]
cannot: [改程式碼, 決定優先級]
feishu:
  open_id: ""          # 留空，gen-roster 會自動抓
  require_mention: true
```

生成：

```bash
./scripts/gen-roster.sh oc_你的群id
```

它會：

1. 合併所有 `agent.yml`
2. 用 Feishu API 列出群成員，按名稱比對自動補 `open_id`
3. 寫出 `agents/roster.yaml`（進 git，可審計）

名冊在每次容器啟動時被複製到 `/opt/data/roster.yaml`，主持人讀那份。

## 讓主持人「不需 @ 也收訊息」

```bash
./scripts/apply-group-rules.sh oc_你的群id
docker compose restart pm
```

只對指定群生效；其他群維持原本規則。其他 agent **不要**這樣設 —— 它們只需要在被 @ 時回應。

## 加一個新功能 agent

1. **你** 在飛書後台建一個新應用（拿到 App ID / Secret）
2. **你** 把憑證寫進該 agent 的 `.env`（用 `read -s`，不要貼聊天）
3. **操作者**（後台管理員）：
   ```bash
   mkdir -p agents/reviewer
   # 寫 agents/reviewer/SOUL.md 與 agent.yml
   # 在 docker-compose.yml 加一個 service
   ./scripts/gen-roster.sh oc_你的群id
   docker compose up -d reviewer
   ```
4. 新 bot 拉進群 → 名冊自動包含它

## 三種失效模式

| 情況 | 主持人應該 |
|---|---|
| 不知道派給誰 | 自己答，或反問一個具體問題（不能沉默） |
| 被派的 agent 答不出 | 回報「reviewer 說缺少 X 資訊」 |
| 兩個 agent 矛盾 | 並列兩方結論 + 分歧點，由人類裁決 |

## 防迴圈

1. 主持人只轉派**人類**的訊息，不轉派 bot 的回覆
2. 功能 agent `ALLOW_BOTS=none` —— 只回 @ 它的訊息，不會再 @ 別人
3. `gateway.bot_loop_guard`（預設開）20 事件 / 5 分鐘 → 冷卻 10 分鐘
