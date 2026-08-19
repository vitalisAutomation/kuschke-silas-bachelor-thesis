:: Source information
:: Source: Gemini 3.6
:: Edited by Silas Kuschke

@echo off

chcp 65001 >nul

:: Generate the ESC character for reliable ANSI color output

for /f "tokens=1,2 delims=#" %%a in ('"prompt #$H#$E# & echo on & for %%b in (1) do rem"') do set "ESC=%%b"

:: Define ANSI color codes

set "BLUE=%ESC%[94m"
set "GREEN=%ESC%[92m"
set "YELLOW=%ESC%[93m"
set "RED=%ESC%[91m"
set "RESET=%ESC%[0m"

cd /d "%~dp0"
set "PROJECT_PATH=%~dp0"
set "ETCHER_VERSION=2.1.4"
set "ETCHER_URL=https://github.com/balena-io/etcher/releases/download/v%ETCHER_VERSION%/balenaEtcher-%ETCHER_VERSION%.Setup.exe"
set "ETCHER_FILE=%PROJECT_PATH%balenaEtcher-setup.exe"
set "PI_USERNAME=sdk_pi"
set "PI_PASSWORD=sdk_pi"
set "PI_HOSTNAME=sdk_pi"
set "SSH_DIR=%USERPROFILE%\.ssh"
set "SSH_KEY_FILE=%SSH_DIR%\id_rsa_ctrlx_pi"

:: =======================================================================
:: Main menu
:: =======================================================================

:MAIN_MENU

cls

echo %BLUE%=======================================================================%RESET%
echo %GREEN%                 RASPBERRY PI SD CARD PREPARATION%RESET%
echo %BLUE%=======================================================================%RESET%
echo(
echo This setup downloads an Ubuntu Server image for Raspberry Pi and
echo opens balenaEtcher to flash the selected image to an SD card.
echo.
echo Please make sure that the SD card is connected before starting balenaEtcher.
echo The selected drive will be erased completely.
echo(
echo %BLUE%Please choose the target software version:%RESET%
echo.
echo 1) ctrlX OS 1.x / 2.x / 3.x - Ubuntu Server 22.04 LTS (ARM64)
echo 2) ctrlX OS 4.x             - Ubuntu Server 24.04 LTS (ARM64)
echo 3) Exit
echo(

set /p OS_CHOICE="%YELLOW%Choose an option (1, 2 or 3): %RESET%"

if "%OS_CHOICE%"=="1" (
    set "UBUNTU_VERSION=22.04.5"
    set "CTRLX_TARGET=ctrlX OS 1.x / 2.x / 3.x"
    set "IMAGE_URL=https://cdimage.ubuntu.com/releases/22.04/release/ubuntu-22.04.5-preinstalled-server-arm64+raspi.img.xz"
    set "IMAGE_FILE=%PROJECT_PATH%ubuntu-22.04.5-preinstalled-server-arm64+raspi.img.xz"
    goto :NET_PROXY_CHECK
)

if "%OS_CHOICE%"=="2" (
    set "UBUNTU_VERSION=24.04.3"
    set "CTRLX_TARGET=ctrlX OS 4.x"
    set "IMAGE_URL=https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz"
    set "IMAGE_FILE=%PROJECT_PATH%ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz"
    goto :NET_PROXY_CHECK
)

if "%OS_CHOICE%"=="3" exit

goto :MAIN_MENU

:: =======================================================================
:: Check the proxy configuration before downloading files
:: =======================================================================

:NET_PROXY_CHECK

cls

echo %BLUE%=======================================================================%RESET%
echo %GREEN%                 NETWORK AND PROXY CHECK%RESET%
echo %BLUE%=======================================================================%RESET%
echo(
echo [Network] %YELLOW%Determining environment...%RESET%
echo Please choose your working environment:
echo 1) I am a Bosch employee %BLUE%(RB Local Proxy Manager)%RESET%
echo 2) I am a partner WITH a %BLUE%company proxy%RESET%
echo 3) I am a partner %BLUE%WITHOUT a proxy (direct connection)%RESET%
echo(

set /p NET_CHOICE="%YELLOW%Choose an option (1, 2 or 3): %RESET%"

set "USE_PROXY=false"
if "%NET_CHOICE%"=="1" goto :BOSCH_PROXY
if "%NET_CHOICE%"=="2" goto :EXT_PROXY
if "%NET_CHOICE%"=="3" goto :NO_PROXY
goto :NET_PROXY_CHECK

:BOSCH_PROXY

set "USE_PROXY=true"
set "PROXY_URL=http://127.0.0.1:3128"

echo.
echo %BLUE%=======================================================================%RESET%
echo %RED%IMPORTANT BOSCH PROXY NOTICE BEFORE STARTING:%RESET%
echo %BLUE%=======================================================================%RESET%
echo Please open the %GREEN%"RB Local Proxy Manager"%RESET% on your PC.
echo You must click the green %GREEN%"Execute"%RESET% button there.
echo The port 3128 will only open for the setup once the Bosch tool is active.
echo %BLUE%=======================================================================%RESET%
echo.
echo %YELLOW%Press Enter when you have started the Bosch tool...%RESET%
pause >nul
goto :DOWNLOAD_FILES

:EXT_PROXY

set "USE_PROXY=true"
if not exist "proxy.env" (
    echo CUSTOMER_PROXY_URL=http://your-proxy-server.de:8080 > proxy.env
    echo.
    echo %RED%[ERROR] Please add your proxy data to the 'proxy.env' file and restart the setup!%RESET%
    pause
    goto :MAIN_MENU
)

for /f "delims=" %%a in (proxy.env) do set %%a
set "PROXY_URL=%CUSTOMER_PROXY_URL%"
goto :DOWNLOAD_FILES

:NO_PROXY

echo.
echo - %GREEN%Direct internet connection%RESET% active.
goto :DOWNLOAD_FILES

:: =======================================================================
:: Download the Ubuntu image and balenaEtcher
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

:: Generate the SSH key that will be installed on the Raspberry Pi
if not exist "%SSH_DIR%" mkdir "%SSH_DIR%" >nul 2>&1
if not exist "%SSH_KEY_FILE%" (
    echo %YELLOW%[SSH] Generating an RSA key for Raspberry Pi access...%RESET%
    ssh-keygen.exe -t rsa -b 4096 -N "" -f "%SSH_KEY_FILE%"
) else (
    echo %GREEN%[SSH] Existing Raspberry Pi key will be reused.%RESET%
)

:: Recreate a missing public key from the existing private key
if exist "%SSH_KEY_FILE%" if not exist "%SSH_KEY_FILE%.pub" (
    ssh-keygen.exe -y -f "%SSH_KEY_FILE%" > "%SSH_KEY_FILE%.pub"
)

if not exist "%SSH_KEY_FILE%" goto :SSH_KEY_ERROR
if not exist "%SSH_KEY_FILE%.pub" goto :SSH_KEY_ERROR

goto :CREDENTIALS_READY

:SSH_KEY_ERROR

echo %RED%[ERROR] The SSH key pair is incomplete or invalid.%RESET%
pause
goto :MAIN_MENU

:CREDENTIALS_READY

:: Collect the Wi-Fi credentials for the first boot
if not defined WIFI_SSID (
    echo.
    echo %BLUE%[Wi-Fi] Enter the wireless network for the Raspberry Pi.%RESET%
    set /p WIFI_SSID="%YELLOW%Wi-Fi SSID: %RESET%"
    echo %YELLOW%Wi-Fi password input is hidden.%RESET%
    for /f "delims=" %%a in ('powershell.exe -NoProfile -Command "$p=Read-Host -AsSecureString; $b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($p); try {[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)} finally {[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}"') do set "WIFI_PASSWORD=%%a"
    if not defined WIFI_SSID (
        echo %RED%[ERROR] The Wi-Fi SSID must not be empty.%RESET%
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

if exist "%IMAGE_FILE%" (
    echo %GREEN%[Ubuntu] Image already exists. Skipping download.%RESET%
) else (
    echo %YELLOW%[Ubuntu] Downloading the official Ubuntu image...%RESET%
    if "%USE_PROXY%"=="true" (
        curl.exe -x "%PROXY_URL%" -L -# -o "%IMAGE_FILE%" "%IMAGE_URL%"
    ) else (
        curl.exe -L -# -o "%IMAGE_FILE%" "%IMAGE_URL%"
    )
    if not exist "%IMAGE_FILE%" (
        echo %RED%[ERROR] Ubuntu image download failed. Please check the network and proxy settings.%RESET%
        pause
        goto :MAIN_MENU
    )
)

if exist "%ETCHER_FILE%" (
    echo %GREEN%[balenaEtcher] Installer already exists. Skipping download.%RESET%
) else (
    echo %YELLOW%[balenaEtcher] Downloading balenaEtcher from GitHub...%RESET%
    if "%USE_PROXY%"=="true" (
        curl.exe -x "%PROXY_URL%" -L -# -o "%ETCHER_FILE%" "%ETCHER_URL%"
    ) else (
        curl.exe -L -# -o "%ETCHER_FILE%" "%ETCHER_URL%"
    )
    if not exist "%ETCHER_FILE%" (
        echo %RED%[ERROR] balenaEtcher download failed. Please check the network and proxy settings.%RESET%
        pause
        goto :MAIN_MENU
    )
)

echo.
echo %GREEN%All required files are ready.%RESET%
echo.
echo %YELLOW%The balenaEtcher installer will now start.%RESET%
echo Install balenaEtcher for the current user if prompted.
echo.
pause
start /wait "" "%ETCHER_FILE%"

set "ETCHER_EXE=%LOCALAPPDATA%\Programs\balenaEtcher\balenaEtcher.exe"
if not exist "%ETCHER_EXE%" set "ETCHER_EXE=%LOCALAPPDATA%\balenaEtcher\balenaEtcher.exe"

if exist "%ETCHER_EXE%" (
    echo %GREEN%balenaEtcher was installed successfully and will now start.%RESET%
    start "balenaEtcher" "%ETCHER_EXE%"
) else (
    echo %YELLOW%Please start balenaEtcher manually after the installation has finished.%RESET%
)

:: =======================================================================
:: Flash instructions
:: =======================================================================

:FLASH_INSTRUCTIONS

cls

echo %BLUE%=======================================================================%RESET%
echo %GREEN%                       FLASH THE SD CARD%RESET%
echo %BLUE%=======================================================================%RESET%
echo(
echo In balenaEtcher, complete these steps:
echo.
echo 1) Select the image file:
echo    %IMAGE_FILE%
echo 2) Select the SD card that will be used in the Raspberry Pi.
echo 3) Click "Flash" and confirm that the selected drive may be erased.
echo 4) Wait until the verification has completed successfully.
echo 5) Leave the SD card connected and close balenaEtcher.
echo.
echo %RED%WARNING: Selecting the wrong drive will permanently erase its data.%RESET%
echo.
echo %GREEN%After the successful flash, press any key to configure the first boot.%RESET%
echo(
pause
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

set /p BOOT_DRIVE="%YELLOW%Boot partition drive letter: %RESET%"
set "BOOT_PATH=%BOOT_DRIVE%\"

if not exist "%BOOT_PATH%" (
    echo %RED%[ERROR] The selected drive does not exist.%RESET%
    pause
    goto :CONFIGURE_FIRST_BOOT
)

echo.
echo %YELLOW%Writing Cloud-Init configuration to %BOOT_PATH%...%RESET%

:: PowerShell writes UTF-8 YAML and escapes arbitrary Wi-Fi credentials safely
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_PATH%configure_cloud_init.ps1"
if errorlevel 1 goto :CONFIGURATION_ERROR
if not exist "%BOOT_PATH%user-data" goto :CONFIGURATION_ERROR
if not exist "%BOOT_PATH%network-config" goto :CONFIGURATION_ERROR
goto :CONFIGURATION_READY

:CONFIGURATION_ERROR

echo %RED%[ERROR] Could not write all Cloud-Init files to the selected boot partition.%RESET%
pause
goto :MAIN_MENU

:CONFIGURATION_READY

echo.
echo %GREEN%Cloud-Init configuration completed successfully.%RESET%
echo.
echo SSH username: %PI_USERNAME%
echo Hostname: %PI_HOSTNAME%
echo Wi-Fi SSID: %WIFI_SSID%
echo SSH private key: %SSH_KEY_FILE%
echo.
echo Safely eject the SD card, insert it into the Raspberry Pi, and power it on.
echo The SDK and Snapcraft installation will run automatically on first boot.
echo The first boot may take several minutes.
echo.
pause
exit