<#
    Riverbend.HelpDesk - the day-to-day account work of a service desk:
    onboarding, password resets, lockout investigation, department moves,
    offboarding and a stale-account audit.

    Every change is written to an audit log with the ticket number that
    requested it, so "who changed this and why" always has an answer.
#>
Set-StrictMode -Version Latest
# Module functions don't inherit the caller's preference, so a failed AD cmdlet
# would otherwise be a non-terminating error and the function would carry on.
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$script:AuditLog  = 'C:\HelpDesk\Logs\audit.csv'
$script:UpnSuffix = 'corp.riverbend.internal'

function Write-AuditEntry {
    param([string]$Ticket, [string]$Action, [string]$Target, [string]$Detail)
    $dir = Split-Path $script:AuditLog
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [pscustomobject]@{
        Timestamp = (Get-Date).ToString('s')
        Ticket    = $Ticket
        Action    = $Action
        Target    = $Target
        Detail    = $Detail
        Operator  = "$env:USERDOMAIN\$env:USERNAME"
    } | Export-Csv -Path $script:AuditLog -Append -NoTypeInformation -Encoding UTF8
}

function ConvertTo-SamAccountName {
    <# "Kevin O'Brien" -> kevin.obrien ; strips accents, max 20 chars, appends 2,3.. on collision. #>
    param([Parameter(Mandatory)][string]$GivenName, [Parameter(Mandatory)][string]$Surname)
    $raw = "$GivenName.$Surname".Normalize([Text.NormalizationForm]::FormD)
    $ascii = -join ($raw.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
    $base = ($ascii.ToLower() -replace "[^a-z0-9.]", '')
    if ($base.Length -gt 18) { $base = $base.Substring(0, 18) }
    $candidate = $base; $n = 2
    while (Get-ADUser -Filter "SamAccountName -eq '$candidate'" -ErrorAction SilentlyContinue) {
        $candidate = "$base$n"; $n++
    }
    return $candidate
}

function New-TempPassword {
    <# 16 random chars from every class; the user must change it at first logon. #>
    $sets = 'ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnpqrstuvwxyz', '23456789', '!@#$%*-_'
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $pick = { param($s) $b = [byte[]]::new(1); $rng.GetBytes($b); $s[$b[0] % $s.Length] }
    $chars = foreach ($s in $sets) { & $pick $s }
    $all = -join $sets
    $chars += 1..12 | ForEach-Object { & $pick $all }
    return -join ($chars | Sort-Object { Get-Random })
}

function Get-DepartmentOU {
    # Letters only: the name is interpolated into an AD filter and an OU path.
    param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z]+$')][string]$Department)
    $dn = "OU=$Department,OU=Users,OU=Riverbend,$((Get-ADDomain).DistinguishedName)"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        throw "Unknown department '$Department' (no OU $dn)."
    }
    return $dn
}

function New-RiverbendUser {
    <#
    .SYNOPSIS Onboards one employee: account, department OU, role groups, temp password.
    .OUTPUTS  Object with the login name and temporary password for the manager handoff.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$GivenName,
        [Parameter(Mandatory)][string]$Surname,
        [Parameter(Mandatory)][string]$Department,
        [Parameter(Mandatory)][string]$Title,
        [string]$Office = 'Remote',
        [Parameter(Mandatory)][string]$Ticket
    )
    $ou  = Get-DepartmentOU $Department
    $sam = ConvertTo-SamAccountName $GivenName $Surname
    $pw  = New-TempPassword
    if (-not $PSCmdlet.ShouldProcess($sam, 'Create user')) { return }

    New-ADUser -Name "$GivenName $Surname ($sam)" -DisplayName "$GivenName $Surname" `
        -GivenName $GivenName -Surname $Surname -SamAccountName $sam `
        -UserPrincipalName "$sam@$script:UpnSuffix" -Title $Title -Department $Department `
        -Office $Office -Company 'Riverbend Logistics' -Path $ou `
        -AccountPassword (ConvertTo-SecureString $pw -AsPlainText -Force) `
        -ChangePasswordAtLogon $true -Enabled $true
    Add-ADGroupMember "GG-$Department" -Members $sam
    Add-ADGroupMember 'GG-All-Staff'   -Members $sam
    Write-AuditEntry $Ticket 'Onboard' $sam "OU=$Department; groups GG-$Department, GG-All-Staff"

    [pscustomobject]@{ SamAccountName = $sam; DisplayName = "$GivenName $Surname"
                       Department = $Department; TempPassword = $pw }
}

function Reset-RiverbendPassword {
    <#
    .SYNOPSIS Resets a password after identity verification, unlocks, forces change at logon.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][string]$Ticket,
        [Parameter(Mandatory)][ValidateSet('CallbackToManager', 'VideoCallWithId', 'InPerson')]
        [string]$IdentityVerifiedBy
    )
    $user = Get-ADUser $SamAccountName -Properties LockedOut, Enabled
    if (-not $user.Enabled) { throw "$SamAccountName is disabled - resets on disabled accounts need HR approval." }
    $pw = New-TempPassword
    if (-not $PSCmdlet.ShouldProcess($SamAccountName, 'Reset password')) { return }

    Set-ADAccountPassword $user -Reset -NewPassword (ConvertTo-SecureString $pw -AsPlainText -Force)
    Set-ADUser $user -ChangePasswordAtLogon $true
    if ($user.LockedOut) { Unlock-ADAccount $user }
    Write-AuditEntry $Ticket 'PasswordReset' $SamAccountName "Verified by $IdentityVerifiedBy; was locked: $($user.LockedOut)"
    [pscustomobject]@{ SamAccountName = $SamAccountName; TempPassword = $pw; WasLocked = $user.LockedOut }
}

function Get-LockoutSource {
    <#
    .SYNOPSIS Finds which computer keeps locking an account (event 4740 on the DC)
              and the failed attempts that led up to it (4771 Kerberos / 4776 NTLM).
    #>
    param([Parameter(Mandatory)][string]$SamAccountName, [int]$HoursBack = 24)
    $since = (Get-Date).AddHours(-$HoursBack)
    $filter = @{ LogName = 'Security'; Id = 4740, 4771, 4776; StartTime = $since }
    Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue | ForEach-Object {
        $xml  = [xml]$_.ToXml()
        # InnerText, not '#text': empty fields have no text node and StrictMode would throw.
        $data = @{}; foreach ($d in $xml.Event.EventData.Data) { $data[$d.Name] = $d.InnerText }
        $who  = if ($data.ContainsKey('TargetUserName')) { $data.TargetUserName } else { $null }
        if ($who -ne $SamAccountName) { return }
        $source = switch ($_.Id) {
            4740 { $data.TargetDomainName }                       # caller computer name
            4771 { ($data.IpAddress -replace '^::ffff:', '') }    # client IP
            4776 { $data.Workstation }
        }
        [pscustomobject]@{
            Time   = $_.TimeCreated
            Event  = $_.Id
            Meaning = @{ 4740 = 'Account locked out'; 4771 = 'Kerberos pre-auth failed'; 4776 = 'NTLM logon failed' }[$_.Id]
            Source = $source
        }
    } | Sort-Object Time
}

function Move-RiverbendUserDepartment {
    <#
    .SYNOPSIS Internal transfer ("mover"): swaps department groups, OU and HR attributes.
              Old access is removed, not accumulated.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][string]$NewDepartment,
        [Parameter(Mandatory)][string]$NewTitle,
        [Parameter(Mandatory)][string]$Ticket
    )
    $user = Get-ADUser $SamAccountName -Properties Department
    $old  = $user.Department
    if ($old -eq $NewDepartment) { throw "$SamAccountName is already in $NewDepartment." }
    $newOU = Get-DepartmentOU $NewDepartment
    if (-not $PSCmdlet.ShouldProcess($SamAccountName, "Move $old -> $NewDepartment")) { return }

    Remove-ADGroupMember "GG-$old" -Members $user -Confirm:$false
    Add-ADGroupMember    "GG-$NewDepartment" -Members $user
    Set-ADUser $user -Department $NewDepartment -Title $NewTitle
    Move-ADObject $user.DistinguishedName -TargetPath $newOU
    Write-AuditEntry $Ticket 'Transfer' $SamAccountName "$old -> $NewDepartment ($NewTitle)"
    Get-ADUser $SamAccountName -Properties Department, Title, MemberOf |
        Select-Object SamAccountName, Department, Title,
            @{ n = 'Groups'; e = { ($_.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace 'CN=' }) -join ', ' } }
}

function Invoke-RiverbendOffboarding {
    <#
    .SYNOPSIS Leaver process: disable, scramble password, strip groups (saved for audit),
              move to Disabled Users. The account is kept, not deleted, for 30 days.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][string]$Ticket,
        [string]$EvidenceDir = 'C:\HelpDesk\Offboarding'
    )
    $user = Get-ADUser $SamAccountName -Properties MemberOf
    $disabledOU = "OU=Disabled Users,OU=Riverbend,$((Get-ADDomain).DistinguishedName)"
    if (-not $PSCmdlet.ShouldProcess($SamAccountName, 'Offboard')) { return }

    if (-not (Test-Path $EvidenceDir)) { New-Item -ItemType Directory $EvidenceDir -Force | Out-Null }
    $user.MemberOf | ForEach-Object { [pscustomobject]@{ User = $SamAccountName; Group = $_ } } |
        Export-Csv "$EvidenceDir\$Ticket-$SamAccountName-groups.csv" -NoTypeInformation -Encoding UTF8

    Disable-ADAccount $user
    Set-ADAccountPassword $user -Reset -NewPassword (ConvertTo-SecureString (New-TempPassword) -AsPlainText -Force)
    foreach ($g in $user.MemberOf) { Remove-ADGroupMember $g -Members $user -Confirm:$false }
    $purgeDate = (Get-Date).AddDays(30).ToString('yyyy-MM-dd')
    Set-ADUser $user -Description "Offboarded $((Get-Date).ToString('yyyy-MM-dd')) ($Ticket). Delete after $purgeDate."
    Move-ADObject $user.DistinguishedName -TargetPath $disabledOU
    Write-AuditEntry $Ticket 'Offboard' $SamAccountName "Removed from $($user.MemberOf.Count) groups; purge after $purgeDate"
    Get-ADUser $SamAccountName -Properties Description, MemberOf |
        Select-Object SamAccountName, Enabled, Description, @{ n = 'GroupCount'; e = { $_.MemberOf.Count } }
}

function Get-StaleAccountReport {
    <#
    .SYNOPSIS Monthly hygiene audit: enabled accounts with no logon in N days (or never),
              accounts whose password never expires, and disabled accounts past their purge date.
    #>
    param([int]$InactiveDays = 90)
    $cutoff = (Get-Date).AddDays(-$InactiveDays)
    $props  = 'LastLogonDate', 'PasswordNeverExpires', 'Enabled', 'WhenCreated', 'Description', 'Department'
    Get-ADUser -Filter * -SearchBase "OU=Riverbend,$((Get-ADDomain).DistinguishedName)" -Properties $props |
        ForEach-Object {
            $findings = @()
            if ($_.Enabled -and -not $_.LastLogonDate -and $_.WhenCreated -lt (Get-Date).AddDays(-14)) { $findings += 'Never logged on (created 14+ days ago)' }
            elseif ($_.Enabled -and -not $_.LastLogonDate) { $findings += 'Never logged on (new account)' }
            if ($_.Enabled -and $_.LastLogonDate -and $_.LastLogonDate -lt $cutoff) { $findings += "No logon in $InactiveDays+ days" }
            if ($_.Enabled -and $_.PasswordNeverExpires) { $findings += 'Password never expires' }
            if (-not $_.Enabled -and $_.Description -match 'Delete after (\d{4}-\d{2}-\d{2})' -and [datetime]$Matches[1] -lt (Get-Date)) {
                $findings += 'Disabled and past purge date'
            }
            foreach ($f in $findings) {
                [pscustomobject]@{ SamAccountName = $_.SamAccountName; Department = $_.Department
                                   Enabled = $_.Enabled; LastLogon = $_.LastLogonDate; Finding = $f }
            }
        }
}

Export-ModuleMember -Function New-RiverbendUser, Reset-RiverbendPassword, Get-LockoutSource,
    Move-RiverbendUserDepartment, Invoke-RiverbendOffboarding, Get-StaleAccountReport, ConvertTo-SamAccountName
