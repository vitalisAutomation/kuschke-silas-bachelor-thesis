$ErrorActionPreference = 'Stop'

$bootPath = $env:BOOT_PATH
$username = $env:PI_USERNAME
$password = $env:PI_PASSWORD
$hostname = $env:PI_HOSTNAME
$ipAddress = $env:PI_IP_ADDRESS
$ssid = $env:WIFI_SSID
$wifiPassword = $env:WIFI_PASSWORD
$wifiCountry = $env:WIFI_COUNTRY
$keyboardLayout = $env:KEYBOARD_LAYOUT
$locale = $env:LOCALE
$timezone = $env:TIMEZONE
$publicKeyPath = $env:SSH_KEY_FILE + '.pub'

if ([string]::IsNullOrWhiteSpace($bootPath) -or -not (Test-Path -LiteralPath $bootPath)) {
    throw 'The boot partition path is missing or does not exist.'
}

if ($wifiCountry -notmatch '^[A-Za-z]{2}$') {
    throw 'The Wi-Fi regulatory country must be a two-letter country code.'
}

$wifiCountry = $wifiCountry.ToUpperInvariant()

if ($keyboardLayout -notmatch '^[A-Za-z]{2,3}$') {
    throw 'The keyboard layout must contain two or three letters.'
}

if ($locale -notmatch '^[A-Za-z]{2,3}_[A-Za-z]{2}(?:\.UTF-8)?$') {
    throw 'The locale must use a format such as de_DE.UTF-8.'
}

if ($timezone -notmatch '^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)+$') {
    throw 'The time zone must be a valid zone name such as Europe/Berlin.'
}

$keyboardLayout = $keyboardLayout.ToLowerInvariant()
$locale = $locale -replace '\.utf-8$', '.UTF-8'
if ($locale -notmatch '\.UTF-8$') {
    $locale += '.UTF-8'
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
    'package_update: false'
    "locale: $locale"
    "timezone: $timezone"
    'keyboard:'
    "  layout: $keyboardLayout"
    '  model: pc105'
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
    '      iw reg get > /boot/firmware/cloud-init-debug/iw-reg.txt 2>&1'
    '      iw dev wlan0 info > /boot/firmware/cloud-init-debug/iw-info.txt 2>&1'
    '      iw dev wlan0 link > /boot/firmware/cloud-init-debug/iw-link.txt 2>&1'
    '      dmesg | grep -Ei ''brcmfmac|cfg80211|wlan0|firmware|regulatory'' > /boot/firmware/cloud-init-debug/wlan-kernel.log 2>&1'

    '  - path: /etc/systemd/journald.conf.d/99-ctrlx-persistent.conf'
    "    permissions: '0644'"
    '    content: |'
    '      [Journal]'
    '      Storage=persistent'
    '      SystemMaxUse=200M'
    '      ForwardToConsole=no'

    '  - path: /usr/local/sbin/ctrlx-boot-log.sh'
    "    permissions: '0755'"
    '    content: |'
    '      #!/bin/bash'
    '      set -e'
    '      LOG=/var/log/ctrlx-boot.log'
    '      if mountpoint -q /mnt/ctrlx-logs; then LOG=/mnt/ctrlx-logs/ctrlx-boot.log; else echo "USB mount failed" >> /boot/firmware/cloud-init-debug/usb-mount.txt; fi'
    '      mkdir -p /var/log/journal'
    '      touch "$LOG"'
    '      chmod 0644 "$LOG"'
    '      cp -f /var/log/cloud-init.log /mnt/ctrlx-logs/cloud-init.log 2>/dev/null || true'
    '      cp -f /var/log/cloud-init-output.log /mnt/ctrlx-logs/cloud-init-output.log 2>/dev/null || true'
    '      echo "" >> "$LOG"'
    '      echo "==================== BOOT $(journalctl -b 0 --no-pager -n 1 2>/dev/null | sed -n ''s/.*\[\([0-9-]*\)T.*/\1/p'' | head -1) ====================" >> "$LOG"'
    '      journalctl --flush'
    '      journalctl -b 0 --no-pager -o short-iso >> "$LOG"'
    '      journalctl -b 0 -f -n 0 -o short-iso >> "$LOG"'

    '  - path: /etc/systemd/system/ctrlx-boot-log.service'
    "    permissions: '0644'"
    '    content: |'
    '      [Unit]'
    '      Description=Persist complete boot journal for ctrlX diagnostics'
    '      After=systemd-journald.service'
    '      Wants=systemd-journald.service'
    '      RequiresMountsFor=/mnt/ctrlx-logs'
    ''
    '      [Service]'
    '      Type=simple'
    '      ExecStart=/usr/local/sbin/ctrlx-boot-log.sh'
    '      Restart=on-failure'
    ''
    '      [Install]'
    '      WantedBy=multi-user.target'

    '  - path: /etc/systemd/system/mnt-ctrlx-logs.mount'
    "    permissions: '0644'"
    '    content: |'
    '      [Unit]'
    '      Description=Mount USB stick for ctrlX boot logs'
    '      Before=ctrlx-boot-log.service'
    ''
    '      [Mount]'
    '      What=LABEL=CTRLXLOG'
    '      Where=/mnt/ctrlx-logs'
    '      Type=vfat'
    '      Options=rw,nofail,x-systemd.device-timeout=10s'
    ''
    '      [Install]'
    '      WantedBy=multi-user.target'

    '  - path: /usr/local/sbin/ctrlx-provisioning.sh'
    "    permissions: '0755'"
    '    content: |'
    '      #!/bin/bash'
    '      set +e'
    '      LOG=/mnt/ctrlx-logs/ctrlx-provisioning.log'
    '      if ! mountpoint -q /mnt/ctrlx-logs; then LOG=/var/log/ctrlx-provisioning.log; fi'
    '      exec >> "$LOG" 2>&1'
    '      echo "==== ctrlX provisioning started $(date -Is) ===="'
    '      echo "==== kernel ===="'
    '      cat /proc/cmdline'
    '      echo "==== network ===="'
    '      ip -br addr'
    '      ip route'
    '      resolvectl status'
    '      echo "==== dpkg architectures ===="'
    '      dpkg --print-architecture'
    '      dpkg --print-foreign-architectures'
    '      echo "==== waiting for network ===="'
    '      for attempt in $(seq 1 30); do'
    '        if curl --connect-timeout 3 -fsS https://archive.ubuntu.com/ >/dev/null; then break; fi'
    '        echo "network attempt $attempt failed"'
    '        sleep 2'
    '      done'
    '      if [ "$(dpkg --print-architecture)" = "arm64" ]; then'
    '        for architecture in $(dpkg --print-foreign-architectures); do'
    '          case "$architecture" in amd64|i386) dpkg --remove-architecture "$architecture" ;; esac'
    '        done'
    '      fi'
    '      echo "==== apt update ===="'
    '      apt-get update'
    '      echo "apt-get update exit code: $?"'
    '      echo "==== package installation ===="'
    '      DEBIAN_FRONTEND=noninteractive apt-get install -y iw git unzip curl wget make squashfs-tools snapd openssh-server avahi-daemon'
    '      echo "apt-get install exit code: $?"'
    '      systemctl enable --now ssh'
    '      systemctl enable --now avahi-daemon'
    '      echo "==== ctrlX provisioning finished $(date -Is) ===="'

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

    '  - path: /etc/systemd/system/serial-getty@ttyAMA10.service.d/autologin.conf'
    "    permissions: '0644'"
    '    content: |'
    '      [Service]'
    '      ExecStart='
    ('      ExecStart=-/sbin/agetty --autologin ' + $username + ' --noclear %I $TERM')

    '  - path: /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf'
    "    permissions: '0644'"
    '    content: |'
    '      [Service]'
    '      ExecStart='
    ('      ExecStart=-/sbin/agetty --autologin ' + $username + ' --noclear %I $TERM')

    '  - path: /etc/systemd/system/getty@tty1.service.d/autologin.conf'
    "    permissions: '0644'"
    '    content: |'
    '      [Service]'
    '      ExecStart='
    ('      ExecStart=-/sbin/agetty --autologin ' + $username + ' --noclear %I $TERM')
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
    '  - systemctl daemon-reload'
    '  - systemctl enable --now getty@tty1.service'
    '  - if [ -e /dev/ttyAMA10 ]; then systemctl enable --now serial-getty@ttyAMA10.service; fi'
    '  - if [ -e /dev/ttyS0 ]; then systemctl enable --now serial-getty@ttyS0.service; fi'
    '  - systemctl enable --now ctrlx-apt-update-upgrade.service'
    '  - mkdir -p /mnt/ctrlx-logs'
    '  - mountpoint -q /mnt/ctrlx-logs || mount -L CTRLXLOG -t vfat /mnt/ctrlx-logs'
    '  - mountpoint -q /mnt/ctrlx-logs || echo "USB mount failed" >> /boot/firmware/cloud-init-debug/usb-mount.txt'
    '  - systemctl enable mnt-ctrlx-logs.mount'
    '  - systemctl restart systemd-journald'
    '  - systemctl enable --now ctrlx-boot-log.service'
    '  - /usr/local/sbin/ctrlx-provisioning.sh'
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
    '  ethernet:'
    '    match:'
    '      name: eth0'
    '    dhcp4: false'
    '    optional: true'
    '    addresses:'
    "      - $ipAddress/24"
    'wifis:'
    '  wlan0:'
    '    dhcp4: true'
    '    optional: true'
    "    regulatory-domain: $wifiCountry"
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
    $cmdline = [regex]::Replace($cmdline, '(^|\s)cfg80211\.ieee80211_regdom=[^\s]*', '$1')
    $cmdline = "$cmdline cfg80211.ieee80211_regdom=$wifiCountry ds=nocloud;s=file:///boot/firmware/"
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
