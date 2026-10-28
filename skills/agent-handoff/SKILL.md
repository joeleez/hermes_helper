---
name: agent-handoff
description: "Move agent state between machines without leaking secrets."
version: 1.0.0
author: hermes-pm
license: MIT
metadata:
  hermes:
    tags: [migration, memory, backup, secrets]
---

# Agent Handoff

Use when an agent's state (memory, skills, cron) must move from one machine, profile, or container to another.

## What is state and where it lives

| Piece | Path under `$HERMES_HOME` | Portable? | Contains secrets? |
|---|---|---|---|
| 長期記憶 | `memories/MEMORY.md`, `memories/USER.md` | ✅ | 可能有（email、路徑、帳戶摘要） |
| 技能 | `skills/` | ✅ | 否 |
| 排程 | `cron/` | ✅ | 否（但可能含內部 chat id） |
| 設定 | `config.yaml` | ✅ | 否（金鑰在 .env） |
| 金鑰 | `.env`, `auth.json` | ⚠️ 可搬但要當密碼保管 | **是** |
| 對話歷史 | `state.db`, `sessions/` | ⚠️ 大且敏感 | 可能有 |

**Never put `.env`, `auth.json`, or `state.db` in git.** Anyone with the repo would own the agent's credentials and full transcript.

## Order of operations

1. **Stop the source agent.** Two processes on one home compound each other's memory. `hermes gateway stop` first.
2. **Back up, then verify the backup.**
   ```bash
   tar czf /path/hermes-state-$(date +%F).tar.gz -C ~ .hermes \
     --exclude='.hermes/cache' --exclude='.hermes/audio_cache'
   tar tzf /path/hermes-state-*.tar.gz | head        # listing proves it is readable
   ```
3. **Move only what the target needs.** Usually: `memories/`, `skills/`, `SOUL.md`, and hand-copied keys.
4. **Recreate secrets by hand.** Re-issuing an API key or re-running `gh auth login` costs 5 minutes and removes a permanent leak risk.
5. **Verify, don't assume.**
   - Skills visible: `hermes skills list` (or start a chat and ask what skills it has)
   - Memory loaded: ask a question whose answer is only in `MEMORY.md`
   - Cron present: `hermes cron list`

## Cross-WSL / cross-machine transfer

Two WSL distros cannot see each other's filesystem directly. Go through Windows:

```bash
# source distro
tar czf /mnt/c/Users/<user>/hermes-state.tar.gz -C ~ .hermes/memories .hermes/skills SOUL.md

# target distro
cd ~ && tar xzf /mnt/c/Users/<user>/hermes-state.tar.gz
rm /mnt/c/Users/<user>/hermes-state.tar.gz        # don't leave plaintext state on C:
```

## Checklist before declaring the handoff done

- [ ] Source agent stopped (no two writers)
- [ ] Backup created **and** listing verified
- [ ] Secrets re-issued, not copied
- [ ] Memory answer-tested with a question only the old agent could answer
- [ ] Cron jobs listed and their next run times sane
- [ ] Old copy left untouched for one week, then removed deliberately
