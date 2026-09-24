# RB-1004 — "Access denied" saving the Finance price list

> Reproduced in the Riverbend lab as the real user from WS01. Output: [`evidence/RB-1004-read-only-by-design.txt`](../evidence/RB-1004-read-only-by-design.txt)

| Field | Value |
|---|---|
| **Ticket ID** | RB-1004 |
| **Type** | Incident → converted to access request |
| **Priority** | P3 |
| **Reported via** | Email |

## User report

> "I can open the Q3 price list on the Finance drive but when I try to save my changes it says access denied. Please fix my permissions, I need to add a discount for ACME today." — Kevin O'Brien, Sales Manager

## Agent notes

**08:49** — Reproduced as the user, not as an admin (an admin account would succeed and prove nothing):

```
PS> Get-Content \\DC01\Finance\Q3-price-list.txt
Riverbend Q3 price list (lab sample data)

PS> Add-Content \\DC01\Finance\Q3-price-list.txt 'Discount 15% for ACME'
ERROR: Access to the path '\\DC01\Finance\Q3-price-list.txt' is denied.
```

**08:50** — Traced the permission chain:

```
kevin.obrien → GG-Sales → DL-Share-Finance-RO → ReadAndExecute on C:\Shares\Finance
```

This is **intentional**: Sales was given read-only access to Finance so they can quote from the price list, while Finance owns the numbers.

## Resolution

Not a fault, so no permissions changed. Replied to the user explaining why, and routed the change itself to the data owner:

> "Hi Kevin, this one is working the way it was set up: Sales can read the Finance price list but only Finance can change it, so prices stay consistent for everyone. I've passed your ACME discount to Tomás Ferreyra (Finance Manager), who owns that file. If Sales needs to edit it regularly, Tomás can approve write access and I'll set it up the same day."

**Why not just add him to the RW group:** it would fix today's request and quietly break the rule that Finance controls pricing. Access changes go through the resource owner, not through whoever asks loudest.

**Tags:** `permissions` `ntfs` `agdlp` `access-request` `data-owner` `communication`
