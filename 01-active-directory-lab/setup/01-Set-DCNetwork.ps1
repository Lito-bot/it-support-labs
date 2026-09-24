<#
.SYNOPSIS
    Gives DC01 a static IP before it becomes a domain controller.
.NOTES
    A DC must never depend on DHCP for its own address: every client in the
    domain will point at this IP for DNS.
#>
[CmdletBinding()]
param(
    [string]$IPAddress   = '10.0.50.10',
    [int]   $PrefixLength = 24,
    [string]$Gateway     = '10.0.50.1'
)
$ErrorActionPreference = 'Stop'

$nic = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
if (-not $nic) { throw 'No active network adapter found.' }

Set-NetIPInterface -InterfaceIndex $nic.ifIndex -Dhcp Disabled
Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false
Get-NetRoute -InterfaceIndex $nic.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Remove-NetRoute -Confirm:$false

New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $IPAddress -PrefixLength $PrefixLength -DefaultGateway $Gateway | Out-Null
# Loopback first: once AD DS is installed, this server answers its own DNS queries.
Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses @('127.0.0.1', '1.1.1.1')

Get-NetIPConfiguration -InterfaceIndex $nic.ifIndex |
    Select-Object InterfaceAlias, IPv4Address, IPv4DefaultGateway, DNSServer
