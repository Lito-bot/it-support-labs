# RB-1001 — New hire onboarding (Finance)

> Reproduced end to end in the Riverbend lab. Every step below has captured output in [`evidence/`](../evidence/).

| Field | Value |
|---|---|
| **Ticket ID** | RB-1001 |
| **Type** | Service request — onboarding |
| **Priority** | P3 — start date is tomorrow |
| **Requested by** | Tomás Ferreyra (Finance Manager), via HR form |
| **SLA** | Account ready before the employee's first logon |

## Request

> "Nicolás Vega starts tomorrow as Junior Accountant in Finance, Buenos Aires office. He needs the usual Finance access."

## Agent notes

**08:13** — Confirmed the request came through the HR form with the manager as requester (no ad-hoc requests from the new hire). Ran:

```powershell
New-RiverbendUser -GivenName 'Nicolás' -Surname 'Vega' -Department Finance `
  -Title 'Junior Accountant' -Office 'Buenos Aires' -Ticket RB-1001
```

The tool generated the login name `nicolas.vega` (accent stripped, collision-checked), created the account in `OU=Finance`, added `GG-Finance` + `GG-All-Staff`, set a random 16-character temporary password and **forced a change at first logon**. The action was written to the audit log with this ticket number. → [`RB-1001-onboarding.txt`](../evidence/RB-1001-onboarding.txt)

**08:14** — Temporary password handed to the manager out of band. It is not written in this ticket or sent by email.

**08:35** — First logon on WS01 as `RIVERBEND\nicolas.vega`. Windows required a password change before the desktop loaded, as intended. → [`RB-1001-first-logon-must-change.png`](../evidence/RB-1001-first-logon-must-change.png)

**08:37** — Verified from the user's own session: **Finance (F:)** and **Public (P:)** were mapped on the first logon, and no other department drives appeared. → [`RB-1001-drive-maps-first-logon.png`](../evidence/RB-1001-drive-maps-first-logon.png)

**08:38** — `gpresult` confirms why: the user object sits in `OU=Finance`, receives `USR - Drive Maps`, and holds the `GG-Finance` membership the drive-map targeting checks. → [`RB-1001-gpresult.txt`](../evidence/RB-1001-gpresult.txt)

## Resolution

Account created, correct access verified from the user's side (not just "the account exists"). Closed.

**Tags:** `onboarding` `active-directory` `group-policy` `drive-mapping` `least-privilege`
