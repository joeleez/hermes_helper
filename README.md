# hermes_helper — 一句 `docker compose up` 起一個 Hermes Agent

這個 repo 是**框架**，不是資料。

- `docker compose up -d` → 起一個叫 **PM** 的 agent（專案經理型）
- 每個 agent 的記憶、對話、技能都住在 **named volume**（`hermes-pm-data`），不在 repo 內
- 秘密只放在 `.env`（已 gitignored，而且有 pre-commit hook 攔截）

## 快速開始

```bash
git clone https://github.com/joeleez/hermes_helper.git
cd hermes_helper
cp .env.example .env        # 填入模型金鑰與 Feishu App
docker compose up -d
docker compose logs -f pm
```

首次啟動會自動初始化 `/opt/data`（SOUL、skills、config、空記憶骨架）。
之後再啟動**不會**覆蓋 —— agent 學到的東西會留下來。

## 換機器 / 重建

```bash
./scripts/backup.sh                 # 導出 volume 到 D:\hermes-backups
./scripts/restore.sh <備份檔>       # 還原（會先停容器）
```

## 常用指令

| 想做 | 指令 |
|---|---|
| 啟動 | `docker compose up -d` |
| 看日誌 | `docker compose logs -f pm` |
| 進容器 | `docker compose exec pm bash` |
| 停止 | `docker compose stop` |
| 更新映像 | `docker compose pull && docker compose up -d` |
| 備份 | `./scripts/backup.sh` |
| 同步技能 | `./scripts/sync-skills.sh --apply` |

## 架構

```
docker-compose.yml   PM 服務定義（1 個 agent / 1 個 Feishu App）
agents/pm/SOUL.md    PM 人格（只在首次初始化時種入）
skills/              共用技能（同上）
scripts/entrypoint.sh 首次 seed + 啟動
scripts/backup.sh    從 named volume 導出 tar.gz
.env.example         參數模板（.env 才是真的，且永不進 git）
```

## 安全規則

1. `.env` 永不進 git —— `.gitignore` + `.githooks/pre-commit` 雙重攔截
2. 記憶與對話永不進 git —— 它們在 volume 裡
3. 備份檔含 secrets（`/opt/data/.env`）→ 放加密槽或受控目錄

## 文件

- [`docs/01-quickstart.md`](docs/01-quickstart.md) — 從零到能對話
- [`docs/02-feishu.md`](docs/02-feishu.md) — 接 Feishu
- [`docs/03-backup-restore.md`](docs/03-backup-restore.md) — 備份與還原演練
- [`docs/04-migrate-memory.md`](docs/04-migrate-memory.md) — 把舊 agent 的記憶搬進來
