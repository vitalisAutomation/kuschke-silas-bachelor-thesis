$ErrorActionPreference = 'Stop'

$settingsDirectory = Join-Path $env:APPDATA 'Code\User'
$settingsPath = Join-Path $settingsDirectory 'settings.json'
New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null

$setting = '"remote.SSH.localServerDownload"'
$settingValue = '"never"'

if (Test-Path -LiteralPath $settingsPath) {
    $content = Get-Content -LiteralPath $settingsPath -Raw
    $pattern = '(?m)(^[ \t]*"remote\.SSH\.localServerDownload"[ \t]*:[ \t]*)"(?:always|never)"[ \t]*,?'
    if ([regex]::IsMatch($content, $pattern)) {
        $content = [regex]::Replace($content, $pattern, ('$1' + $settingValue + ','))
    } else {
        $closingBrace = $content.LastIndexOf('}')
        if ($closingBrace -lt 0) {
            throw "The VS Code settings file is not valid JSON: $settingsPath"
        }
        $beforeBrace = $content.Substring(0, $closingBrace).TrimEnd()
        $separator = if ($beforeBrace.EndsWith('{')) { '' } else { ',' }
        $content = $beforeBrace + $separator + [Environment]::NewLine + "    $setting`: $settingValue" + [Environment]::NewLine + '}' + $content.Substring($closingBrace + 1)
    }
} else {
    $content = "{`n    $setting`: $settingValue`n}`n"
}

[System.IO.File]::WriteAllText($settingsPath, $content, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "Configured VS Code Remote-SSH remote server download: $settingsPath"
