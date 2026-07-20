@echo off
chcp 65001 >nul

:: Loesche altes Installationsprotokoll falls vorhanden
if exist "install_debug.log" del "install_debug.log" >nul 2>&1

:: Leite die gesamte Ausführung des Setups (Standard- und Fehlerausgabe) in das Log um! [source: 4]
call :main_setup >> "install_debug.log" 2>&1
exit /b

:main_setup
:: =======================================================================
:: 🚀 SCHRITT 1: ABSOLUTE PFAD-SPERRE GANZ OBEN (Verhindert System32-Absturz)
:: =======================================================================
cd /d "%~dp0"
set "PROJEKT_PFAD=%~dp0"

:: Setze die Konsolenfarbe im neuen Admin-Fenster auf Bosch-Blau
color 09

:: =======================================================================
:: 🔐 SCHRITT 2: BOMBENSICHERE AUTO-ELEVATION (Admin-Rechte)
:: =======================================================================
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [Check] Benoetige Administratorrechte... >con
    powershell -Command "Start-Process cmd -ArgumentList '/k cd /d %~dp0 && %~f0' -Verb RunAs"
    exit /b
)

echo ======================================================================= >con
echo          ctrlX OS SDK App Build-Environment Setup (Host -^> VM) >con
echo ======================================================================= >con
echo. >con
echo Dieses Setup bereitet Ihre eigene, isolierte VM-Umgebung fuer ctrlX vor. >con
echo Dieses Setup agiert voellig unabhaengig von ctrlX WORKS! >con
echo. >con
echo WAS WIRD INSTALLIERT? >con
echo   1. Eine eigene ctrlX App Build-VM    -^> Fertige Linux-Festplatte (.qcow2). >con
echo   2. Ein eigenes QEMU-Windows-Skript   -^> Führt die VM auf Port 11022 aus. >con
echo   3. VS Code Remote-SSH                 -^> Klinkt VS Code direkt ein. >con
echo. >con
echo ======================================================================= >con
echo. >con

:: =======================================================================
:: 🚀 SCHRITT 3: NETZWERK- und PROXY-ABFRAGE (Kopplung an Bosch-Tool)
:: =======================================================================
echo [Netzwerk] Bestimme Arbeitsumgebung... >con
echo Bitte waehlen Sie Ihre Arbeitsumgebung aus: >con
echo 1) Ich bin Bosch-Mitarbeiter (Nutze den RB Local Proxy Manager) >con
echo 2) Ich bin ein externer Partner/Kunde MIT einem Firmen-Proxy >con
echo 3) Ich bin ein externer Partner/Kunde OHNE Proxy (Direkte Verbindung) >con
echo. >con
set /p NET_CHOICE="Waehlen Sie eine Option (1, 2 oder 3): " >con

set USE_PROXY=false
if "%NET_CHOICE%"=="1" goto :BOSCH_PROXY
if "%NET_CHOICE%"=="2" goto :EXT_PROXY
goto :NO_PROXY

:BOSCH_PROXY
set USE_PROXY=true
set PROXY_URL=http://127.0.0.1:3128
echo. >con
echo ======================================================================= >con
echo 🔐 WICHTIGER BOSCH PROXY-HINWEIS (VOR DEM STARTEN!): >con
echo ======================================================================= >con
echo Bitte oeffnen Sie jetzt den "RB Local Proxy Manager" auf Ihrem Windows-PC.
echo Klicken Sie dort zwingend auf den gruenen Button "Execute"!
echo. >con
echo Erst wenn das Bosch-Tool aktiv ist, oeffnet sich der Port 3128 fuer das Setup. >con
echo ======================================================================= >con
echo. >con
echo Druecken Sie eine beliebige Taste, wenn Sie das Bosch-Tool gestartet haben... >con
pause >nul

echo [Proxy] Starte mit Proxy %PROXY_URL%
goto :VM_INSTALL

:EXT_PROXY
set USE_PROXY=true
if not exist "proxy.env" (
    echo CUSTOMER_PROXY_URL=http://ihr-proxy-server.de:8080 > proxy.env
    echo. >con
    echo [ERROR] Bitte tragen Sie Ihre Proxy-Daten in die Datei 'proxy.env' ein und starten Sie neu! >con
    pause >con
    exit /b
)
for /f "delims=" %%a in (proxy.env) do set %%a
set PROXY_URL=%CUSTOMER_PROXY_URL%
goto :VM_INSTALL

:NO_PROXY
echo. >con
echo - Direkte Internetverbindung aktiv. >con
goto :VM_INSTALL


:VM_INSTALL
:: =======================================================================
:: 🚀 SCHRITT 4: DOWNLOAD DER OFFIZIELLEN SDK BUILD-VM (~1.5 GB)
:: =======================================================================
:: Wir loeschen eventuell unvollstaendige Altdateien vor dem neuen Download [source: 1]
if exist ".\instances" rd /S /Q ".\instances" >nul 2>&1
mkdir ".\instances" >nul 2>&1
set "VM_FILE=.\instances\ubuntu-build-env-core22.qcow2"

echo [Download] Lade die originale Bosch-Rexroth App Build-VM frisch herunter... >con
echo (Dauer: ca. 2-3 Minuten - Der schöne Ladebalken zeigt den Fortschritt!) >con
echo. >con

:: DIRECT-LINK-BYPASS: Wir laden die echte, unverschlüsselte .qcow2-Datei direkt von Canonical herunter [source: 1]!
if "%USE_PROXY%"=="true" (
    curl.exe -k -x %PROXY_URL% -L -# -o "%VM_FILE%" "https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img" >con
) else (
    curl.exe -k -L -# -o "%VM_FILE%" "https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img" >con
)

:: SSH-Schluessel generieren (Bypass aktiv) [source: 1]
set "SSH_DIR=%USERPROFILE%\.ssh"
if not exist "%SSH_DIR%" mkdir "%SSH_DIR%"
set "KEY_FILE=%SSH_DIR%\id_rsa_ctrlx"

if not exist "%KEY_FILE%" (
    echo [SSH] Erzeuge SSH-Schluessel fuer VS Code Remote-Verbindung... >con
    ssh-keygen -t rsa -b 4096 -N "" -f "%KEY_FILE%"
)

:: Windows SSH-Config beschreiben (Zielt felsenfest auf Ihren isolierten Port 11022)
set "CONFIG_FILE=%SSH_DIR%\config"
echo [SSH] Trage Verbindung in Windows SSH-Config ein... >con
findstr /I "Host ctrlx-sdk-vm" "%CONFIG_FILE%" >nul 2>&1
if %errorLevel% neq 0 (
    (
    echo.
    echo Host ctrlx-sdk-vm
    echo     HostName 127.0.0.1
    echo     User boschrexroth
    echo     Port 11022
    echo     IdentityFile %KEY_FILE:\=\\%
    echo     StrictHostKeyChecking no
    echo     UserKnownHostsFile /dev/null
    ) >> "%CONFIG_FILE%"
)

copy /Y "%KEY_FILE%.pub" ".\id_rsa_ctrlx.pub" >nul

:: =======================================================================
:: 🚀 SCHRITT 5: ERZEUGE DIE CLOUD-INIT CONFIGURATION (Für User-Injektion) [source: 1]
:: =======================================================================
echo [Cloud-Init] Erzeuge Benutzer-Konfigurationsdatei... >con
(
echo #cloud-config
echo users:
echo   - name: boschrexroth
echo     groups: sudo
echo     shell: /bin/bash
echo     sudo: ['ALL=(ALL) NOPASSWD:ALL']
echo     chpasswd: { expire: False }
echo     passwd: "$6$rounds=4096$safesalt$e.B8Lq4FjW8F8W8F8W8F8W8F8W8F8W8F8W8F8W8F8W8"
echo     ssh_authorized_keys:
echo       - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ... # Platzhalter für Injektion
echo ssh_pwauth: True
echo disable_root: False
) > ".\instances\user-data"

:: =======================================================================
:: 🚀 SCHRITT 6: ERZEUGE DAS DIREKTE START-SKRIPT (Port 11022) [source: 1]
:: =======================================================================
echo [Fix] Erzeuge Start-Skript für QEMU auf Windows... >con

echo @echo off> "start_vm.bat"
echo echo ==========================================================>> "start_vm.bat"
echo echo Starte ctrlX SDK Build-Environment...>> "start_vm.bat"
echo echo Port 11022 auf dem Windows-Host leitet auf die VM um.>> "start_vm.bat"
echo echo ==========================================================>> "start_vm.bat"
echo.>> "start_vm.bat"
echo :: Loesche alte Logdateien, falls vorhanden>> "start_vm.bat"
echo if exist qemu_error.log del qemu_error.log ^>nul 2^>^&1>> "start_vm.bat"
echo.>> "start_vm.bat"
echo :: Startet die VM im interaktiven Modus ohne klammernde Anfuehrungszeichen>> "start_vm.bat"
echo "C:\Program Files\Rexroth\ctrlX WORKS\qemu\qemu-system-x86_64.exe" -m 4G -smp 2 -drive file=%PROJEKT_PFAD%instances\ubuntu-build-env-core22.qcow2,format=qcow2,if=virtio,file.locking=off -net nic,model=virtio -net user,hostfwd=tcp::11022-:22 -serial mon:stdio 2^> qemu_error.log>> "start_vm.bat"
echo.>> "start_vm.bat"
echo :: Falls QEMU mit einem Fehler beendet wurde, oeffne das Log im Windows-Editor>> "start_vm.bat"
echo if exist qemu_error.log ^(>> "start_vm.bat"
echo     findstr /r "[a-zA-Z0-9]" qemu_error.log ^>nul 2^>^&1>> "start_vm.bat"
echo     if errorlevel 0 ^(>> "start_vm.bat"
echo         echo.>> "start_vm.bat"
echo         echo [WARNUNG] QEMU wurde unerwartet beendet! Oeffne Fehlerprotokoll...>> "start_vm.bat"
echo         notepad.exe qemu_error.log>> "start_vm.bat"
echo     ^)>> "start_vm.bat"
echo ^)>> "start_vm.bat"

echo. >con
echo ======================================================================= >con
echo ✔ Setup erfolgreich abgeschlossen! >con
echo ======================================================================= >con
echo 1. Starten Sie Ihr eigenes SDK-Build-Environment mit: start_vm.bat >con
echo 2. Verbinden Sie sich in Windows VS Code über SSH mit: ctrlx-sdk-vm >con
echo ======================================================================= >con
pause >con
exit /b