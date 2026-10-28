#!/usr/bin/env bash
# backup.sh — 把 named volume 導出成 tar.gz（含 SQLite 一致性備份）
#
# 用法： ./scripts/backup.sh [目標目錄]
#        預設 /mnt/d/hermes-backups（不存在則 ~/hermes-backups）
#
# 原理：起一個臨時 alpine 容器，同時掛載 volume 與目標目錄，在裡面打包。
#      不經過 Windows 檔案系統，所以快且不受權限問題影響。
set -euo pipefail

VOLUME="${VOLUME:-hermes-pm-data}"
DEST="${1:-}"
if [ -z "$DEST" ]; then
  if [ -d /mnt/d ]; then DEST=/mnt/d/hermes-backups; else DEST="$HOME/hermes-backups"; fi
fi
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="hermes-${VOLUME#hermes-}-$STAMP.tar.gz"
KEEP="${KEEP:-7}"

mkdir -p "$DEST"
echo "volume：$VOLUME"
echo "目標：$DEST/$OUT"

docker volume inspect "$VOLUME" >/dev/null 2>&1 || {
  echo "✗ 找不到 volume：$VOLUME（先啟動過容器才會有）"; exit 1; }

# 打包前先讓 SQLite 做一次 checkpoint（若容器在跑，用 docker exec 較安全）
if docker ps --format '{{.Names}}' | grep -qx "hermes-pm"; then
  docker exec hermes-pm bash -lc \
    'command -v sqlite3 >/dev/null && sqlite3 /opt/data/state.db "PRAGMA wal_checkpoint(TRUNCATE);" || true' \
    2>/dev/null || true
fi

docker run --rm \
  -v "$VOLUME":/data:ro \
  -v "$DEST":/backup \
  alpine:3 sh -c "cd /data && tar czf '/backup/$OUT' ."

# 驗證：能列出內容且含 config.yaml
if docker run --rm -v "$DEST":/backup alpine:3 sh -c "tar tzf '/backup/$OUT'" 2>/dev/null | grep -q '^\./config\.yaml$'; then
  echo "✓ 備份完成並驗證：$DEST/$OUT ($(du -h "$DEST/$OUT" | cut -f1))"
else
  echo "✗ 備份內容不完整（缺 config.yaml），請檢查"; exit 1
fi

# 保留策略
ls -1t "$DEST"/hermes-*.tar.gz 2>/dev/null | tail -n +$((KEEP+1)) | while read -r old; do
  rm -f "$old"; echo "  刪除舊備份：$(basename "$old")"
done
