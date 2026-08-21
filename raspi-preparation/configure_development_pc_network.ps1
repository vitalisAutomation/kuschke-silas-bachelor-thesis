[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 254)]
    [int]$LastOctet
)

$ErrorActionPreference = 'Stop'

if ($LastOctet -in @(1, 100)) {
    throw 'The development computer IP cannot be 192.168.1.1 or 192.168.1.100 because these addresses are reserved.'
}

$adapter = Get-NetAdapter -Physical | Where-Object {
    $_.InterfaceDescription -match 'Ethernet|Gigabit|I219|Realtek|PCIe' -and
    $_.InterfaceDescription -notmatch 'Virtual|VPN|Cisco|AnyConnect|Wireless|Wi-Fi'
} | Select-Object -First 1

if (-not $adapter) {
    throw 'No physical Ethernet adapter could be identified.'
}

$ipAddress = "192.168.1.$LastOctet"
Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Disabled
Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $ipAddress -PrefixLength 24

Write-Output "Configured $($adapter.Name) with $ipAddress/24."
