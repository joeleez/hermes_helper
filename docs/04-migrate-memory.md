# 04 — 把舊 agent 的記憶搬進來

情境：你已經有一個在跑 Hermes 的環境（例如 WSL 直裝的），想把它的記憶灌進這個 PM agent。

**記憶不經過 git。** 走 tar + 明確複製。

## 要搬什麼

| 東西 | 搬？ | 理由 |
|---|---|---|
| `memories/MEMORY.md`、`USER.md` | ✅ | 這就是「記憶」 |
| `skills/` | ⚠️ 選擇性 | repo 已有共用技能；只搬你自己寫的 |
| `cron/` | ⚠️ 看你 | 排程要不要延續 |
| `.env`、`auth.json` | ❌ | 重新輸入，不要複製 |
| `state.db` | ❌ | 4 MB+ 對話歷史，且含敏感內容 |

## 步驟

### 1. 停舊 agent（避免兩個寫同一份記憶）

```bash
hermes gateway stop
```

### 2. 打包（在舊環境）

```bash
tar czf /mnt/c/Users/User/pm-seed.tar.gz -C ~/.hermes memories config.yaml SOUL.md
tar tzf /mnt/c/Users/User/pm-seed.tar.gz | head      # 驗證可讀
```

### 3. 灌進 volume

容器要先起過一次（volume 才會存在）：

```bash
docker compose up -d
docker compose stop
docker run --rm \
  -v hermes-pm-data:/data \
  -v /mnt/c/Users/User:/seed:ro \
  alpine:3 sh -c "cd /seed && tar xzf pm-seed.tar.gz -C /data --strip-components=0"
docker compose up -d
```

### 4. 驗證（唯一可信方式）

問一個**只有舊 agent 才會答對**的問題：

```
我們之前把 MPF 快照存在哪裡？
```

答出 `~/mpf-snapshots/<月份>/` → 記憶接上了。
答不出 → `docker compose exec pm cat /opt/data/memories/MEMORY.md` 確認檔案在不在。

### 5. 清理

```bash
rm /mnt/c/Users/User/pm-seed.tar.gz      # 不要在 C: 留明文
```

## 記憶衝突怎麼辦

如果 repo 的 PM 是「專案經理」人格，而舊記憶是別的角色的經驗：

- **保留記憶，但調整人格** → 搬記憶，不搬 SOUL.md
- **只要人格** → 什麼都不搬，重新開始
- **兩者都要** → 先搬記憶，再人工把 `MEMORY.md` 裡與 PM 無關的條目刪掉（記憶上限 2200 字）

## 心理準備

新 agent 不會「記得」你的語氣、習慣、之前踩過的坑 —— 那些在 `USER.md` 和過去的對話裡。
搬 `MEMORY.md` + `USER.md` 能延續大約 80% 的連續感，剩下 20% 需要重新相處。
