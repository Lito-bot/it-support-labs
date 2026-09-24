<#
.SYNOPSIS
    Domain password/lockout policy plus two GPOs:
      WS - Security Baseline  (linked to Workstations)
      USR - Drive Maps        (linked to Riverbend\Users, one drive per department)
.NOTES
    Drive maps use Group Policy Preferences with item-level targeting by group,
    so one GPO covers every department instead of one GPO per team.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory, GroupPolicy

$domain   = Get-ADDomain
$domainDN = $domain.DistinguishedName
$wsOU     = "OU=Workstations,OU=Riverbend,$domainDN"
$usersOU  = "OU=Users,OU=Riverbend,$domainDN"

# --- Password and lockout policy ---------------------------------------------
# 5 bad attempts locks the account for 15 minutes: enough to stop guessing,
# short enough that a locked-out user is not stuck all day.
Set-ADDefaultDomainPasswordPolicy -Identity $domain.DNSRoot -MinPasswordLength 12 `
    -ComplexityEnabled $true -PasswordHistoryCount 12 -MaxPasswordAge (New-TimeSpan -Days 365) `
    -LockoutThreshold 5 -LockoutDuration (New-TimeSpan -Minutes 15) `
    -LockoutObservationWindow (New-TimeSpan -Minutes 15)

function Get-OrCreateGPO([string]$Name, [string]$Comment, [string]$LinkTo) {
    $gpo = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if (-not $gpo) { $gpo = New-GPO -Name $Name -Comment $Comment }
    $linked = @((Get-GPInheritance -Target $LinkTo).GpoLinks | ForEach-Object DisplayName)
    if ($linked -notcontains $Name) {
        New-GPLink -Guid $gpo.Id -Target $LinkTo | Out-Null
    }
    return $gpo
}

# --- WS - Security Baseline -----------------------------------------------------
$ws = Get-OrCreateGPO 'WS - Security Baseline' 'Screen lock, logon banner, USB write block, firewall on' $wsOU
$sys = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System'
$settings = @(
    @($sys, 'InactivityTimeoutSecs', 'DWord', 600),
    # Don't show who signed in last: an attacker at the lock screen shouldn't get half the credentials for free.
    @($sys, 'DontDisplayLastUserName', 'DWord', 1),
    @($sys, 'legalnoticecaption', 'String', 'Riverbend Logistics - authorized use only'),
    @($sys, 'legalnoticetext', 'String', 'This computer is company property. Activity may be monitored. Report lost devices or suspicious email to the Service Desk.'),
    @('HKLM\Software\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}', 'Deny_Write', 'DWord', 1),
    @('HKLM\Software\Policies\Microsoft\WindowsFirewall\DomainProfile',  'EnableFirewall', 'DWord', 1),
    @('HKLM\Software\Policies\Microsoft\WindowsFirewall\PrivateProfile', 'EnableFirewall', 'DWord', 1),
    @('HKLM\Software\Policies\Microsoft\WindowsFirewall\PublicProfile',  'EnableFirewall', 'DWord', 1),
    # Wait for the network at logon so drive maps apply on the first logon, not the second.
    @('HKLM\Software\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon', 'SyncForegroundPolicy', 'DWord', 1)
)
foreach ($s in $settings) {
    Set-GPRegistryValue -Guid $ws.Id -Key $s[0] -ValueName $s[1] -Type $s[2] -Value $s[3] | Out-Null
}
Write-Host "Configured '$($ws.DisplayName)' -> $wsOU"

# --- USR - Drive Maps -----------------------------------------------------------
. "$PSScriptRoot\lib\Set-GppDriveMaps.ps1"
$maps = @(
    @{ Letter = 'F'; Share = 'Finance';    Group = 'GG-Finance' },
    @{ Letter = 'S'; Share = 'Sales';      Group = 'GG-Sales' },
    @{ Letter = 'H'; Share = 'HR';         Group = 'GG-HR' },
    @{ Letter = 'O'; Share = 'Operations'; Group = 'GG-Operations' },
    @{ Letter = 'I'; Share = 'IT';         Group = 'GG-IT' },
    @{ Letter = 'P'; Share = 'Public';     Group = 'GG-All-Staff' }
)
$dm = Get-OrCreateGPO 'USR - Drive Maps' 'Department drives via GPP item-level targeting' $usersOU
Set-GppDriveMaps -Gpo $dm -Maps $maps -FileServer 'DC01' -NetBIOSName $domain.NetBIOSName
Write-Host "Configured '$($dm.DisplayName)' -> $usersOU"

Get-GPO -All | Where-Object DisplayName -match '^(WS|USR) - ' |
    Select-Object DisplayName, GpoStatus, @{ n = 'UserVer'; e = { $_.User.DSVersion } }, @{ n = 'ComputerVer'; e = { $_.Computer.DSVersion } }
