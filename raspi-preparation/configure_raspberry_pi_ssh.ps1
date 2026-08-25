$ErrorActionPreference = 'Stop'

# Validate the connection settings supplied by the batch workflow.
foreach ($variable in @('SSH_HOST', 'SSH_USER', 'SSH_KEY_FILE')) {
    if ([string]::IsNullOrWhiteSpace((Get-Item -Path "Env:$variable" -ErrorAction SilentlyContinue).Value)) {
        throw "The environment variable $variable is missing."
    }
}

if (-not (Test-Path -LiteralPath $env:SSH_KEY_FILE -PathType Leaf)) {
    throw "The SSH private key does not exist: $env:SSH_KEY_FILE"
}

# Replace only the managed ctrlx-pi host block and preserve other SSH entries.
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
