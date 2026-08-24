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
    'output:'
    '  all: "| tee -a /var/log/cloud-init-output.log /var/log/ctrlx-provisioning.log"'
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

$userData += @(
    'bootcmd:'
    '  - [ bash, -c, "DEBUG_DIR=/boot/firmware/cloud-init-debug; mkdir -p $DEBUG_DIR; date -Is > $DEBUG_DIR/bootcmd-start.txt; mountpoint /boot/firmware > $DEBUG_DIR/boot-mount.txt 2>&1; { echo ==== bootcmd ====; date -Is; cat /proc/cmdline; ip -br addr; ip route; resolvectl status; } >> /var/log/ctrlx-provisioning.log 2>&1; cp -f /var/log/cloud-init.log $DEBUG_DIR/cloud-init-bootcmd.log 2>&1 || true; sync" ]'
    'write_files:'
    '  - path: /usr/local/sbin/ctrlx-cloud-init-debug.sh'
    "    permissions: '0755'"
    '    content: |'
    '      #!/bin/bash'
    '      set +e'
    '      mkdir -p /boot/firmware/cloud-init-debug'
    '      cp -f /var/log/cloud-init.log /boot/firmware/cloud-init-debug/cloud-init.log'
    '      cp -f /var/log/cloud-init-output.log /boot/firmware/cloud-init-debug/cloud-init-output.log'
    '      cloud-init status --long > /boot/firmware/cloud-init-debug/status.txt 2>&1'
    '      cloud-init query ds > /boot/firmware/cloud-init-debug/datasource.txt 2>&1'
    '      cp -f /var/log/syslog /boot/firmware/cloud-init-debug/syslog.log'

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

if ($env:PI_USE_PROXY -eq 'true') {
    $piProxy = $env:PI_PROXY_URL
    if ([string]::IsNullOrWhiteSpace($piProxy)) {
        throw 'The Raspberry Pi proxy URL is missing.'
    }
    $userData += @(
        'apt:'
        "  proxy: $piProxy"
        '  conf:'
        "    Acquire::http::Proxy: $piProxy"
        "    Acquire::https::Proxy: $piProxy"
    )
}

$userData += @(
    'runcmd:'
    '  - /usr/local/sbin/ctrlx-cloud-init-debug.sh'
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
    '  - /usr/local/sbin/ctrlx-cloud-init-debug.sh'
)

$networkConfig = @(
    'version: 2'
    'renderer: networkd'
    'ethernets:'
    '  wired:'
    '    match:'
    '      name: "eth*"'
    '    dhcp4: false'
    '    optional: true'
    '    addresses:'
    "      - $ipAddress/24"
    'wifis:'
    '  wireless:'
    '    match:'
    '      name: "wl*"'
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

$cmdlinePath = Join-Path $bootPath 'cmdline.txt'
if (Test-Path -LiteralPath $cmdlinePath) {
    $cmdline = (Get-Content -LiteralPath $cmdlinePath -Raw).Trim()
    $cmdline = [regex]::Replace($cmdline, '(^|\s)ds=nocloud(?:-net)?;[^\s]*', '$1')
    $cmdline = [regex]::Replace($cmdline, '(^|\s)systemd\.show_status=true', '$1')
    $cmdline = [regex]::Replace($cmdline, '(^|\s)systemd\.log_level=debug', '$1')
    $cmdline = [regex]::Replace($cmdline, '(^|\s)systemd\.log_target=console', '$1')
    $cmdline = "$cmdline ds=nocloud;s=file:///boot/firmware/"
    [System.IO.File]::WriteAllText($cmdlinePath, "$cmdline`n", $encoding)
}

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
