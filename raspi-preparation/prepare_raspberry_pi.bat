:: Source information
:: Source: Gemini 3.6
:: Edited by Silas Kuschke

@echo off

chcp 65001 >nul

:: Generate the escape character for reliable ANSI color output

for /f "tokens=1,2 delims=#" %%a in ('"prompt #$H#$E# & echo on & for %%b in (1) do rem"') do set "ESC=%%b"

:: Define ANSI color codes

set "BLUE=%ESC%[94m"
set "GREEN=%ESC%[92m"
set "YELLOW=%ESC%[93m"
set "RED=%ESC%[91m"
set "RESET=%ESC%[0m"

cd /d "%~dp0"
set "PROJECT_PATH=%~dp0"
set "IMAGER_VERSION=1.8.5"
set "IMAGER_EXE="
set "IMAGER_CLI="
set "PI_USERNAME=sdk-pi"
set "PI_PASSWORD=sdk-pi"
set "PI_HOSTNAME=sdk-pi"
set "PI_MDNS_HOSTNAME=%PI_HOSTNAME%.local"
set "PI_IP_ADDRESS=192.168.1.100"
set "PC_IP_LAST_OCTET=10"
set "PC_IP_ADDRESS=192.168.1.10"
set "PI_USE_PROXY=false"
set "PI_PROXY_URL="
set "WIFI_COUNTRY=DE"
set "KEYBOARD_LAYOUT=de"
set "LOCALE=de_DE.UTF-8"
set "TIMEZONE=Europe/Berlin"
set "SSH_DIR=%USERPROFILE%\.ssh"
set "SSH_KEY_FILE=%SSH_DIR%\id_rsa_ctrlx_pi"
set "IMAGE_SHA256="
set "WIFI_PASSWORD_FILE=%TEMP%\ctrlx-wifi-password-%RANDOM%.tmp"

:: Create the SSH key before generating any Pi or SSH configuration
if not exist "%SSH_DIR%" mkdir "%SSH_DIR%" >nul 2>&1
if not exist "%SSH_KEY_FILE%" (
    echo %YELLOW%[SSH] Generating an RSA key for Raspberry Pi access...%RESET%
    ssh-keygen.exe -t rsa -b 4096 -N "" -f "%SSH_KEY_FILE%"
    if errorlevel 1 (
        echo %RED%[ERROR] Could not generate the Raspberry Pi SSH key.%RESET%
        pause
        exit /b 1
    )
) else (
    echo %GREEN%[SSH] Existing Raspberry Pi key will be reused.%RESET%
)

if not exist "%SSH_KEY_FILE%.pub" (
    ssh-keygen.exe -y -f "%SSH_KEY_FILE%" > "%SSH_KEY_FILE%.pub"
    if errorlevel 1 (
        echo %RED%[ERROR] Could not create the Raspberry Pi public SSH key.%RESET%
        pause
        exit /b 1
    )
)

if not exist "%SSH_KEY_FILE%" (
    echo %RED%[ERROR] The SSH private key is missing.%RESET%
    pause
    exit /b 1
)
if not exist "%SSH_KEY_FILE%.pub" (
    echo %RED%[ERROR] The SSH key pair is incomplete or invalid.%RESET%
    pause
    exit /b 1
)

:: =======================================================================
:: Check and install the required development tools
:: =======================================================================

if "%~1"=="-install-dependencies" goto :INSTALL_DEPENDENCIES

set "NETWORK_READY="
set "MISSING_DEV_TOOLS="
set "INSTALL_VSCODE_FLAG="
set "INSTALL_REMOTE_SSH_FLAG="
set "INSTALL_EXTENSIONS_FLAG="
call :CHECK_DEVELOPMENT_TOOLS

if defined MISSING_DEV_TOOLS (
    call :PREPARE_NETWORK
    if errorlevel 1 exit /b 1
    goto :REQUEST_ADMIN
)
goto :START_MENU

:RPI_IMAGER_MISSING
cls
echo %BLUE%=======================================================================%RESET%
echo %RED%             RASPBERRY PI IMAGER IS REQUIRED%RESET%
echo %BLUE%=======================================================================%RESET%
echo.
echo %RED%[ERROR] Raspberry Pi Imager %IMAGER_VERSION% was not found.%RESET%
echo Please install Raspberry Pi Imager and run this script again.
pause
exit /b 1

:REQUEST_ADMIN
cls
echo %BLUE%=======================================================================%RESET%
echo %YELLOW%             REQUIRED DEVELOPMENT TOOLS ARE MISSING%RESET%
echo %BLUE%=======================================================================%RESET%
echo.
echo %YELLOW%[Check] The following required component(s) are missing:%RESET%
echo %RED%  * %MISSING_DEV_TOOLS%%RESET%
echo.
echo %YELLOW%Administrator rights are required for the automatic installation.%RESET%
echo.
echo %GREEN%A new terminal window will now be opened as administrator.%RESET%
echo %GREEN%The missing component(s) will be installed there automatically.%RESET%
echo.
echo Press any key to continue...
pause >nul

set "INSTALL_ARGS=-install-dependencies"
if defined INSTALL_VSCODE_FLAG set "INSTALL_ARGS=%INSTALL_ARGS% -install-vscode"
if defined INSTALL_REMOTE_SSH_FLAG set "INSTALL_ARGS=%INSTALL_ARGS% -install-remote-ssh"
if defined INSTALL_EXTENSIONS_FLAG set "INSTALL_ARGS=%INSTALL_ARGS% -install-extensions"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%INSTALL_ARGS%' -Verb RunAs"
exit

:INSTALL_DEPENDENCIES
cls
echo %BLUE%=======================================================================%RESET%
echo %GREEN%             INSTALLING REQUIRED DEVELOPMENT TOOLS%RESET%
echo %BLUE%=======================================================================%RESET%
echo.

set "ARG_STRING=%*"

set "CURL_PROXY_ARGS="
set "WINGET_PROXY_ARGS="
if "%USE_PROXY%"=="true" (
    set "CURL_PROXY_ARGS=-x "%PROXY_URL%""
    set "WINGET_PROXY_ARGS=--proxy "%PROXY_URL%""
    set "HTTP_PROXY=%PROXY_URL%"
    set "HTTPS_PROXY=%PROXY_URL%"
)

echo %ARG_STRING% | findstr /i /c:"-install-vscode" >nul
if not errorlevel 1 (
    echo %YELLOW%[VS Code] Visual Studio Code is missing.%RESET%
    echo %YELLOW%[VS Code] Downloading the official installer...%RESET%
    curl.exe --fail --retry 3 --retry-all-errors %CURL_PROXY_ARGS% -L -# -o "%PROJECT_PATH%vscode_setup.exe" "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user"
    if not exist "%PROJECT_PATH%vscode_setup.exe" (
        echo %RED%[ERROR] VS Code download failed.%RESET%
        pause
        exit /b 1
    )
    echo %YELLOW%[VS Code] Installing Visual Studio Code for the current user...%RESET%
    start /wait "" "%PROJECT_PATH%vscode_setup.exe" /VERYSILENT /NORESTART
    if errorlevel 1 (
        echo %RED%[ERROR] VS Code installer failed.%RESET%
        del "%PROJECT_PATH%vscode_setup.exe" >nul 2>&1
        pause
        exit /b 1
    )
    del "%PROJECT_PATH%vscode_setup.exe" >nul 2>&1
    call :CHECK_VSCODE_PATH
    if not defined CODE_EXE (
        echo %RED%[ERROR] VS Code could not be found after installation.%RESET%
        pause
        exit /b 1
    )
    echo %GREEN%[VS Code] Installation completed successfully.%RESET%
)

echo %ARG_STRING% | findstr /i /r /c:"-install-remote-ssh" /c:"-install-extensions" >nul
if not errorlevel 1 (
    call :CHECK_VSCODE_PATH
    if not defined CODE_EXE (
        echo %RED%[ERROR] The VS Code command-line tool is unavailable.%RESET%
        pause
        exit /b 1
    )
    echo %YELLOW%[VS Code] Installing missing extensions...%RESET%
    for %%e in (golang.go ms-dotnettools.csharp ms-python.python ms-vscode-remote.remote-ssh ms-vscode.cmake-tools ms-vscode.cpptools vscjava.vscode-java-pack twxs.cmake) do (
        "%CODE_EXE%" --list-extensions 2>nul | findstr /i /r /b /e /c:"%%e" >nul
        if errorlevel 1 (
            echo %BLUE%  * Installing %%e...%RESET%
            "%CODE_EXE%" --install-extension %%e --force >> "install_debug.log" 2>&1
            if errorlevel 1 (
                echo %RED%[ERROR] Extension %%e installation failed.%RESET%
                pause
                exit /b 1
            )
        )
    )
    echo %GREEN%[VS Code] Extension installation completed successfully.%RESET%
)

echo.
echo %GREEN%All required development tools are ready.%RESET%
echo %YELLOW%The Raspberry Pi preparation menu will now start.%RESET%
timeout /t 2 /nobreak >nul
goto :START_MENU

:: =======================================================================
:: Main menu and workflow selection
:: =======================================================================

:START_MENU

cls

echo %BLUE%=======================================================================%RESET%
echo %GREEN%                 RASPBERRY PI PREPARATION%RESET%
echo %BLUE%=======================================================================%RESET%
echo(
echo 1) Connect directly to an existing Raspberry Pi via VS Code Remote-SSH
echo 2) Download Ubuntu and flash an SD card
echo 3) Exit
echo.

set "MODE_CHOICE="
set /p MODE_CHOICE="%YELLOW%Choose an option (1, 2 or 3): %RESET%"

if "%MODE_CHOICE%"=="1" goto :CONNECT_SSH
if "%MODE_CHOICE%"=="2" goto :MAIN_MENU
if "%MODE_CHOICE%"=="3" exit
goto :START_MENU

:: =======================================================================
:: SD card flashing and Ubuntu version selection
:: =======================================================================

:MAIN_MENU

call :CHECK_RPI_IMAGER_LOCAL
if errorlevel 1 goto :RPI_IMAGER_MISSING

cls

echo %BLUE%=======================================================================%RESET%
echo %GREEN%                 SD CARD PREPARATION%RESET%
echo %BLUE%=======================================================================%RESET%
echo(
echo This setup downloads an Ubuntu Server image for Raspberry Pi and
echo uses Raspberry Pi Imager to flash the selected image to an SD card.
echo.
echo %YELLOW%[NOTICE] Administrator rights are required for flashing the SD card.%RESET%
echo If Windows asks for permission, confirm the administrator prompt.
echo.
echo Please make sure that the SD card is connected before starting Raspberry Pi Imager.
echo The selected drive will be erased completely.
echo(
echo %BLUE%Please choose the target software version:%RESET%
echo.
echo 1) ctrlX OS 1.x / 2.x / 3.x - Ubuntu Server 22.04 LTS (ARM64)
echo 2) ctrlX OS 4.x             - Ubuntu Server 24.04 LTS (ARM64)
echo 3) Back
echo(

set "OS_CHOICE="
set /p OS_CHOICE="%YELLOW%Choose an option (1, 2 or 3): %RESET%"

if "%OS_CHOICE%"=="1" (
    set "UBUNTU_VERSION=22.04.5"
    set "CTRLX_TARGET=ctrlX OS 1.x / 2.x / 3.x"
    set "IMAGE_URL=https://cdimage.ubuntu.com/releases/22.04/release/ubuntu-22.04.5-preinstalled-server-arm64+raspi.img.xz"
    set "IMAGE_FILE=%PROJECT_PATH%ubuntu-22.04.5-preinstalled-server-arm64+raspi.img.xz"
    set "IMAGE_FLASH_FILE=%PROJECT_PATH%ubuntu-22.04.5-preinstalled-server-arm64+raspi.img"
    set "IMAGE_SHA256=fd7687c5c9422a6c7ba4717c227bf6473fe4e0c954d5a9f664201dcecc63e822"
    goto :NET_PROXY_CHECK
)

if "%OS_CHOICE%"=="2" (
    set "UBUNTU_VERSION=24.04.3"
    set "CTRLX_TARGET=ctrlX OS 4.x"
    set "IMAGE_URL=https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz"
    set "IMAGE_FILE=%PROJECT_PATH%ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz"
    set "IMAGE_FLASH_FILE=%PROJECT_PATH%ubuntu-24.04.3-preinstalled-server-arm64+raspi.img"
    set "IMAGE_SHA256=9bb1799cee8965e6df0234c1c879dd35be1d87afe39b84951f278b6bd0433e56"
    goto :NET_PROXY_CHECK
)

if "%OS_CHOICE%"=="3" goto :START_MENU

goto :MAIN_MENU

:: =======================================================================
:: Connect to an existing Raspberry Pi through VS Code Remote-SSH
:: =======================================================================

:CONNECT_SSH

cls

echo %BLUE%=======================================================================%RESET%
echo %GREEN%                 CONNECT TO RASPBERRY PI%RESET%
echo %BLUE%=======================================================================%RESET%
echo.
echo Enter the Raspberry Pi IP address or hostname.
echo Use %PI_MDNS_HOSTNAME% only when mDNS is available on this computer.
echo Press Enter to accept each displayed default value.
echo.

set "SSH_HOST="
set /p SSH_HOST="%YELLOW%Pi host or IP address (default %PI_IP_ADDRESS%): %RESET%"
if not defined SSH_HOST set "SSH_HOST=%PI_IP_ADDRESS%"
if not defined SSH_HOST (
    echo %RED%[ERROR] A host or IP address is required.%RESET%
    pause
    goto :START_MENU
)

set "SSH_USER=%PI_USERNAME%"
set "SSH_USER_INPUT="
set /p SSH_USER_INPUT="%YELLOW%SSH username (default %PI_USERNAME%): %RESET%"
if defined SSH_USER_INPUT set "SSH_USER=%SSH_USER_INPUT%"

call :CHECK_VSCODE_PATH
if not defined CODE_EXE (
    echo %RED%[ERROR] Visual Studio Code could not be found.%RESET%
    pause
    goto :START_MENU
)

call :CHECK_REMOTE_SSH_EXTENSION
if errorlevel 1 (
    echo %RED%[ERROR] The VS Code Remote-SSH extension is not installed.%RESET%
    pause
    goto :START_MENU
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_PATH%configure_vscode_remote_ssh.ps1"
if errorlevel 1 (
    echo %RED%[ERROR] Could not configure local Remote-SSH server download.%RESET%
    pause
    goto :START_MENU
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_PATH%configure_raspberry_pi_ssh.ps1"
if errorlevel 1 (
    echo %RED%[ERROR] Could not configure the SSH connection for the Raspberry Pi.%RESET%
    pause
    goto :START_MENU
)

echo.
echo %YELLOW%Testing the SSH connection to %SSH_USER%@%SSH_HOST%...%RESET%
set "SSH_TEST_LOG=%TEMP%\ctrlx-ssh-test.log"
ssh.exe -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 ctrlx-pi "true" > "%SSH_TEST_LOG%" 2>&1
if errorlevel 1 (
    type "%SSH_TEST_LOG%"
    findstr /i /c:"REMOTE HOST IDENTIFICATION HAS CHANGED" /c:"Host key verification failed." "%SSH_TEST_LOG%" >nul
    if not errorlevel 1 (
        echo.
        echo %YELLOW%The Pi was probably reflashed and has a new SSH host key.%RESET%
        echo Only continue if you recognize and expect this host-key change.
        choice /c YN /n /m "%YELLOW%Remove the old known_hosts entry for %SSH_HOST% and retry? (Y/N): %RESET%"
        if errorlevel 2 goto :SSH_CONNECTION_ERROR
        ssh-keygen.exe -R "%SSH_HOST%"
        if errorlevel 1 goto :SSH_CONNECTION_ERROR
        ssh.exe -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 ctrlx-pi "true" > "%SSH_TEST_LOG%" 2>&1
        if not errorlevel 1 goto :SSH_CONNECTION_VERIFIED
        type "%SSH_TEST_LOG%"
    )
:SSH_CONNECTION_ERROR
    echo %RED%[ERROR] The Raspberry Pi is not reachable via SSH.%RESET%
    echo Check that the Pi has the configured IP address and that sshd is running.
    del /q "%SSH_TEST_LOG%" >nul 2>&1
    pause
    goto :START_MENU
)
:SSH_CONNECTION_VERIFIED
del /q "%SSH_TEST_LOG%" >nul 2>&1
echo %GREEN%SSH connection verified.%RESET%

echo.
echo %YELLOW%Opening VS Code Remote-SSH for %SSH_USER%@%SSH_HOST%...%RESET%
call "%CODE_EXE%" --new-window --remote "ssh-remote+ctrlx-pi" "/home/%SSH_USER%"
if errorlevel 1 (
    echo %RED%[ERROR] VS Code could not start the Remote-SSH connection.%RESET%
    pause
    goto :START_MENU
)
call :INSTALL_PI_EXTENSIONS
echo %GREEN%VS Code Remote-SSH was started.%RESET%
pause
goto :START_MENU

:: =======================================================================
:: Check the proxy configuration before downloading the image
:: =======================================================================

:NET_PROXY_CHECK

if not defined PROXY_READY (
    set "NETWORK_READY="
    call :PREPARE_NETWORK
    if not defined NETWORK_READY goto :MAIN_MENU
)
goto :DOWNLOAD_FILES

:: =======================================================================
:: Download and prepare the Ubuntu image for flashing
:: =======================================================================

:DOWNLOAD_FILES

cls

echo %BLUE%=======================================================================%RESET%
echo %GREEN%                  DOWNLOAD REQUIRED SOFTWARE%RESET%
echo %BLUE%=======================================================================%RESET%
echo(
echo Target: %CTRLX_TARGET%
echo Ubuntu image: Ubuntu Server %UBUNTU_VERSION% LTS for Raspberry Pi (ARM64)
echo.

goto :CREDENTIALS_READY

:CREDENTIALS_READY

:: Collect the Wi-Fi credentials required during first boot
if not defined WIFI_SSID (
    echo.
    echo %BLUE%[Wi-Fi] Enter the wireless network for the Raspberry Pi.%RESET%
    echo %YELLOW%IMPORTANT: The Pi must connect to a hotspot with Internet access.%RESET%
    echo %YELLOW%It needs this connection to download Ubuntu packages, the SDK and VS Code extensions.%RESET%
    set /p WIFI_SSID="%YELLOW%Wi-Fi SSID: %RESET%"
    set "WIFI_PASSWORD="
    set "WIFI_PASSWORD_CONFIRM="
    powershell.exe -NoProfile -Command "$read = { param($prompt); $secure = Read-Host -Prompt $prompt -AsSecureString; $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure); try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) } }; $first = &$read 'Wi-Fi password'; $second = &$read 'Confirm Wi-Fi password'; $encoding = New-Object Text.UTF8Encoding($false); if ($first -cne $second) { [IO.File]::WriteAllText($env:WIFI_PASSWORD_FILE, '__PASSWORD_MISMATCH__', $encoding); exit 2 }; [IO.File]::WriteAllText($env:WIFI_PASSWORD_FILE, $first, $encoding)"
    if exist "%WIFI_PASSWORD_FILE%" set /p WIFI_PASSWORD=<"%WIFI_PASSWORD_FILE%"
    del "%WIFI_PASSWORD_FILE%" >nul 2>&1
    if not defined WIFI_SSID (
        echo %RED%[ERROR] The Wi-Fi SSID must not be empty.%RESET%
        pause
        goto :MAIN_MENU
    )
    if "%WIFI_PASSWORD%"=="__PASSWORD_MISMATCH__" (
        echo %RED%[ERROR] The Wi-Fi passwords do not match.%RESET%
        pause
        goto :MAIN_MENU
    )
    if not defined WIFI_PASSWORD (
        echo %RED%[ERROR] The Wi-Fi password must not be empty.%RESET%
        pause
        goto :MAIN_MENU
    )
)

if not defined WIFI_PASSWORD goto :MAIN_MENU

echo.
echo %BLUE%[Wi-Fi] Select the regulatory country for the Raspberry Pi.%RESET%
echo Press Enter to keep the default country code DE.
set "WIFI_COUNTRY_INPUT="
set /p WIFI_COUNTRY_INPUT="%YELLOW%Country code (default DE): %RESET%"
if not defined WIFI_COUNTRY_INPUT set "WIFI_COUNTRY_INPUT=DE"
set "WIFI_COUNTRY="
for /f "delims=" %%C in ('powershell.exe -NoProfile -Command "$c=$env:WIFI_COUNTRY_INPUT.Trim().ToUpperInvariant(); if ($c -match '^[A-Z]{2}$') { $c }"') do set "WIFI_COUNTRY=%%C"
if not defined WIFI_COUNTRY (
    echo %RED%[ERROR] Please enter a two-letter country code, for example DE.%RESET%
    pause
    goto :MAIN_MENU
)

echo Press Enter to keep the default keyboard layout DE.
set "KEYBOARD_LAYOUT_INPUT="
set /p KEYBOARD_LAYOUT_INPUT="%YELLOW%Keyboard layout (default DE): %RESET%"
if not defined KEYBOARD_LAYOUT_INPUT set "KEYBOARD_LAYOUT_INPUT=DE"
set "KEYBOARD_LAYOUT="
for /f "delims=" %%K in ('powershell.exe -NoProfile -Command "$k=$env:KEYBOARD_LAYOUT_INPUT.Trim().ToLowerInvariant(); if ($k -match '^[a-z]{2,3}$') { $k }"') do set "KEYBOARD_LAYOUT=%%K"
if not defined KEYBOARD_LAYOUT (
    echo %RED%Please enter a valid keyboard layout, for example DE or US.%RESET%
    pause
    goto :MAIN_MENU
)

echo Press Enter to keep the default system locale de_DE.UTF-8.
set "LOCALE_INPUT="
set /p LOCALE_INPUT="%YELLOW%System locale (default de_DE.UTF-8): %RESET%"
if not defined LOCALE_INPUT set "LOCALE_INPUT=de_DE.UTF-8"
set "LOCALE="
for /f "delims=" %%L in ('powershell.exe -NoProfile -Command "$l=$env:LOCALE_INPUT.Trim(); if ($l -match '^[A-Za-z]{2,3}_[A-Za-z]{2}(?:\.UTF-8)?$') { if ($l -notmatch '\.UTF-8$') { $l += '.UTF-8' }; $l }"') do set "LOCALE=%%L"
if not defined LOCALE (
    echo %RED%Please enter a valid locale, for example de_DE.UTF-8 or en_US.UTF-8.%RESET%
    pause
    goto :MAIN_MENU
)

echo Press Enter to keep the default time zone Europe/Berlin.
set "TIMEZONE_INPUT="
set /p TIMEZONE_INPUT="%YELLOW%Time zone (default Europe/Berlin): %RESET%"
if not defined TIMEZONE_INPUT set "TIMEZONE_INPUT=Europe/Berlin"
set "TIMEZONE="
for /f "delims=" %%T in ('powershell.exe -NoProfile -Command "$t=$env:TIMEZONE_INPUT.Trim(); if ($t -match '^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)+$') { $t }"') do set "TIMEZONE=%%T"
if not defined TIMEZONE (
    echo %RED%Please enter a valid time zone, for example Europe/Berlin.%RESET%
    pause
    goto :MAIN_MENU
)

echo.
echo %BLUE%[Raspberry Pi] Configure an HTTP/HTTPS proxy for the Pi?%RESET%
echo The download proxy configured earlier is only used by this Windows PC.
set "PI_USE_PROXY=false"
set "PI_PROXY_URL="
choice /c YN /n /m "%YELLOW%Use a proxy on the Raspberry Pi? (Y/N): %RESET%"
if errorlevel 2 goto :PI_PROXY_READY
if errorlevel 1 goto :PI_PROXY_SET

:PI_PROXY_SET
set "PI_USE_PROXY=true"
set /p PI_PROXY_URL="%YELLOW%Raspberry Pi proxy URL (for example http://192.168.1.10:3128): %RESET%"
if not defined PI_PROXY_URL (
    echo %RED%[ERROR] The Raspberry Pi proxy URL must not be empty.%RESET%
    pause
    goto :MAIN_MENU
)

:PI_PROXY_READY

call :CONFIGURE_DEVELOPMENT_PC_NETWORK
if errorlevel 1 goto :MAIN_MENU

if exist "%IMAGE_FILE%" (
    echo %GREEN%[Ubuntu] Image already exists. Skipping download.%RESET%
) else (
    echo %YELLOW%[Ubuntu] Downloading the official Ubuntu image...%RESET%
    if "%USE_PROXY%"=="true" (
        curl.exe --fail --retry 3 --retry-all-errors -x "%PROXY_URL%" -L -# -o "%IMAGE_FILE%" "%IMAGE_URL%"
    ) else (
        curl.exe --fail --retry 3 --retry-all-errors -L -# -o "%IMAGE_FILE%" "%IMAGE_URL%"
    )
    if not exist "%IMAGE_FILE%" (
        echo %RED%[ERROR] Ubuntu image download failed. Please check the network and proxy settings.%RESET%
        pause
        goto :MAIN_MENU
    )
)

call :VERIFY_IMAGE_ARCHIVE
if errorlevel 1 (
    echo %RED%[ERROR] The Ubuntu image checksum is invalid.%RESET%
    echo Please delete the downloaded archive and run the setup again.
    pause
    goto :MAIN_MENU
)

:: Verify the archive and extract the image for Raspberry Pi Imager
if not exist "C:\Program Files\7-Zip\7z.exe" if not exist "%ProgramFiles%\7-Zip\7z.exe" (
    echo %RED%[ERROR] 7-Zip is required to prepare the image for Raspberry Pi Imager.%RESET%
    echo Please install 7-Zip and run this script again.
    pause
    goto :MAIN_MENU
)

set "SEVEN_ZIP_EXE=%ProgramFiles%\7-Zip\7z.exe"
if not exist "%SEVEN_ZIP_EXE%" set "SEVEN_ZIP_EXE=C:\Program Files\7-Zip\7z.exe"

echo %YELLOW%[Ubuntu] Verifying and extracting the image for Raspberry Pi Imager...%RESET%
"%SEVEN_ZIP_EXE%" t "%IMAGE_FILE%" >nul
if errorlevel 1 (
    echo %RED%[ERROR] The downloaded Ubuntu archive is corrupt.%RESET%
    pause
    goto :MAIN_MENU
)
if exist "%IMAGE_FLASH_FILE%" del /q "%IMAGE_FLASH_FILE%" >nul 2>&1
"%SEVEN_ZIP_EXE%" e -y -o"%PROJECT_PATH%" "%IMAGE_FILE%" >nul
if errorlevel 1 (
    echo %RED%[ERROR] Could not fully extract the Ubuntu image.%RESET%
    if exist "%IMAGE_FLASH_FILE%" del /q "%IMAGE_FLASH_FILE%" >nul 2>&1
    pause
    goto :MAIN_MENU
)
if not exist "%IMAGE_FLASH_FILE%" (
    echo %RED%[ERROR] Could not extract the Ubuntu image.%RESET%
    pause
    goto :MAIN_MENU
)
for %%F in ("%IMAGE_FLASH_FILE%") do if %%~zF LSS 1000000000 (
    echo %RED%[ERROR] The extracted Ubuntu image is unexpectedly small.%RESET%
    del /q "%IMAGE_FLASH_FILE%" >nul 2>&1
    pause
    goto :MAIN_MENU
)

call :CHECK_RPI_IMAGER_LOCAL
if errorlevel 1 goto :RPI_IMAGER_MISSING

echo %GREEN%[Raspberry Pi Imager] Local executable: %IMAGER_EXE%%RESET%

:: Raspberry Pi Imager CLI expects a physical device path rather than a drive letter.
echo.
echo Enter the drive letter currently assigned to the SD card, for example E:.
set "TARGET_DRIVE="
set /p TARGET_DRIVE="%YELLOW%SD card drive letter: %RESET%"
set "TARGET_DRIVE=%TARGET_DRIVE::=%"
set "TARGET_DRIVE=%TARGET_DRIVE: =%"
echo(%TARGET_DRIVE%| findstr /r /x /i "[A-Z]" >nul
if errorlevel 1 (
    echo %RED%[ERROR] Enter exactly one SD card drive letter, for example E:.%RESET%
    pause
    goto :MAIN_MENU
)
set "TARGET_DISK="
set "TARGET_IS_BOOT="
set "TARGET_IS_SYSTEM="
set "TARGET_DEVICE="
for /f "delims=" %%D in ('powershell.exe -NoProfile -Command "$p = Get-Partition -DriveLetter '%TARGET_DRIVE%' -ErrorAction SilentlyContinue; $p.DiskNumber"') do set "TARGET_DISK=%%D"
if defined TARGET_DISK for /f "delims=" %%D in ('powershell.exe -NoProfile -Command "$d = Get-Disk -Number %TARGET_DISK%; $d.IsBoot"') do set "TARGET_IS_BOOT=%%D"
if defined TARGET_DISK for /f "delims=" %%D in ('powershell.exe -NoProfile -Command "$d = Get-Disk -Number %TARGET_DISK%; $d.IsSystem"') do set "TARGET_IS_SYSTEM=%%D"
if defined TARGET_DISK if /i not "%TARGET_IS_BOOT%"=="True" if /i not "%TARGET_IS_SYSTEM%"=="True" set "TARGET_DEVICE=\\.\PhysicalDrive%TARGET_DISK%"
if not defined TARGET_DEVICE (
    echo %RED%[ERROR] The drive letter is invalid or belongs to a system disk.%RESET%
    pause
    goto :MAIN_MENU
)
echo %YELLOW%[Raspberry Pi Imager] Target device: %TARGET_DEVICE%%RESET%
echo %RED%[WARNING] The selected device will be erased completely.%RESET%
echo.
set "FLASH_CONFIRM="
set /p FLASH_CONFIRM="Continue with flashing? (Y/N): "
if /i not "%FLASH_CONFIRM%"=="Y" goto :MAIN_MENU
echo.
echo %YELLOW%The SD card will remain mounted after flashing so Cloud-Init can be written.%RESET%
call :DISABLE_IMAGER_EJECT
pushd "%IMAGER_DIR%"
call "%IMAGER_CLI%" "%IMAGE_FLASH_FILE%" "%TARGET_DEVICE%"
set "IMAGER_FAILED="
if errorlevel 1 set "IMAGER_FAILED=1"
popd
echo.
if defined IMAGER_FAILED (
    echo %RED%[ERROR] Raspberry Pi Imager reported a flash or verification failure.%RESET%
    pause
    goto :MAIN_MENU
)
echo %GREEN%[Raspberry Pi Imager] Flash and verification completed successfully.%RESET%
echo Continuing with first-boot configuration...
goto :CONFIGURE_FIRST_BOOT

:: =======================================================================
:: Configure Cloud-Init on the Ubuntu boot partition
:: =======================================================================

:CONFIGURE_FIRST_BOOT

cls

echo %BLUE%=======================================================================%RESET%
echo %GREEN%                 CONFIGURE UBUNTU FIRST BOOT%RESET%
echo %BLUE%=======================================================================%RESET%
echo(
echo The Ubuntu boot partition should now be visible in Windows Explorer.
echo It is usually mounted as the drive named "system-boot".
echo.
echo Enter only the drive letter, for example E:
echo Do not enter the Linux root partition.
echo(

set "BOOT_DRIVE="
set /p BOOT_DRIVE="%YELLOW%Boot partition drive letter: %RESET%"
set "BOOT_DRIVE=%BOOT_DRIVE::=%"
set "BOOT_DRIVE=%BOOT_DRIVE: =%"
echo(%BOOT_DRIVE%| findstr /r /x /i "[A-Z]" >nul
if errorlevel 1 (
    echo %RED%[ERROR] Enter exactly one boot partition drive letter, for example E:.%RESET%
    pause
    goto :CONFIGURE_FIRST_BOOT
)
set "BOOT_DRIVE=%BOOT_DRIVE%:"
if not "%BOOT_DRIVE:~-1%"==":" set "BOOT_DRIVE=%BOOT_DRIVE%:"
set "BOOT_PATH=%BOOT_DRIVE%\"

if not exist "%BOOT_PATH%" (
    echo %RED%[ERROR] The selected drive does not exist.%RESET%
    pause
    goto :CONFIGURE_FIRST_BOOT
)

echo.
echo %YELLOW%Writing Cloud-Init configuration to %BOOT_PATH%...%RESET%

:: PowerShell writes UTF-8 YAML and safely escapes Wi-Fi credentials
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_PATH%configure_cloud_init.ps1"
if errorlevel 1 goto :CONFIGURATION_ERROR
if not exist "%BOOT_PATH%user-data" goto :CONFIGURATION_ERROR
if not exist "%BOOT_PATH%network-config" goto :CONFIGURATION_ERROR
if not exist "%BOOT_PATH%meta-data" goto :CONFIGURATION_ERROR
if not exist "%BOOT_PATH%cmdline.txt" goto :CONFIGURATION_ERROR
findstr /i /c:"ds=nocloud;s=file:///boot/firmware/" "%BOOT_PATH%cmdline.txt" >nul
if errorlevel 1 goto :CONFIGURATION_ERROR
goto :CONFIGURATION_READY

:CONFIGURATION_ERROR

echo %RED%[ERROR] Could not write all Cloud-Init files to the selected boot partition.%RESET%
echo Required files: meta-data, user-data, network-config, cmdline.txt
echo cmdline.txt must contain: ds=nocloud;s=file:///boot/firmware/
pause
goto :MAIN_MENU

:CONFIGURATION_READY

echo.
echo %GREEN%Cloud-Init configuration completed successfully.%RESET%
echo.
echo %YELLOW%The Cloud-Init files are now on the SD card.%RESET%
echo %YELLOW%Safely ejecting the SD card and USB reader...%RESET%
call :EJECT_SD_CARD
if errorlevel 1 goto :EJECT_ERROR
echo %GREEN%SD card and USB reader were safely ejected and can now be removed.%RESET%
echo.
echo Hostname: %PI_HOSTNAME%
echo Host/IP: %PI_IP_ADDRESS%
echo SSH username: %PI_USERNAME%
echo Development computer IP: %PC_IP_ADDRESS%
echo Wi-Fi SSID: %WIFI_SSID%
echo SSH private key: %SSH_KEY_FILE%
echo.
echo Insert the SD card into the Raspberry Pi and power it on.
echo The SDK and Snapcraft installation will run automatically on first boot.
echo The first boot may take several minutes.
echo.
pause
exit

:EJECT_ERROR

echo %RED%[WARNING] Cloud-Init was written, but Windows could not eject the SD card and USB reader automatically.%RESET%
echo Close any Explorer windows or applications using %BOOT_DRIVE% and eject it manually.
pause
exit /b 1

:EJECT_SD_CARD

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$process = Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%PROJECT_PATH%eject_sd_card.ps1','-DriveLetter','%BOOT_DRIVE:~0,1%' -Verb RunAs -Wait -PassThru; exit $process.ExitCode"
if errorlevel 1 exit /b 1
exit /b 0

:DISABLE_IMAGER_EJECT

reg add "HKCU\Software\Raspberry Pi\Imager" /v eject /t REG_SZ /d false /f >nul 2>&1
reg add "HKCU\Software\Raspberry Pi\Raspberry Pi Imager" /v eject /t REG_SZ /d false /f >nul 2>&1
exit /b 0

:CONFIGURE_DEVELOPMENT_PC_NETWORK

echo.
echo %BLUE%[Network] Configure the development computer Ethernet address.%RESET%
echo The Raspberry Pi will use %PI_IP_ADDRESS%/24.
echo The development computer must use 192.168.1.x/24.
echo.
set "PC_IP_LAST_OCTET="
set /p PC_IP_LAST_OCTET="%YELLOW%Last IP octet for this computer (default 10): %RESET%"
if not defined PC_IP_LAST_OCTET set "PC_IP_LAST_OCTET=10"
for /f "delims=0123456789" %%A in ("%PC_IP_LAST_OCTET%") do (
    echo %RED%[ERROR] Please enter a number between 1 and 254.%RESET%
    exit /b 1
)
 powershell.exe -NoProfile -Command "$n=0; if (-not [int]::TryParse($env:PC_IP_LAST_OCTET,[ref]$n) -or $n -lt 1 -or $n -gt 254) { exit 1 }"
if errorlevel 1 (
    echo %RED%[ERROR] Please enter a number between 1 and 254.%RESET%
    exit /b 1
)
if "%PC_IP_LAST_OCTET%"=="1" (
    echo %RED%[ERROR] The value 1 is reserved for the ctrlX Core.%RESET%
    exit /b 1
)
set "PC_IP_ADDRESS=192.168.1.%PC_IP_LAST_OCTET%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$process = Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%PROJECT_PATH%configure_development_pc_network.ps1','-LastOctet','%PC_IP_LAST_OCTET%','-PiIpAddress','%PI_IP_ADDRESS%' -Verb RunAs -Wait -PassThru; exit $process.ExitCode"
if errorlevel 1 (
    echo %RED%[ERROR] Could not configure the development computer Ethernet address.%RESET%
    exit /b 1
)
echo %GREEN%[Network] Development computer: %PC_IP_ADDRESS%/24%RESET%
echo %GREEN%[Network] Raspberry Pi: %PI_IP_ADDRESS%/24%RESET%
exit /b 0

:CHECK_DEVELOPMENT_TOOLS
set "CODE_EXE="
call :CHECK_VSCODE_PATH
if not defined CODE_EXE (
    call :ADD_MISSING_DEV_TOOL "Visual Studio Code"
    set "INSTALL_VSCODE_FLAG=1"
    set "INSTALL_REMOTE_SSH_FLAG=1"
    set "INSTALL_EXTENSIONS_FLAG=1"
) else (
    call :CHECK_EXTENSIONS
    if errorlevel 1 (
        call :ADD_MISSING_DEV_TOOL "one or more VS Code extensions"
        set "INSTALL_REMOTE_SSH_FLAG=1"
        set "INSTALL_EXTENSIONS_FLAG=1"
    )
)
goto :EOF

:PREPARE_NETWORK
set "NETWORK_READY="
cls
echo %BLUE%=======================================================================%RESET%
echo %GREEN%                 NETWORK AND PROXY CHECK%RESET%
echo %BLUE%=======================================================================%RESET%
echo.
echo Please choose your working environment for all downloads:
echo 1) Bosch employee %BLUE%(RB Local Proxy Manager)%RESET%
echo 2) Partner with a company proxy
echo 3) Direct internet connection
echo.
set /p NET_CHOICE="%YELLOW%Choose an option (1, 2 or 3): %RESET%"
set "USE_PROXY=false"
if "%NET_CHOICE%"=="1" (
    set "USE_PROXY=true"
    set "PROXY_URL=http://127.0.0.1:3128"
    echo.
    echo %YELLOW%Please start the RB Local Proxy Manager and click Execute.%RESET%
    pause
    set "PROXY_READY=true"
    set "NETWORK_READY=true"
    exit /b 0
)
if "%NET_CHOICE%"=="2" (
    set "USE_PROXY=true"
    if not exist "proxy.env" (
        echo CUSTOMER_PROXY_URL=http://your-proxy-server.de:8080 > proxy.env
        echo %RED%[ERROR] Please configure proxy.env and restart the setup.%RESET%
        pause
        exit /b 1
    )
    for /f "delims=" %%A in (proxy.env) do set %%A
    call set "PROXY_URL=%%CUSTOMER_PROXY_URL%%"
    set "PROXY_READY=true"
    set "NETWORK_READY=true"
    exit /b 0
)
if "%NET_CHOICE%"=="3" (
    set "PROXY_READY=true"
    set "NETWORK_READY=true"
    exit /b 0
)
echo %RED%[ERROR] Invalid selection.%RESET%
pause
exit /b 1

:VERIFY_IMAGE_ARCHIVE
set "IMAGE_HASH="
for /f "tokens=*" %%H in ('certutil -hashfile "%IMAGE_FILE%" SHA256 ^| findstr /r /v /i /c:"hash" /c:"CertUtil"') do if not defined IMAGE_HASH set "IMAGE_HASH=%%H"
call set "IMAGE_HASH=%%IMAGE_HASH: =%%"
if /i "%IMAGE_HASH%"=="%IMAGE_SHA256%" exit /b 0
exit /b 1

:CHECK_RPI_IMAGER_LOCAL
set "IMAGER_EXE="
set "IMAGER_CLI="
if exist "%ProgramFiles(x86)%\Raspberry Pi Imager\rpi-imager.exe" set "IMAGER_EXE=%ProgramFiles(x86)%\Raspberry Pi Imager\rpi-imager.exe"
if not defined IMAGER_EXE if exist "%ProgramFiles%\Raspberry Pi Imager\rpi-imager.exe" set "IMAGER_EXE=%ProgramFiles%\Raspberry Pi Imager\rpi-imager.exe"
if not defined IMAGER_EXE exit /b 1
if not exist "%IMAGER_EXE%" exit /b 1
for %%F in ("%IMAGER_EXE%") do set "IMAGER_DIR=%%~dpF"
set "IMAGER_CLI=%IMAGER_DIR%rpi-imager-cli.cmd"
if not exist "%IMAGER_CLI%" exit /b 1
powershell.exe -NoProfile -Command "$item = Get-Item -LiteralPath '%IMAGER_EXE%'; if ($item.Length -lt 1MB) { exit 1 }"
if errorlevel 1 (
    set "IMAGER_EXE="
    set "IMAGER_CLI="
    exit /b 1
)
exit /b 0

:CHECK_VSCODE_PATH
set "CODE_EXE="
if exist "%USERPROFILE%\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd" set "CODE_EXE=%USERPROFILE%\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd"
if defined CODE_EXE goto :EOF
for /f "tokens=*" %%P in ('where code 2^>nul') do if not defined CODE_EXE set "CODE_EXE=%%P"
if defined CODE_EXE goto :EOF
for /d %%U in (C:\Users\*) do (
    if exist "%%U\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd" (
        set "CODE_EXE=%%U\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd"
        goto :EOF
    )
)
goto :EOF

:CHECK_REMOTE_SSH_EXTENSION
call "%CODE_EXE%" --list-extensions --show-versions 2>nul | findstr /i /r /b /c:"ms-vscode-remote\.remote-ssh$" /c:"ms-vscode-remote\.remote-ssh@" >nul
exit /b %errorlevel%

:CHECK_EXTENSIONS
set "EXTENSIONS_OK=Yes"
for %%e in (golang.go ms-dotnettools.csharp ms-python.python ms-vscode-remote.remote-ssh ms-vscode.cmake-tools ms-vscode.cpptools vscjava.vscode-java-pack twxs.cmake) do (
    "%CODE_EXE%" --list-extensions --show-versions 2>nul | findstr /i /r /b /c:"%%e$" /c:"%%e@" >nul
    if errorlevel 1 set "EXTENSIONS_OK=No"
)
if /i "%EXTENSIONS_OK%"=="Yes" exit /b 0
exit /b 1

:INSTALL_PI_EXTENSIONS
echo %BLUE%[Pi Extensions]%RESET% Waiting for the VS Code Server to initialize...
set /a PI_EXTENSION_WAIT_COUNT=0
:WAIT_FOR_PI_CODE_SERVER
set /a PI_EXTENSION_WAIT_COUNT+=1
ssh.exe -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 ctrlx-pi "find /home/%SSH_USER%/.vscode-server/bin -path '*/bin/code-server' -type f -perm -111 -print -quit | grep -q ." >nul 2>&1
if not errorlevel 1 goto :PI_CODE_SERVER_READY
if %PI_EXTENSION_WAIT_COUNT% GEQ 60 (
    echo %YELLOW%[Pi Extensions] VS Code Server not ready. Extensions were not installed.%RESET%
    exit /b 0
)
timeout /t 5 /nobreak >nul
goto :WAIT_FOR_PI_CODE_SERVER

:PI_CODE_SERVER_READY
echo %BLUE%[Pi Extensions]%RESET% Installing extensions in the Raspberry Pi...
ssh.exe -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 ctrlx-pi "set -e; code_server=$(find /home/%SSH_USER%/.vscode-server/bin -path '*/bin/code-server' -type f -perm -111 -print -quit); test -n $code_server; for extension in Angular.ng-template golang.go ms-dotnettools.csharp ms-python.python ms-vscode.cmake-tools ms-vscode.cpptools vscjava.vscode-java-pack twxs.cmake; do echo Installing $extension; $code_server --install-extension $extension --force; done; echo Installed Pi extensions:; $code_server --list-extensions"
if errorlevel 1 (
    echo %YELLOW%[Pi Extensions] Installation failed. Check the Remote-SSH output for details.%RESET%
    exit /b 0
)
echo %GREEN%[Pi Extensions] Remote extensions installed and verified.%RESET%
exit /b 0

:ADD_MISSING_DEV_TOOL
if defined MISSING_DEV_TOOLS (
    set "MISSING_DEV_TOOLS=%MISSING_DEV_TOOLS%, %~1"
) else (
    set "MISSING_DEV_TOOLS=%~1"
)
goto :EOF