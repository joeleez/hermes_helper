# 05b — 主持人收訊設定（三層門檻）

## 定案（2026-10-30）

| 層 | 設定 | 值 | 為什麼 |
|---|---|---|---|
| ① Feishu 應用權限 | `im:message.group_msg` | **必須開**（免審） | 沒有它，bot 收不到任何「沒 @ 它」的群訊息 —— 人類的問題、專員的回覆，全部收不到 |
| ② adapter | `FEISHU_ALLOW_BOTS` | `all`（主持人） | 專員不會 @ 任何人，所以主持人只能靠「全收」才聽得到回報 |
| ③ adapter | `FEISHU_REQUIRE_MENTION` | `false`（主持人） | 你講話不必先 @ 它 |
| 專員側 | `FEISHU_ALLOW_BOTS` / `require_mention` | `none` / `true` | 專員只在被點名時回應，不理其他 bot，永不 @ 人 |

三層缺一不可。②③ 是 adapter 的開關，①才是「訊息到不到得了」的門。

## 對話規則（配合上面的設定）

- **專員不 @ 任何人**（包括主持人與其他專員）—— `@` 是派工權，只屬於主持人
- 專員若要交接，用**名字**寫：「A、B 完成；C 建議由 reviewer 接手」
- 主持人收到後自行決定：值得派就自己 @ 那位成員（附任務卡），不值得就回一句「要求已完成」
- 跳數上限 3 跳，同一專員在一條對話裡不得被派兩次

## 為什麼寫在 env 而不是 config.yaml

adapter 讀 `group_rules` 走 config.yaml，但 `require_mention` 的實際判定來自
**`FEISHU_REQUIRE_MENTION` 環境變數**（預設 `true`）。實測：只寫 config.yaml 的
`feishu.group_rules.<chat>.require_mention=false`，未 @ 的群訊息仍在門口被丟掉，
`state.db` 完全沒有寫入。

所以主持人要在 `.env.pm` 設：

```
AGENT_NAME=pm
FEISHU_REQUIRE_MENTION=false
FEISHU_ALLOW_BOTS=all
```

compose 的 `env_file` 順序是 `[.env, .env.pm]`，後者覆蓋前者，不影響其他 agent。

## 代價與風險

`FEISHU_REQUIRE_MENTION=false` 是**全群生效**，不只那一個群。主持人因此在任何被加入的群裡
都會處理所有訊息。對策：

1. 主持人只加入你批准的群（飛書可用範圍 + 你手動拉進群）
2. 想更精確：把 `FEISHU_GROUP_POLICY` 由 `open` 改成 `allowlist`，
   再把 `FEISHU_ALLOWED_USERS` 設成你的 user id —— 這樣只有你的訊息會被處理

## 驗證

```bash
./scripts/apply-group-rules.sh   # config 那層（保留，無害）
docker compose up -d pm
docker exec hermes-pm sh -c "grep -E 'REQUIRE_MENTION|GROUP_POLICY' /opt/data/.env"
```

然後在群裡**不要 @** 任何 bot 打一句話，檢查 `state.db` 有沒有新訊息：

```bash
docker exec hermes-pm ls -la /opt/data/state.db   # 時間應該剛剛更新
```
