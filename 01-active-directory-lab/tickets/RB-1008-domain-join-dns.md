# RB-1008 — New PC can't join the domain

> This happened for real while building the lab: the first join attempt failed. Before/after output: [`RB-1008-before.txt`](../evidence/RB-1008-before.txt), [`RB-1008-after.txt`](../evidence/RB-1008-after.txt)

| Field | Value |
|---|---|
| **Ticket ID** | RB-1008 |
| **Type** | Incident — device setup |
| **Priority** | P3 |
| **Reported via** | Deskside tech setting up WS01 |

## Report

> "Joining WS01 to the domain fails with 'the specified domain either does not exist or could not be contacted'. The domain is definitely up, other things work, and I can reach the internet."

## Agent notes

The error text says "does not exist or could not be contacted" and nothing about DNS, even though DNS is the cause most of the time. A domain join finds the DC through a DNS SRV record. Cheapest check first:

```
PS> ipconfig /all
   DHCP Server . . . . . . . : 10.0.50.2
   DNS Servers . . . . . . . : <ISP resolver>

PS> Resolve-DnsName _ldap._tcp.dc._msdcs.corp.riverbend.internal -Type SRV
ERROR: DNS name does not exist
```

**Root cause:** WS01 got its lease from the **wrong DHCP server**, the hypervisor's built-in one (`10.0.50.2`), which handed out the ISP's public resolver. A public resolver has never heard of `corp.riverbend.internal`, so the PC could reach the internet but not the domain.

**Fix**, at the source rather than on the one PC:
1. Disabled the second DHCP server, so the only DHCP on the segment is DC01, which hands out `DNS = 10.0.50.10`.
2. `ipconfig /release` / `/renew` on WS01.

```
   DHCP Server . . . . . . . : 10.0.50.10
   DNS Servers . . . . . . . : 10.0.50.10
   Connection-specific DNS Suffix : corp.riverbend.internal

PS> Resolve-DnsName _ldap._tcp.dc._msdcs.corp.riverbend.internal -Type SRV
NameTarget                    Port
dc01.corp.riverbend.internal   389
```

Join succeeded. The computer object landed in `OU=Workstations` (not the default `CN=Computers`, which can't have GPOs linked), and the secure channel check came back `NERR_Success`. → [`10-Join-Domain.txt`](../evidence/10-Join-Domain.txt)

## Prevention

The join script ([`10-Join-Domain.ps1`](../setup/10-Join-Domain.ps1)) now **checks the DC SRV record before attempting the join** and fails with a message that says what's wrong: *"Cannot find a domain controller via DNS (this PC uses: X). Point DNS at the DC (renew DHCP) and retry."*

Setting a static DNS on just this PC would have "fixed" it and left the next ten PCs broken. The fix belongs at the DHCP server.

**Tags:** `dns` `dhcp` `domain-join` `rogue-dhcp` `root-cause`
