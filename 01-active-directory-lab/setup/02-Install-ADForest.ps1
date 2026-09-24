<#
.SYNOPSIS
    Installs AD DS + DNS and promotes DC01 to the first DC of a new forest.
.NOTES
    The server reboots on its own when promotion finishes.
    The DSRM password is read from a file so it never appears in command history.
#>
[CmdletBinding()]
param(
    [string]$DomainName   = 'corp.riverbend.internal',
    [string]$NetBIOSName  = 'RIVERBEND',
    [Parameter(Mandatory)][string]$DsrmPasswordFile
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $DsrmPasswordFile)) { throw "DSRM password file not found: $DsrmPasswordFile" }
$dsrm = ConvertTo-SecureString (Get-Content $DsrmPasswordFile -Raw).Trim() -AsPlainText -Force

Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null

Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetBIOSName `
    -ForestMode WinThreshold `
    -DomainMode WinThreshold `
    -InstallDns `
    -SafeModeAdministratorPassword $dsrm `
    -NoRebootOnCompletion:$false `
    -Force
