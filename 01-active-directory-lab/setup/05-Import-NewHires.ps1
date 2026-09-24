<#
.SYNOPSIS
    Bulk onboarding from the HR new-hire CSV.
.NOTES
    Temporary passwords go to a handoff file on the server only (never to the
    ticket, never to email). The manager gets them through a separate channel
    and every user must change theirs at first logon.
#>
[CmdletBinding()]
param(
    [string]$CsvPath,
    [string]$HandoffPath = 'C:\HelpDesk\Handoff\new-hire-credentials.csv',
    [string]$Ticket      = 'RB-1000'
)
$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 leaves $PSScriptRoot empty inside param() defaults.
if (-not $CsvPath) { $CsvPath = Join-Path $PSScriptRoot '..\data\new-hires.csv' }
Import-Module "$PSScriptRoot\..\tools\Riverbend.HelpDesk.psm1" -Force

$rows = Import-Csv $CsvPath -Encoding UTF8
$required = 'GivenName', 'Surname', 'Department', 'Title'
$missing = $required | Where-Object { $_ -notin $rows[0].PSObject.Properties.Name }
if ($missing) { throw "CSV is missing columns: $($missing -join ', ')" }

$created = @(); $failed = @()
foreach ($r in $rows) {
    try {
        $created += New-RiverbendUser -GivenName $r.GivenName -Surname $r.Surname -Department $r.Department `
                                      -Title $r.Title -Office $r.Office -Ticket $Ticket
    } catch {
        $failed += [pscustomobject]@{ Name = "$($r.GivenName) $($r.Surname)"; Error = $_.Exception.Message }
    }
}

$handoffDir = Split-Path $HandoffPath
New-Item -ItemType Directory -Path $handoffDir -Force | Out-Null
# Temp passwords: Administrators and SYSTEM only, nothing inherited from C:\.
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
foreach ($id in 'BUILTIN\Administrators', 'NT AUTHORITY\SYSTEM') {
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($id, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
}
Set-Acl -Path $handoffDir -AclObject $acl
$created | Export-Csv $HandoffPath -NoTypeInformation -Encoding UTF8

Write-Host "Created $($created.Count) of $($rows.Count) accounts. Handoff file: $HandoffPath"
$created | Select-Object SamAccountName, DisplayName, Department | Format-Table -AutoSize
if ($failed) { Write-Warning "$($failed.Count) failed:"; $failed | Format-Table -AutoSize }
