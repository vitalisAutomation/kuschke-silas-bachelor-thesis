[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 254)]
    [int]$LastOctet,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])$')]
    [string]$PiIpAddress
)

$ErrorActionPreference = 'Stop'

if ($LastOctet -eq 1) {
    throw 'The development computer IP cannot be 192.168.1.1 because this address is reserved.'
}

$piLastOctet = [int]$PiIpAddress.Split('.')[-1]
if ($LastOctet -eq $piLastOctet) {
    throw "The development computer IP cannot use the Raspberry Pi address $PiIpAddress."
}

$adapter = Get-NetAdapter -Physical | Where-Object {
    $_.PhysicalMediaType -eq '802.3' -and
    $_.InterfaceDescription -notmatch 'Virtual|VPN|Cisco|AnyConnect|Wireless|Wi-Fi|Bluetooth'
} | Sort-Object @{ Expression = { if ($_.Status -eq 'Up') { 0 } else { 1 } } } | Select-Object -First 1

if (-not $adapter) {
    throw 'No physical Ethernet adapter could be identified.'
}

$ipAddress = "192.168.1.$LastOctet"
Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Disabled
Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -InterfaceMetric 1
Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $ipAddress -PrefixLength 24
Get-NetRoute -DestinationPrefix "$piIpAddress/32" -ErrorAction SilentlyContinue |
    Remove-NetRoute -Confirm:$false
New-NetRoute -DestinationPrefix "$piIpAddress/32" -InterfaceIndex $adapter.ifIndex -NextHop '0.0.0.0' -RouteMetric 1 | Out-Null

Write-Output "Configured $($adapter.Name) with $ipAddress/24."
