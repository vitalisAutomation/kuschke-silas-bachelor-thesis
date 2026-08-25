[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z]$')]
    [string]$DriveLetter
)

$ErrorActionPreference = 'Stop'

# Resolve the selected volume and refuse to eject a Windows system disk.
$drive = $DriveLetter.ToUpperInvariant()
$partition = Get-Partition -DriveLetter $drive
$disk = Get-Disk -Number $partition.DiskNumber

if ($disk.IsBoot -or $disk.IsSystem) {
    throw "Refusing to eject boot or system disk $($disk.Number)."
}

$diskDrive = Get-CimInstance Win32_DiskDrive -Filter "Index=$($disk.Number)"
if (-not $diskDrive.PNPDeviceID) {
    throw "Could not resolve the USB device for disk $($disk.Number)."
}

$parentProperty = Get-PnpDeviceProperty -InstanceId $diskDrive.PNPDeviceID -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue
$deviceId = $parentProperty.Data
if (-not $deviceId) {
    $deviceId = $diskDrive.PNPDeviceID
}

# Add the minimal Configuration Manager interop required for safe device eject.
if (-not ('WindowsDeviceEjector' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class WindowsDeviceEjector
{
    [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
    private static extern int CM_Locate_DevNode(out uint devInst, string deviceId, uint flags);

    [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
    private static extern int CM_Request_Device_Eject(
        uint devInst,
        out uint vetoType,
        IntPtr vetoName,
        uint vetoNameLength,
        uint flags);

    public static int Eject(string deviceId)
    {
        uint devInst;
        var locateResult = CM_Locate_DevNode(out devInst, deviceId, 0);
        if (locateResult != 0)
            return locateResult;

        uint vetoType;
        return CM_Request_Device_Eject(devInst, out vetoType, IntPtr.Zero, 0, 0);
    }
}
"@
}

# Re-enable automatic volume mounting before requesting device removal.
& "$env:SystemRoot\System32\mountvol.exe" /e
if ($LASTEXITCODE -ne 0) {
    throw 'Could not enable automatic volume mounting.'
}

$ejectResult = [WindowsDeviceEjector]::Eject($deviceId)
if ($ejectResult -ne 0) {
    throw "Windows refused to eject the SD device node $deviceId (CM_Request_Device_Eject result $ejectResult)."
}

Start-Sleep -Milliseconds 500
if (Get-Disk -Number $disk.Number -ErrorAction SilentlyContinue) {
    throw "The SD device is still present after the eject request."
}
