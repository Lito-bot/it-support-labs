<#
.SYNOPSIS
    Configures DNS forwarders and a DHCP scope on DC01, so clients get the DC
    as their DNS server automatically.
.NOTES
    Clients that resolve against a public DNS server cannot find the domain.
    Handing out the DC's address via DHCP removes that whole class of ticket.
#>
[CmdletBinding()]
param(
    [string]$DcIP        = '10.0.50.10',
    [string]$Gateway     = '10.0.50.1',
    [string]$ScopeId     = '10.0.50.0',
    [string]$RangeStart  = '10.0.50.100',
    [string]$RangeEnd    = '10.0.50.200',
    [string]$DomainName  = 'corp.riverbend.internal'
)
$ErrorActionPreference = 'Stop'

# Anything outside the domain gets forwarded to public resolvers.
Set-DnsServerForwarder -IPAddress @('1.1.1.1', '8.8.8.8')

# Reverse lookup zone so nslookup and troubleshooting tools show host names.
if (-not (Get-DnsServerZone -Name '50.0.10.in-addr.arpa' -ErrorAction SilentlyContinue)) {
    Add-DnsServerPrimaryZone -NetworkId '10.0.50.0/24' -ReplicationScope Domain
}
# The cmdlet's default is DynamicUpdate None, which silently stops every PTR registration.
Set-DnsServerPrimaryZone -Name '50.0.10.in-addr.arpa' -DynamicUpdate Secure

Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
# DHCP on a DC has to be authorized in AD before it hands out leases.
Add-DhcpServerInDC -DnsName "$env:COMPUTERNAME.$DomainName" -IPAddress $DcIP
Add-DhcpServerSecurityGroup
Restart-Service DHCPServer
# Clears the Server Manager "complete DHCP configuration" warning.
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' -Name ConfigurationState -Value 2

if (-not (Get-DhcpServerv4Scope -ScopeId $ScopeId -ErrorAction SilentlyContinue)) {
    Add-DhcpServerv4Scope -Name 'Riverbend LAN' -StartRange $RangeStart -EndRange $RangeEnd `
        -SubnetMask 255.255.255.0 -LeaseDuration (New-TimeSpan -Days 8) -State Active
}
Set-DhcpServerv4OptionValue -ScopeId $ScopeId -Router $Gateway -DnsServer $DcIP -DnsDomain $DomainName
# Register A + PTR records for every lease, so "which PC is 10.0.50.x?" has an answer
# during a lockout or security investigation.
Set-DhcpServerv4DnsSetting -ScopeId $ScopeId -DynamicUpdates Always -DeleteDnsRROnLeaseExpiry $true -UpdateDnsRRForOlderClients $true

Get-DhcpServerv4Scope | Select-Object ScopeId, StartRange, EndRange, State
Get-DhcpServerv4OptionValue -ScopeId $ScopeId | Select-Object OptionId, Name, Value
