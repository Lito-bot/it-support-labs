<#
.SYNOPSIS
    Creates one share per department plus a Public share, with NTFS permissions
    granted only to the DL-Share-* resource groups (AGDLP).
.NOTES
    Share permission is broad (Authenticated Users: Change); NTFS is where
    access is actually decided. Access-based enumeration hides folders a user
    cannot open, which cuts "why can I see it but not open it" tickets.
    In production these would live on a file server, not on the DC.
#>
[CmdletBinding()]
param(
    [string]  $Root        = 'C:\Shares',
    [string[]]$Departments = @('Finance', 'Sales', 'HR', 'Operations', 'IT', 'Public')
)
$ErrorActionPreference = 'Stop'
$netbios = (Get-ADDomain).NetBIOSName

function Set-FolderAcl([string]$Path, [string]$Dept) {
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)   # stop inheriting from C:\Shares
    $inherit = 'ContainerInherit, ObjectInherit'
    $rules = @(
        @('BUILTIN\Administrators', 'FullControl'),
        @('NT AUTHORITY\SYSTEM',    'FullControl'),
        @("$netbios\DL-Share-$Dept-RW", 'Modify')
    )
    if ($Dept -ne 'Public') { $rules += ,@("$netbios\DL-Share-$Dept-RO", 'ReadAndExecute') }
    foreach ($r in $rules) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($r[0], $r[1], $inherit, 'None', 'Allow')))
    }
    Set-Acl -Path $Path -AclObject $acl
}

foreach ($dept in $Departments) {
    $path = Join-Path $Root $dept
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Set-FolderAcl $path $dept
    if (-not (Get-SmbShare -Name $dept -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $dept -Path $path -ChangeAccess 'Authenticated Users' `
                     -FullAccess 'BUILTIN\Administrators' -FolderEnumerationMode AccessBased | Out-Null
    }
    Write-Host "Share \\$env:COMPUTERNAME\$dept ready"
}

# A file per share so drive mappings are easy to verify from a client.
Set-Content "$Root\Finance\Q3-price-list.txt" 'Riverbend Q3 price list (lab sample data)'
Set-Content "$Root\Public\welcome.txt"        'Welcome to Riverbend Logistics'

Get-SmbShare | Where-Object Path -like "$Root*" | Select-Object Name, Path, FolderEnumerationMode
