# RB-1007 — Monthly account hygiene audit

> Run in the Riverbend lab. Output: [`evidence/RB-1007-stale-account-audit.txt`](../evidence/RB-1007-stale-account-audit.txt)

| Field | Value |
|---|---|
| **Ticket ID** | RB-1007 |
| **Type** | Scheduled task — access review |
| **Priority** | P4 |
| **Requested by** | Recurring, first business day of the month |

## Request

> "Monthly review: list accounts that shouldn't be active."

## Agent notes

**08:51** — Ran `Get-StaleAccountReport -InactiveDays 90`. It flags four things:

| Rule | Why it matters |
|---|---|
| No logon in 90+ days | Forgotten accounts are the ones nobody notices being used by someone else |
| Never logged on (14+ days after creation) | Onboarded for someone who never started, or a typo'd duplicate |
| Password never expires | Usually a service account whose password nobody has rotated in years |
| Disabled and past purge date | Leavers from [RB-1006](RB-1006-offboarding.md) whose 30 days are up |

Result:

```
13  Never logged on (new account)
 1  Password never expires       ← svc-scan2mail
```

**The real finding:** `svc-scan2mail`, the copier's scan-to-email account, has **Password never expires**. It was seeded for this exercise, but it is the most common thing this kind of audit turns up in a real domain. Next step: rotate the password, record the owner, and move it to a managed service account (gMSA) if the copier supports it.

The 13 "new account" entries are expected: the lab was built today, and those users have not signed in yet. The report labels them separately so they don't bury the real finding.

Report exported to `C:\HelpDesk\stale-accounts-2026-09.csv` for the reviewer.

## Honest limitation

A freshly built lab has no accounts that are really 90 days stale, and `lastLogonTimestamp` can't be backdated. The 90-day rule is implemented, but this run did not exercise it with real data.

**Tags:** `access-review` `service-accounts` `audit` `reporting` `powershell`
