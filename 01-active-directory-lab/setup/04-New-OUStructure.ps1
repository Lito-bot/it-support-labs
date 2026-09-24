<#
.SYNOPSIS
    Creates the Riverbend OU tree, department groups (AGDLP) and redirects new
    computer accounts to the Workstations OU.
.NOTES
    Idempotent: safe to re-run, existing objects are skipped.
#>
[CmdletBinding()]
param(
    [string[]]$Departments = @('Finance', 'Sales', 'HR', 'Operations', 'IT')
)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$domainDN = (Get-ADDomain).DistinguishedName
$rootDN   = "OU=Riverbend,$domainDN"

function New-OUIfMissing([string]$Name, [string]$Path) {
    $dn = "OU=$Name,$Path"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
        Write-Host "Created OU $dn"
    }
    return $dn
}

function New-GroupIfMissing([string]$Name, [string]$Scope, [string]$Path, [string]$Description) {
    if (-not (Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $Name -GroupScope $Scope -GroupCategory Security -Path $Path -Description $Description
        Write-Host "Created group $Name"
    }
}

New-OUIfMissing 'Riverbend' $domainDN | Out-Null
$usersDN     = New-OUIfMissing 'Users'            $rootDN
$groupsDN    = New-OUIfMissing 'Groups'           $rootDN
$wsDN        = New-OUIfMissing 'Workstations'     $rootDN
New-OUIfMissing 'Service Accounts' $rootDN | Out-Null
New-OUIfMissing 'Disabled Users'   $rootDN | Out-Null
$roleDN      = New-OUIfMissing 'Role'     $groupsDN
$resourceDN  = New-OUIfMissing 'Resource' $groupsDN

foreach ($dept in $Departments) {
    New-OUIfMissing $dept $usersDN | Out-Null
    # AGDLP: users go in the global role group, the role group goes in the
    # domain-local resource groups, and only resource groups appear on ACLs.
    New-GroupIfMissing "GG-$dept"              Global      $roleDN     "All $dept staff"
    New-GroupIfMissing "DL-Share-$dept-RW"     DomainLocal $resourceDN "Modify on \\DC01\$dept"
    New-GroupIfMissing "DL-Share-$dept-RO"     DomainLocal $resourceDN "Read on \\DC01\$dept"
    Add-ADGroupMember "DL-Share-$dept-RW" -Members "GG-$dept"
}
New-GroupIfMissing 'GG-All-Staff'        Global      $roleDN     'Every active employee'
New-GroupIfMissing 'DL-Share-Public-RW'  DomainLocal $resourceDN 'Modify on \\DC01\Public'
Add-ADGroupMember 'DL-Share-Public-RW' -Members 'GG-All-Staff'
# Sales needs to read Finance price lists, not change them.
Add-ADGroupMember 'DL-Share-Finance-RO' -Members 'GG-Sales'

# New domain-joined PCs land in Workstations (where the GPOs are linked)
# instead of the default CN=Computers container, which cannot have GPOs linked.
redircmp $wsDN | Out-Null
Write-Host "Default computer container redirected to $wsDN"
