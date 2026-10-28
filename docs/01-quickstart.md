# 01 — 從零到能對話（10 分鐘）

## 0. 前置：Docker 與 WSL

```bash
docker --version            # 需要 Docker Desktop 或 Docker Engine
docker compose version
```

WSL 裡沒有 docker CLI 時，用 Windows 端：

```bash
export PATH="/mnt/c/Program Files/Docker/Docker/resources/bin:$PATH"
```

## 1. Clone 與設定

```bash
git clone https://github.com/joeleez/hermes_helper.git
cd hermes_helper
git config core.hooksPath .githooks     # 啟用防洩漏 hook（強烈建議）
cp .env.example .env
```

編輯 `.env`，至少填：

```
HERMES_MODEL=deepseek:deepseek-chat     # 換成你的 provider:model
DEEPSEEK_API_KEY=你的key                 # 對應 provider 的金鑰
```

Feishu 先留空也能啟動（只是不能從 Feishu 對話）。

## 2. 啟動

```bash
docker compose up -d
docker compose logs -f pm
```

首次啟動日誌會看到：

```
[entrypoint][pm] 首次啟動：初始化 /opt/data
[entrypoint][pm] 已安裝 SOUL.md
[entrypoint][pm] 已安裝 skills：agent-handoff pm-orchestration
[entrypoint][pm] 已產生 config.yaml（model=...）
[entrypoint][pm] 已寫入 .env（2 個變數）
[entrypoint][pm] 啟動：hermes gateway
```

## 3. 驗證

```bash
docker compose ps                       # 狀態要是 running / healthy
docker compose exec pm ls /opt/data     # 應看到 config.yaml skills memories SOUL.md
docker compose exec pm cat /opt/data/config.yaml
```

**記憶與對話不會出現在 repo 裡** —— 它們在 volume `hermes-pm-data`：

```bash
docker volume inspect hermes-pm-data          # 看 mountpoint
docker run --rm -v hermes-pm-data:/data alpine ls -la /data
```

## 4. 跟它說話

```bash
docker compose exec pm hermes chat
```

第一句建議問：`你是誰？你的工作流程是什麼？`

**預期**：它說自己是 PM、提到「收單→拆解→派工→驗收→匯報」。如果像一般聊天機器人，代表 SOUL.md 沒進去 —— 檢查 `docker compose exec pm cat /opt/data/SOUL.md`。

## 5. 停止與重啟

```bash
docker compose stop          # 停，資料留著
docker compose up -d         # 再起，記憶還在
docker compose down          # 刪容器，volume 還在（安全）
docker compose down -v       # ⚠️ 連 volume 一起刪 = 記憶消失
```

**永遠不要加 `-v`。**
