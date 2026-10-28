# 03 — 備份與還原

資料在 named volume `hermes-pm-data` 裡，**不在 repo**。所以備份要用 Docker 操作。

## 每日備份

```bash
./scripts/backup.sh                   # 預設到 /mnt/d/hermes-backups
./scripts/backup.sh /mnt/e/backups    # 指定目錄
KEEP=30 ./scripts/backup.sh           # 保留 30 份
```

腳本做四件事：

1. 若容器在跑，先讓 SQLite 做 `wal_checkpoint(TRUNCATE)`
2. 起臨時 alpine 容器，把 volume 打包成 `hermes-pm-YYYYMMDD-HHMMSS.tar.gz`
3. **驗證**清單裡有 `config.yaml`，否則報失敗
4. 只保留最近 7 份

## 還原

```bash
./scripts/restore.sh /mnt/d/hermes-backups/hermes-pm-20261028-223000.tar.gz
```

腳本會：

1. 停容器
2. 先把現有 volume 另存 `pre-restore-<時間>.tar.gz`（可回退）
3. 清空 volume、解開備份
4. 驗證 `config.yaml` 存在
5. 提示 `docker compose up -d`

## 每月演練（重要）

沒演練過的備份不算備份。

```bash
# 1. 備份
./scripts/backup.sh

# 2. 把備份解到臨時目錄檢查
mkdir -p /tmp/hp-check
docker run --rm -v /mnt/d/hermes-backups:/backup:ro -v /tmp/hp-check:/out alpine:3 \
  sh -c "tar xzf /backup/hermes-pm-*.tar.gz -C /out && ls /out"

# 3. 檢查 SQLite
python3 - <<'PY'
import sqlite3
c = sqlite3.connect('/tmp/hp-check/state.db')
print('integrity:', c.execute('PRAGMA integrity_check').fetchone()[0])
print('messages :', c.execute('SELECT COUNT(*) FROM messages').fetchone()[0])
PY
```

`integrity: ok` 且訊息數合理 → 這份備份可用。

## 自動化（WSL systemd timer）

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/hermes-backup.service <<'EOF'
[Unit]
Description=Backup hermes-pm volume
[Service]
Type=oneshot
ExecStart=/home/%u/hermes_helper/scripts/backup.sh
EOF

cat > ~/.config/systemd/user/hermes-backup.timer <<'EOF'
[Unit]
Description=Daily hermes-pm backup
[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true
[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now hermes-backup.timer
systemctl --user list-timers | grep hermes
```

## 3-2-1 原則

| 份數 | 位置 |
|---|---|
| 3 份 | 每日 7 份中最新的幾份 |
| 2 種介質 | D 槽 + 外接碟或加密雲端 |
| 1 份離機 | 每月複製一份到另一台機器/雲端（加密後） |

⚠️ 備份檔內含 `/opt/data/.env`（Feishu secret、模型 key）→ **當密碼檔保管**。
