<#
.SYNOPSIS
    Turns on the DC audit subcategories a service desk (and later a SIEM) needs
    to answer "who locked this account out, and from where?".
.NOTES
    Out of the box the DC logs the lockout (4740) but not the failed attempts
    leading up to it (4771 Kerberos, 4776 NTLM), so the trail has a gap.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$subcategories = @(
    'Kerberos Authentication Service',   # 4768 / 4771
    'Credential Validation',             # 4776
    'User Account Management',           # 4720 created, 4725 disabled, 4740 locked
    'Security Group Management',         # 4728 / 4732 / 4756 member added
    'Logon'                              # 4624 / 4625
)
foreach ($sub in $subcategories) {
    auditpol /set /subcategory:"$sub" /success:enable /failure:enable | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "auditpol failed for '$sub'" }
}
# A bigger Security log so a week of events survives on a busy DC.
limit-eventlog -LogName Security -MaximumSize 256MB

auditpol /get /category:"Account Logon","Account Management","Logon/Logoff" |
    Select-String ($subcategories -join '|')
