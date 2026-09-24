# RB-1006 — Leaver: disable access today

> Reproduced in the Riverbend lab, including a logon attempt before and after. Output: [`evidence/RB-1006-offboarding.txt`](../evidence/RB-1006-offboarding.txt)

| Field | Value |
|---|---|
| **Ticket ID** | RB-1006 |
| **Type** | Service request — leaver |
| **Priority** | P1 — access must be removed at end of day |
| **Requested by** | HR |

## Request

> "Hannah Schmidt (Recruiter) leaves today. Please remove all access at 17:00."

## Agent notes

**08:50** — Confirmed the account worked before the change, so the "after" test means something:

```
Before - logon from WS01 as hannah.schmidt: riverbend\hannah.schmidt
```

Ran the leaver process:

```powershell
Invoke-RiverbendOffboarding -SamAccountName hannah.schmidt -Ticket RB-1006
```

In order, it:
1. **Saved her group memberships to a CSV** before touching anything (`GG-All-Staff`, `GG-HR`), in case HR reverses the decision or an auditor asks what she had.
2. Disabled the account.
3. Replaced the password with a random one nobody knows.
4. Removed every group membership.
5. Moved the object to `OU=Disabled Users` and stamped the description `Offboarded 2026-09-24 (RB-1006). Delete after 2026-10-24.`

The account is **disabled, not deleted**. Deleting on day one destroys the audit trail and any mailbox or file ownership that still has to be handed over.

**08:51** — Verified:

```
After - logon from WS01 as hannah.schmidt:
The specified user account on the guest is restricted and can't be used to logon
```

Also tried a password reset on the disabled account, as a stand-in for a later "can you reset Hannah's password?" request. It was refused: `hannah.schmidt is disabled - resets on disabled accounts need HR approval.`

## Resolution

Access removed and verified. The 30-day purge date is picked up by the monthly audit ([RB-1007](RB-1007-stale-account-audit.md)). Closed.

**Tags:** `offboarding` `leaver` `access-removal` `audit-trail` `active-directory`
