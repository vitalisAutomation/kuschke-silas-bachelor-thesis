$ErrorActionPreference = 'Stop'

$bootPath = $env:BOOT_PATH
$username = $env:PI_USERNAME
$password = $env:PI_PASSWORD
$hostname = $env:PI_HOSTNAME
$ipAddress = $env:PI_IP_ADDRESS
$ssid = $env:WIFI_SSID
$wifiPassword = $env:WIFI_PASSWORD
$publicKeyPath = $env:SSH_KEY_FILE + '.pub'

if ([string]::IsNullOrWhiteSpace($bootPath) -or -not (Test-Path -LiteralPath $bootPath)) {
    throw 'The boot partition path is missing or does not exist.'
}

if (-not (Test-Path -LiteralPath $publicKeyPath)) {
    throw 'The SSH public key does not exist.'
}

function ConvertTo-YamlSingleQuoted {
    param([string]$Value)

    return "'" + $Value.Replace("'", "''") + "'"
}

$publicKey = (Get-Content -LiteralPath $publicKeyPath -Raw).Trim()
$ssidYaml = ConvertTo-YamlSingleQuoted $ssid
$wifiPasswordYaml = ConvertTo-YamlSingleQuoted $wifiPassword

$userData = @(
    '#cloud-config'
    ''
    "hostname: $hostname"
    'users:'
    "  - name: $username"
    '    gecos: ctrlX SDK user'
    '    groups: sudo,adm'
    '    shell: /bin/bash'
    '    sudo: ALL=(ALL) NOPASSWD:ALL'
    '    lock_passwd: false'
    '    ssh_authorized_keys:'
    "      - $publicKey"
    'chpasswd:'
    '  list: |'
    "    ${username}:${password}"
    '  expire: false'
    'ssh_pwauth: true'
    'disable_root: true'
    'package_update: true'
    'packages:'
    '  - git'
    '  - unzip'
    '  - curl'
    '  - wget'
    '  - make'
    '  - squashfs-tools'
    '  - snapd'
    '  - openssh-server'
    '  - avahi-daemon'
)

if ($env:USE_PROXY -eq 'true') {
    $proxy = $env:PROXY_URL
    $userData += @(
        'apt:'
        "  proxy: $proxy"
    )
}

$userData += @(
    'write_files:'
    '  - path: /etc/systemd/system/ctrlx-apt-update-upgrade.service'
    "    permissions: '0644'"
    '    content: |'
    '      [Unit]'
    '      Description=Update and upgrade Ubuntu packages at boot'
    '      Wants=network-online.target'
    '      After=network-online.target apt-daily.service apt-daily-upgrade.service'
    ''
    '      [Service]'
    '      Type=oneshot'
    '      ExecStart=/usr/bin/apt-get update'
    '      ExecStart=/usr/bin/apt-get -y upgrade'
    '      Environment=DEBIAN_FRONTEND=noninteractive'
    ''
    '      [Install]'
    '      WantedBy=multi-user.target'
)

if ($env:USE_PROXY -eq 'true') {
    $userData += @(
        '  - path: /etc/profile.d/ctrlx-proxy.sh'
        "    permissions: '0644'"
        '    content: |'
        "      export http_proxy=$proxy"
        "      export https_proxy=$proxy"
        "      export HTTP_PROXY=$proxy"
        "      export HTTPS_PROXY=$proxy"
    )
}

$userData += @(
    'runcmd:'
    '  - systemctl enable --now ssh'
    '  - systemctl enable --now avahi-daemon'
    '  - systemctl daemon-reload'
    '  - systemctl enable --now ctrlx-apt-update-upgrade.service'
    "  - mkdir -p /home/$username"
    "  - chown ${username}:${username} /home/$username"
    "  - su - $username -c `"wget https://raw.githubusercontent.com/boschrexroth/ctrlx-automation-sdk/main/scripts/clone-install-sdk.sh`""
    "  - su - $username -c `"chmod a+x clone-install-sdk.sh`""
    "  - su - $username -c `"./clone-install-sdk.sh`""
    "  - su - $username -c `"/home/$username/ctrlx-automation-sdk/scripts/install-required-packages.sh`""
    "  - su - $username -c `"/home/$username/ctrlx-automation-sdk/scripts/install-snapcraft.sh`""
    '  - rm -f /boot/firmware/user-data /boot/firmware/network-config /boot/firmware/meta-data'
)

$networkConfig = @(
    'version: 2'
    'ethernets:'
    '  eth0:'
    '    dhcp4: false'
    '    addresses:'
    "      - $ipAddress/24"
    'wifis:'
    '  wlan0:'
    '    dhcp4: true'
    '    optional: true'
    '    access-points:'
    "      ${ssidYaml}:"
    "        password: ${wifiPasswordYaml}"
)

$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines((Join-Path $bootPath 'meta-data'), @(
    'instance-id: ctrlx-raspberry-pi'
    "local-hostname: $hostname"
), $encoding)
[System.IO.File]::WriteAllLines((Join-Path $bootPath 'user-data'), $userData, $encoding)
[System.IO.File]::WriteAllLines((Join-Path $bootPath 'network-config'), $networkConfig, $encoding)

$writtenFiles = @('meta-data', 'user-data', 'network-config') | ForEach-Object {
    Join-Path $bootPath $_
}

if ($writtenFiles | Where-Object { -not (Test-Path -LiteralPath $_) }) {
    throw 'One or more Cloud-Init files could not be written.'
}

$writtenNetworkConfig = Get-Content -LiteralPath (Join-Path $bootPath 'network-config')
if (-not ($writtenNetworkConfig -match '^      .+:$') -or
    -not ($writtenNetworkConfig -match '^        password: .+$')) {
    throw 'The generated network-config is not valid.'
}
