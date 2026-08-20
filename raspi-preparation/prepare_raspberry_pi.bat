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
set "ETCHER_URL=https://github.com/balena-io/etcher/releases/download/v%ETCHER_VERSION%/balenaEtcher-win32-x64-%ETCHER_VERSION%.zip"
set "ETCHER_FILE=%PROJECT_PATH%balenaEtcher-%ETCHER_VERSION%-win32-x64.zip"
set "ETCHER_DIR=%PROJECT_PATH%balenaEtcher-portable"
set "ETCHER_EXE="
set "ETCHER_SHA256=ad0a568f45fcb981173084b4183b684acd6f9dfafbf66b5b04f37627e02c6f91"
set "PI_USERNAME=sdk_pi"
set "PI_PASSWORD=sdk_pi"
set "PI_HOSTNAME=sdk_pi"
set "SSH_DIR=%USERPROFILE%\.ssh"
set "SSH_KEY_FILE=%SSH_DIR%\id_rsa_ctrlx_pi"

:: =======================================================================
:: Check and install VS Code dependencies
:: =======================================================================

if "%~1"=="-install-dependencies" goto :INSTALL_DEPENDENCIES

set "MISSING_DEV_TOOLS="
set "INSTALL_VSCODE_FLAG="
set "INSTALL_REMOTE_SSH_FLAG="
call :CHECK_DEVELOPMENT_TOOLS

if defined MISSING_DEV_TOOLS goto :REQUEST_ADMIN
goto :MAIN_MENU

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
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%INSTALL_ARGS%' -Verb RunAs"
exit

:INSTALL_DEPENDENCIES
cls
echo %BLUE%=======================================================================%RESET%
echo %GREEN%             INSTALLING REQUIRED DEVELOPMENT TOOLS%RESET%
echo %BLUE%=======================================================================%RESET%
echo.

set "ARG_STRING=%*"

echo %ARG_STRING% | findstr /i /c:"-install-vscode" >nul
if not errorlevel 1 (
    echo %YELLOW%[VS Code] Visual Studio Code is missing.%RESET%
    echo %YELLOW%[VS Code] Downloading the official installer...%RESET%
    curl.exe --fail --retry 3 --retry-all-errors -L -# -o "%PROJECT_PATH%vscode_setup.exe" "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user"
    if not exist "%PROJECT_PATH%vscode_setup.exe" (
        echo %RED%[ERROR] VS Code download failed.%RESET%
        pause
        exit /b 1
    )
    echo %YELLOW%[VS Code] Installing Visual Studio Code for the current user...%RESET%
    start /wait "" "%PROJECT_PATH%vscode_setup.exe" /VERYSILENT /NORESTART
    del "%PROJECT_PATH%vscode_setup.exe" >nul 2>&1
    call :CHECK_VSCODE_PATH
    if not defined CODE_EXE (
        echo %RED%[ERROR] VS Code could not be found after installation.%RESET%
        pause
        exit /b 1
    )
    echo %GREEN%[VS Code] Installation completed successfully.%RESET%
)

echo %ARG_STRING% | findstr /i /c:"-install-remote-ssh" >nul
if not errorlevel 1 (
    call :CHECK_VSCODE_PATH
    if not defined CODE_EXE (
        echo %RED%[ERROR] The VS Code command-line tool is unavailable.%RESET%
        pause
        exit /b 1
    )
    echo %YELLOW%[Remote-SSH] Installing the Microsoft Remote-SSH extension...%RESET%
    call "%CODE_EXE%" --install-extension ms-vscode-remote.remote-ssh --force
    if errorlevel 1 (
        echo %RED%[ERROR] Remote-SSH extension installation failed.%RESET%
        pause
        exit /b 1
    )
    echo %GREEN%[Remote-SSH] Extension installation completed successfully.%RESET%
)

echo.
echo %GREEN%All required development tools are ready.%RESET%
echo %YELLOW%The Raspberry Pi preparation menu will now start.%RESET%
timeout /t 2 /nobreak >nul
goto :MAIN_MENU

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
    set "IMAGE_FLASH_FILE=%PROJECT_PATH%ubuntu-22.04.5-preinstalled-server-arm64+raspi.img"
    goto :NET_PROXY_CHECK
)

if "%OS_CHOICE%"=="2" (
    set "UBUNTU_VERSION=24.04.3"
    set "CTRLX_TARGET=ctrlX OS 4.x"
    set "IMAGE_URL=https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz"
    set "IMAGE_FILE=%PROJECT_PATH%ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz"
    set "IMAGE_FLASH_FILE=%PROJECT_PATH%ubuntu-24.04.3-preinstalled-server-arm64+raspi.img"
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

:: Verify the archive and extract the uncompressed image for balenaEtcher
if not exist "C:\Program Files\7-Zip\7z.exe" if not exist "%ProgramFiles%\7-Zip\7z.exe" (
    echo %RED%[ERROR] 7-Zip is required to prepare the image for balenaEtcher.%RESET%
    echo Please install 7-Zip and run this script again.
    pause
    goto :MAIN_MENU
)

set "SEVEN_ZIP_EXE=%ProgramFiles%\7-Zip\7z.exe"
if not exist "%SEVEN_ZIP_EXE%" set "SEVEN_ZIP_EXE=C:\Program Files\7-Zip\7z.exe"

if exist "%IMAGE_FLASH_FILE%" (
    echo %GREEN%[Ubuntu] Uncompressed image already exists. Skipping extraction.%RESET%
) else (
    echo %YELLOW%[Ubuntu] Verifying and extracting the image for balenaEtcher...%RESET%
    "%SEVEN_ZIP_EXE%" t "%IMAGE_FILE%" >nul
    if errorlevel 1 (
        echo %RED%[ERROR] The downloaded Ubuntu archive is corrupt.%RESET%
        pause
        goto :MAIN_MENU
    )
    "%SEVEN_ZIP_EXE%" e -y -o"%PROJECT_PATH%" "%IMAGE_FILE%" >nul
    if not exist "%IMAGE_FLASH_FILE%" (
        echo %RED%[ERROR] Could not extract the Ubuntu image.%RESET%
        pause
        goto :MAIN_MENU
    )
)

:: Check for an existing local portable installation first
for /r "%ETCHER_DIR%" %%F in (balenaEtcher.exe) do if not defined ETCHER_EXE set "ETCHER_EXE=%%~fF"
if defined ETCHER_EXE if exist "%ETCHER_EXE%" (
    powershell.exe -NoProfile -Command "$item = Get-Item -LiteralPath '%ETCHER_EXE%'; if ($item.Length -lt 1MB -or $item.VersionInfo.ProductVersion -notlike '%ETCHER_VERSION%*') { exit 1 }"
    if errorlevel 1 set "ETCHER_EXE="
)

if defined ETCHER_EXE (
    echo %GREEN%[balenaEtcher] Valid local portable installation found.%RESET%
) else (
    if exist "%ETCHER_FILE%" (
        echo %YELLOW%[balenaEtcher] Existing portable archive found. Verifying checksum...%RESET%
    ) else (
        echo %YELLOW%[balenaEtcher] Downloading portable balenaEtcher from GitHub...%RESET%
        if "%USE_PROXY%"=="true" (
            curl.exe --fail --retry 3 --retry-all-errors -x "%PROXY_URL%" -L -# -o "%ETCHER_FILE%" "%ETCHER_URL%"
        ) else (
            curl.exe --fail --retry 3 --retry-all-errors -L -# -o "%ETCHER_FILE%" "%ETCHER_URL%"
        )
    )
    if not exist "%ETCHER_FILE%" (
        echo %RED%[ERROR] balenaEtcher portable archive download failed.%RESET%
        pause
        goto :MAIN_MENU
    )

    powershell.exe -NoProfile -Command "$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath '%ETCHER_FILE%').Hash; if ($hash -ne '%ETCHER_SHA256%') { exit 1 }"
    if errorlevel 1 (
        echo %RED%[ERROR] The balenaEtcher ZIP checksum is invalid.%RESET%
        del "%ETCHER_FILE%" >nul 2>&1
        pause
        goto :MAIN_MENU
    )

    if exist "%ETCHER_DIR%" rmdir /s /q "%ETCHER_DIR%" >nul 2>&1
    mkdir "%ETCHER_DIR%" >nul 2>&1
    echo %YELLOW%[balenaEtcher] Extracting the portable installation...%RESET%
    "%SEVEN_ZIP_EXE%" x -y -o"%ETCHER_DIR%" "%ETCHER_FILE%" >nul
    for /r "%ETCHER_DIR%" %%F in (balenaEtcher.exe) do if not defined ETCHER_EXE set "ETCHER_EXE=%%~fF"
    if not defined ETCHER_EXE (
        echo %RED%[ERROR] balenaEtcher.exe was not found after extraction.%RESET%
        pause
        goto :MAIN_MENU
    )
)

if not exist "%ETCHER_EXE%" (
    echo %RED%[ERROR] No usable local balenaEtcher installation was found.%RESET%
    pause
    goto :MAIN_MENU
)

echo %GREEN%[balenaEtcher] Local executable: %ETCHER_EXE%%RESET%

:: Start the portable application without an installer or administrator rights
start "balenaEtcher" "%ETCHER_EXE%"

:: Continue with the flash instructions
goto :FLASH_INSTRUCTIONS

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
echo    %IMAGE_FLASH_FILE%
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

:CHECK_DEVELOPMENT_TOOLS
set "CODE_EXE="
call :CHECK_VSCODE_PATH
if not defined CODE_EXE (
    call :ADD_MISSING_DEV_TOOL "Visual Studio Code"
    set "INSTALL_VSCODE_FLAG=1"
    set "INSTALL_REMOTE_SSH_FLAG=1"
) else (
    call :CHECK_REMOTE_SSH_EXTENSION
    if errorlevel 1 (
        call :ADD_MISSING_DEV_TOOL "VS Code Remote-SSH extension"
        set "INSTALL_REMOTE_SSH_FLAG=1"
    )
)
goto :EOF

:CHECK_VSCODE_PATH
set "CODE_EXE="
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
call "%CODE_EXE%" --list-extensions 2>nul | findstr /i /r /b /c:"ms-vscode.remote.remote-ssh$" /c:"ms-vscode.remote.remote-ssh@" >nul
exit /b %errorlevel%

:ADD_MISSING_DEV_TOOL
if defined MISSING_DEV_TOOLS (
    set "MISSING_DEV_TOOLS=%MISSING_DEV_TOOLS%, %~1"
) else (
    set "MISSING_DEV_TOOLS=%~1"
)
goto :EOF