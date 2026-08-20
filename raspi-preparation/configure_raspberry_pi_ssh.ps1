$ErrorActionPreference = 'Stop'

$configPath = Join-Path $env:USERPROFILE '.ssh\config'
$configDirectory = Split-Path -Parent $configPath
New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null

$existingConfig = if (Test-Path -LiteralPath $configPath) {
    Get-Content -LiteralPath $configPath -Raw
} else {
    ''
}

$existingConfig = [regex]::Replace(
    $existingConfig,
    '(?ms)^Host ctrlx-pi\r?\n(?:(?!^Host\s).)*(?=^Host\s|\z)',
    ''
).Trim()

$hostBlock = @(
    'Host ctrlx-pi'
    "    HostName $env:SSH_HOST"
    "    User $env:SSH_USER"
    "    IdentityFile $env:SSH_KEY_FILE"
    '    IdentitiesOnly yes'
) -join [Environment]::NewLine

$content = if ($existingConfig) {
    $existingConfig + [Environment]::NewLine + [Environment]::NewLine + $hostBlock + [Environment]::NewLine
} else {
    $hostBlock + [Environment]::NewLine
}

[System.IO.File]::WriteAllText($configPath, $content)
