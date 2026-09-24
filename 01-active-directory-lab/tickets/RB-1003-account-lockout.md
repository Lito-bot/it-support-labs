# RB-1003 — Account keeps locking

> Reproduced in the Riverbend lab: six logons with an old password were sent from WS01. Output: [`evidence/RB-1003-lockout-investigation.txt`](../evidence/RB-1003-lockout-investigation.txt)

| Field | Value |
|---|---|
| **Ticket ID** | RB-1003 |
| **Type** | Incident — access |
| **Priority** | P2 |
| **Reported via** | Chat |

## User report

> "My account got locked again. I'm typing the right password, I swear. This is the third time this week."

## Agent notes

**08:41** — "I'm typing the right password" plus repeat lockouts usually means **something else** is trying an old password on the user's behalf: a phone mail app, a mapped drive, a saved credential on another PC. Resetting the password would not fix that. It would just give the stale device a new wrong password to fail with.

**08:41** — Confirmed the state:

```
LockedOut              : True
BadLogonCount          : 5
```

**08:42** — First pass with `Get-LockoutSource` showed only the lockout event (4740), not the failed attempts before it. **Root cause of the gap:** the DC was not auditing Kerberos/NTLM failures (Windows default). Fixed with [`08-Enable-DCAuditing.ps1`](../setup/08-Enable-DCAuditing.ps1), then reproduced again.

**08:43** — Full trail:

```
Time        Event  Meaning                   Source
08:40:44    4771   Kerberos pre-auth failed  10.0.50.100
... (x5)
08:40:56    4740   Account locked out        WS01
```

The source is WS01 (the 4740 event names the caller computer). In a real case that is the device to go and look at for the saved credential.

**08:44** — **Unlocked, not reset.** The user knows the current password; the problem was the other device.

```powershell
Unlock-ADAccount diego.ramirez
```

Verified with a fresh logon from WS01 using the current password: `riverbend\diego.ramirez`.

## Resolution

Account unlocked; lockout source identified; DC auditing gap closed so the next lockout is traceable in one query.

## Open follow-up

Reverse DNS for DHCP clients is not registering (`10.0.50.100` has no PTR record), even with secure dynamic updates enabled on the reverse zone and DHCP set to update DNS. Logged as an open item instead of being papered over. The investigation did not depend on it, because 4740 already carries the computer name.

**Tags:** `account-lockout` `event-logs` `4740` `4771` `auditing` `root-cause`
