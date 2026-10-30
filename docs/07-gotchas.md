# 07 — 踩過的坑（實測紀錄）

## 1. 改了 bind-mount 的檔案，容器起不來

**症狀**

```
error mounting ".../99-seed-agent": no such file or directory
runc create failed: error during container init
```

**原因**：`docker-compose.yml` 把 `scripts/seed-agent.sh` 綁進 `/etc/cont-init.d/`。
`git pull` 會**刪掉再重建**檔案（新 inode），Docker 記住的掛載參照失效。

**解法**

```bash
docker compose up -d --force-recreate pm developer
```

`restart` 不夠，一定要 `--force-recreate`。

## 2. seed 只在「第一次」複製 skills

`seed-agent.sh` 的首次初始化用 marker（`/opt/data/.seeded-by-hermes-helper`）判斷。
之後 repo 新增 `skills/`，容器**不會**自動拿到。

```bash
CONTAINER=hermes-pm ./scripts/sync-skills.sh --apply
```

新 skill 上線三步：`sync-skills.sh --apply` → `git pull` →（若改 SOUL）`docker cp` + 重啟。

## 3. 機器人不在群成員 API 裡

`GET /open-apis/im/v1/chats/:id/members` 只回**人類**。
bot 不出現在清單，所以名冊不能靠掃群成員補 `open_id`。

```bash
./scripts/sync-open-ids.sh     # 用每個 agent 自己的 App 查 /bot/v3/info
```

## 4. 未 @ 的群訊息收不到

飛書只把「有 @ 到 bot」的群訊息推給它，除非應用有 `im:message.group_msg`（免審權限）。

- 主持人需要不 @ 也收 → 勾 `im:message.group_msg`
- 專員只需要被 @ → 不用勾，保持最小權限

## 5. `FEISHU_DOMAIN` 填錯

`feishu` = 中國版（open.feishu.cn）；`lark` = 國際版（open.larksuite.com）。
填錯的症狀：`connect failed, err: 1000040351: Incorrect domain name`。

## 6. 主持人用 `delegate_task` 冒充群成員

症狀：群裡出現「Delegating 1 tasks…」，但真正的成員從沒被 @。

原因：`moderator-routing` 技能沒同步進容器，模型只好用手上唯一的工具。
解法：同步技能 + SOUL 的硬規則（先讀名冊 → 用 `<at user_id>` 派工）。

## 7. 兩個 agent 共用一個 Feishu App

同一個 App ID 不能同時被兩個 gateway 長連線 —— 會互搶、斷線。
一個 agent 一個應用（`.env.<name>`），`docker compose` 的 `env_file` 順序要讓後者覆蓋前者。
