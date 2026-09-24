# RB-1002 — Forgotten password

> Reproduced in the Riverbend lab. Output: [`evidence/RB-1002-password-reset.txt`](../evidence/RB-1002-password-reset.txt)

| Field | Value |
|---|---|
| **Ticket ID** | RB-1002 |
| **Type** | Incident — access |
| **Priority** | P2 — user fully blocked |
| **Reported via** | Phone |

## User report

> "I came back from holidays and I can't remember my password. Can you just reset it? I'm Tomás from Finance."

## Agent notes

**08:45** — A caller saying who they are is not identity verification. Password resets are the most common social-engineering request a service desk gets. Did not reset on the call.

**08:46** — Identity verified by **calling his manager back on the number in the company directory** (never a number the caller provides), who confirmed Tomás was the one asking. *(Narrated step: there is no one to phone in a lab. The command below records the method used, and the tool refuses to run without one.)*

**08:48** — Reset with the recorded verification method:

```powershell
Reset-RiverbendPassword -SamAccountName tomas.ferreyra -Ticket RB-1002 -IdentityVerifiedBy CallbackToManager
```

The tool will not run without `-IdentityVerifiedBy`, forces a change at next logon, unlocks the account if it was locked (it was not), and writes who/why/how-verified to the audit log. The temporary password was read to the user on the verified callback and is not in this ticket.

## Resolution

Password reset after verified identity; user must choose a new password at logon. Closed.

**Why the guard rails matter:** the same tool **refuses** to reset a disabled account (see [RB-1006](RB-1006-offboarding.md)), so a reset request can never quietly bring a leaver's account back.

**Tags:** `password-reset` `identity-verification` `social-engineering` `audit-trail`
