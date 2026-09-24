# RB-1005 — Internal transfer: Operations → Finance

> Reproduced in the Riverbend lab. Output: [`evidence/RB-1005-department-transfer.txt`](../evidence/RB-1005-department-transfer.txt)

| Field | Value |
|---|---|
| **Ticket ID** | RB-1005 |
| **Type** | Service request — mover |
| **Priority** | P3 — effective Monday |
| **Requested by** | HR |

## Request

> "Aisha Bello moves from Operations to Finance as Financial Analyst from Monday. Please update her access."

## Agent notes

**08:50** — Before:

```
Department : Operations      OU : OU=Operations
Groups     : GG-All-Staff, GG-Operations
```

The classic mover mistake is to **add** the new department's access and forget to **remove** the old one. After a few transfers, one person can read half the company's shares. The tool swaps groups instead of stacking them:

```powershell
Move-RiverbendUserDepartment -SamAccountName aisha.bello -NewDepartment Finance `
  -NewTitle 'Financial Analyst' -Ticket RB-1005
```

After:

```
Department : Finance         OU : OU=Finance
Title      : Financial Analyst
Groups     : GG-All-Staff, GG-Finance
```

Moving her object to `OU=Finance` matters too: that is what the drive-map GPO and any future Finance policies target.

**08:51** — Ran the same command a second time on purpose (a duplicate ticket is a realistic mistake). It refused: `aisha.bello is already in Finance.`

## Resolution

Old access removed, new access granted, directory attributes updated for the org chart and HR reports. Audit log entry written. Closed.

**Tags:** `mover` `access-review` `privilege-creep` `active-directory`
