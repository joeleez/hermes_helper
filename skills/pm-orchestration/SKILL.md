---
name: pm-orchestration
description: "Run a project: intake, breakdown, delegate, verify, report."
version: 1.0.0
author: hermes-pm
license: MIT
metadata:
  hermes:
    tags: [pm, planning, delegation, delivery]
---

# PM Orchestration

Use when taking on a piece of work end to end: framing it, splitting it, handing parts out, and proving it landed.

## 1. Intake (never skip)

Confirm four things before any planning. If one is missing, ask — do not guess:

| Field | Bad | Good |
|---|---|---|
| 產出物 | 「一個網站」 | 「一個 `todo/` 目錄，含 index.html/style.css/app.js」 |
| 完成定義 | 「能用」 | 「開 index.html 可以新增/勾選/刪除，重整後資料還在」 |
| 限制 | 「快一點」 | 「今天做完，不要加 npm 依賴」 |
| 驗收人 | 「你」 | 「你自己在瀏覽器點一次」 |

## 2. Breakdown

Split until each unit is one sitting of work. Write a task card per unit:

```
任務：<動詞開頭的一句話>
產出：<檔案 / 連結 / 指令輸出>
完成定義：<可驗證條件>
驗證方式：<誰、怎麼驗>
依賴：<前置任務>
```

A card with no verifiable 驗證方式 is not ready — keep breaking it down or ask.

## 3. Sequencing

Order by: **解鎖其他任務的能力** > 風險最高的 > 最確定能做的。

Put anything that may block the whole project on day one (access, approvals, data availability).
A three-day wait for an approval discovered on day three is a schedule failure; discovered on day one it is just a plan.

## 4. Delegation

Every handoff states:

- Scope: which files / which branch rules (e.g. "PR only, never touch existing branches")
- Forbidden: secrets, CI config, other people's branches
- Return format: diff summary, test output, PR link

If the executor is an AI agent, add: "do not run git; do not report success without evidence".

## 5. Verification (do not accept self-reports)

| Claim | What counts as proof |
|---|---|
| 測試通過 | the actual test output, with counts |
| PR 已開 | the PR URL, fetched back and confirmed |
| 功能正常 | someone clicked it, or an automated check hit the real endpoint |
| 部署成功 | a request to the live URL returning the expected response |

**The executor's own summary is never evidence.**

## 6. Reporting

Three fixed sections, every time:

```
## 現況   (what shipped, with evidence)
## 風險   (blocked items, unverified assumptions, decisions needed)
## 下一步 (what I will do next, what you must decide)
```

No narration of the process. No adjectives in place of numbers.

## 7. Failure modes to watch for

- **假完成**：把「看起來好了」當「好了」。名字要改：部分完成 → 明確說是部分完成。
- **範圍蔓延**：任務外的順手修改。發現就問，不要自己加。
- **驗證外包**：把驗證推給委託者卻說「已完成」。驗證是 PM 的工作。
- **沉默的假設**：所有未確認的假設都要寫進匯報的「風險」段。
