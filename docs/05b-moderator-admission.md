# 05b — 主持人收訊設定（env 才是真相）

## 為什麼寫在 env 而不是 config.yaml

adapter 讀 `group_rules` 走 config.yaml，但 `require_mention` 的實際判定來自
**`FEISHU_REQUIRE_MENTION` 環境變數**（預設 `true`）。實測：只寫 config.yaml 的
`feishu.group_rules.<chat>.require_mention=false`，未 @ 的群訊息仍在門口被丟掉，
`state.db` 完全沒有寫入。

所以主持人要在 `.env.pm` 設：

```
AGENT_NAME=pm
FEISHU_REQUIRE_MENTION=false
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
