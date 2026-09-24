<#
.SYNOPSIS
    Runs on the workstation: checks the domain is resolvable, then joins it.
.NOTES
    The DNS pre-check exists because of ticket RB-1008: a PC pointed at a
    public DNS server cannot find the domain, and the join error does not say so.
#>
[CmdletBinding()]
param(
    [string]$DomainName = 'corp.riverbend.internal',
    [string]$JoinUser   = 'RIVERBEND\labadmin',
    [Parameter(Mandatory)][string]$PasswordFile
)
$ErrorActionPreference = 'Stop'

$srv = Resolve-DnsName "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV -ErrorAction SilentlyContinue
if (-not $srv) {
    $dns = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses).ServerAddresses -join ', '
    throw "Cannot find a domain controller for $DomainName via DNS (this PC uses: $dns). Point DNS at the DC (renew DHCP) and retry."
}

$pw   = ConvertTo-SecureString (Get-Content $PasswordFile -Raw).Trim() -AsPlainText -Force
$cred = New-Object Management.Automation.PSCredential($JoinUser, $pw)
Add-Computer -DomainName $DomainName -Credential $cred -Restart -Force
