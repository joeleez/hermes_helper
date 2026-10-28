#!/usr/bin/env bash
# restore.sh — 從備份還原到 named volume
#
# 用法： ./scripts/restore.sh <備份檔.tar.gz>
#
# 安全性：會先停容器、把現有 volume 內容另存為 pre-restore-<時間>.tar.gz 再覆蓋。
set -euo pipefail

ARCHIVE="${1:-}"
VOLUME="${VOLUME:-hermes-pm-data}"
CONTAINER="${CONTAINER:-hermes-pm}"

[ -n "$ARCHIVE" ] || { echo "用法：$0 <備份檔.tar.gz>"; exit 1; }
[ -f "$ARCHIVE" ] || { echo "✗ 找不到檔案：$ARCHIVE"; exit 1; }

echo "1/4 停止容器（若有）"
docker stop "$CONTAINER" >/dev/null 2>&1 || true

DIR="$(cd "$(dirname "$ARCHIVE")" && pwd)"
FILE="$(basename "$ARCHIVE")"

echo "2/4 先把現有資料另存（出錯可回退）"
SAFE="pre-restore-$(date +%Y%m%d-%H%M%S).tar.gz"
if docker run --rm -v "$VOLUME":/data:ro -v "$DIR":/backup alpine:3 \
     sh -c "cd /data && tar czf '/backup/$SAFE' . 2>/dev/null"; then
  echo "   已保存：$DIR/$SAFE"
else
  echo "   （volume 可能是空的，跳過）"
fi

echo "3/4 清空並還原"
docker run --rm -v "$VOLUME":/data -v "$DIR":/backup alpine:3 \
  sh -c "rm -rf /data/* /data/..?* /data/.[!.]* 2>/dev/null; cd /data && tar xzf '/backup/$FILE'"

echo "4/4 驗證"
docker run --rm -v "$VOLUME":/data:ro alpine:3 \
  sh -c 'ls /data && test -f /data/config.yaml && echo "✓ config.yaml 存在"'

echo
echo "完成。啟動：docker compose up -d"
echo "若行為不對，回退：$0 $DIR/$SAFE"
