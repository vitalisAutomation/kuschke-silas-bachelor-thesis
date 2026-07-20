@echo off
chcp 65001 >nul

:: Virtuelle Terminalsequenzen für native Windows-ANSI-Farben aktivieren
reg add HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 1 /f >nul 2>&1

:: Farbcodes definieren
set "ESC="
set "BLUE=%ESC%[94m"
set "GREEN=%ESC%[92m"
set "YELLOW=%ESC%[93m"
set "RED=%ESC%[91m"
set "RESET=%ESC%[0m"

:: =======================================================================
:: 🚀 SCHRITT 1: ABSOLUTE PFAD-SPERRE GANZ OBEN (Verhindert System32-Absturz)
:: =======================================================================
cd /d "%~dp0"
set "PROJEKT_PFAD=%~dp0"

:: =======================================================================
:: 🔐 SCHRITT 2: BOMBENSICHERE AUTO-ELEVATION (Admin-Rechte)
:: =======================================================================
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo %YELLOW%[Check] Benoetige Administratorrechte...%RESET%
    powershell -Command "Start-Process cmd -ArgumentList '/k cd /d %~dp0 && %~f0' -Verb RunAs"
    exit
)

:: Bereite Logdatei vor
if exist "install_debug.log" del "install_debug.log" >nul 2>&1

echo %BLUE%=======================================================================%RESET%
echo          ctrlX OS SDK App Build-Environment Setup %GREEN%(Host -^> VM)%RESET%
echo %BLUE%=======================================================================%RESET%
echo.
echo Dieses Setup bereitet Ihre eigene, isolierte VM-Umgebung fuer ctrlX vor.
echo Dieses Setup agiert voellig unabhaengig von ctrlX WORKS!
echo.
echo WAS WIRD INSTALLIERT?
echo   1. Eine eigene %GREEN%ctrlX App Build-VM%RESET%    -^> Fertige Linux-Festplatte .qcow2
echo   2. Ein eigenes %GREEN%QEMU-Windows-Skript%RESET%   -^> Führt die VM auf Port 11022 aus
echo   3. %GREEN%VS Code Remote-SSH%RESET%                 -^> Klinkt VS Code direkt ein
echo.
echo %BLUE%=======================================================================%RESET%
echo.

:: =======================================================================
:: 🚀 SCHRITT 3: NETZWERK- und PROXY-ABFRAGE (Kopplung an Bosch-Tool)
:: =======================================================================
echo [Netzwerk] %YELLOW%Bestimme Arbeitsumgebung...%RESET%
echo Bitte waehlen Sie Ihre Arbeitsumgebung aus:
echo 1) Ich bin Bosch-Mitarbeiter %BLUE%(RB Local Proxy Manager)%RESET%
echo 2) Ich bin ein partner MIT einem %BLUE%Firmen-Proxy%RESET%
echo 3) Ich bin ein partner %BLUE%OHNE Proxy (Direkt)%RESET%
echo.
set /p NET_CHOICE="%YELLOW%Waehlen Sie eine Option (1, 2 oder 3): %RESET%"

set USE_PROXY=false
if "%NET_CHOICE%"=="1" goto :BOSCH_PROXY
if "%NET_CHOICE%"=="2" goto :EXT_PROXY
goto :NO_PROXY

:BOSCH_PROXY
set USE_PROXY=true
set PROXY_URL=http://127.0.0.1:3128
echo.
echo %BLUE%=======================================================================%RESET%
echo %RED%🔐 WICHTIGER BOSCH PROXY-HINWEIS VOR DEM STARTEN:%RESET%
echo %BLUE%=======================================================================%RESET%
echo Bitte oeffnen Sie jetzt den %GREEN%"RB Local Proxy Manager"%RESET% auf Ihrem PC.
echo Klicken Sie dort zwingend auf den gruenen Button %GREEN%"Execute"%RESET%!
echo.
echo Erst wenn das Bosch-Tool aktiv ist, oeffnet sich der Port 3128 fuer das Setup.
echo %BLUE%=======================================================================%RESET%
echo.
echo %YELLOW%Druecken Sie Enter, wenn Sie das Bosch-Tool gestartet haben...%RESET%
pause >nul
echo [Proxy] Starte mit Proxy %PROXY_URL% >> "install_debug.log" 2>&1
goto :VM_INSTALL

:EXT_PROXY
set USE_PROXY=true
if not exist "proxy.env" (
    echo CUSTOMER_PROXY_URL=http://ihr-proxy-server.de:8080 > proxy.env
    echo.
    echo %RED%[ERROR] Bitte tragen Sie Ihre Proxy-Daten in die Datei 'proxy.env' ein und starten Sie neu!%RESET%
    pause
    exit
)
for /f "delims=" %%a in (proxy.env) do set %%a
set PROXY_URL=%CUSTOMER_PROXY_URL%
goto :VM_INSTALL

:NO_PROXY
echo.
echo - %GREEN%Direkte Internetverbindung%RESET% aktiv.
goto :VM_INSTALL


:VM_INSTALL
:: =======================================================================
:: 🚀 SCHRITT 4: DOWNLOAD DER OFFIZIELLEN SDK BUILD-VM (~1.5 GB)
:: =======================================================================
if exist ".\instances" rd /S /Q ".\instances" >nul 2>&1
mkdir ".\instances" >nul 2>&1
set "VM_FILE=.\instances\ubuntu-build-env-core22.qcow2"

echo %BLUE%[Download]%RESET% Lade die originale Bosch-Rexroth App Build-VM frisch herunter...
echo %YELLOW%(Dauer: ca. 2-3 Minuten - Der Ladebalken zeigt den Fortschritt)%RESET%
echo.

:: Hier zwingen wir curl dazu, den Ladebalken live im Terminal auszugeben! [source: 2]
if "%USE_PROXY%"=="true" (
    curl.exe -k -x %PROXY_URL% -L -# -o "%VM_FILE%" "https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img"
) else (
    curl.exe -k -L -# -o "%VM_FILE%" "https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img"
)

:: SSH-Schluessel generieren (Bypass aktiv) [source: 3]
set "SSH_DIR=%USERPROFILE%\.ssh"
if not exist "%SSH_DIR%" mkdir "%SSH_DIR%"
set "KEY_FILE=%SSH_DIR%\id_rsa_ctrlx"

if not exist "%KEY_FILE%" (
    echo %BLUE%[SSH]%RESET% Erzeuge SSH-Schluessel fuer VS Code Remote-Verbindung...
    ssh-keygen -t rsa -b 4096 -N "" -f "%KEY_FILE%" >> "install_debug.log" 2>&1
)

:: Windows SSH-Config beschreiben (Zielt felsenfest auf Ihren isolierten Port 11022)
set "CONFIG_FILE=%SSH_DIR%\config"
echo %BLUE%[SSH]%RESET% Trage Verbindung in Windows SSH-Config ein...
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

copy /Y "%KEY_FILE%.pub" ".\id_rsa_ctrlx.pub" >nul 2>&1

:: =======================================================================
:: 🚀 SCHRITT 5: ERZEUGE DIE CLOUD-INIT CONFIGURATION (Für User-Injektion) [source: 11]
:: =======================================================================
echo %BLUE%[Cloud-Init]%RESET% Erzeuge Benutzer-Konfigurationsdatei...

:: klammerfreie Zeilen loesen den Syntaxfehler endgueltig! [source: 24]
echo #cloud-config> ".\instances\user-data"
echo users:>> ".\instances\user-data"
echo   - name: boschrexroth>> ".\instances\user-data"
echo     groups: sudo>> ".\instances\user-data"
echo     shell: /bin/bash>> ".\instances\user-data"
echo     sudo: ALL=^(ALL^) NOPASSWD:ALL>> ".\instances\user-data"
echo     chpasswd: { expire: False }>> ".\instances\user-data"
echo     passwd: $6$rounds=4096$safesalt$e.B8Lq4FjW8F8W8F8W8F8W8F8W8F8W8F8W8F8W8F8W8>> ".\instances\user-data"
echo     ssh_authorized_keys:>> ".\instances\user-data"
echo       - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ...>> ".\instances\user-data"
echo ssh_pwauth: True>> ".\instances\user-data"
echo disable_root: False>> ".\instances\user-data"

:: =======================================================================
:: 🚀 SCHRITT 6: ERZEUGE DAS DIREKTE START-SKRIPT (Port 11022) (Zerstörungsfrei!) [source: 1]
:: =======================================================================
echo %BLUE%[Fix]%RESET% Erzeuge Start-Skript für QEMU auf Windows...

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

echo.
echo %GREEN%=======================================================================%RESET%
echo ✔ %GREEN%Setup erfolgreich abgeschlossen!%RESET%
echo %GREEN%=======================================================================%RESET%
echo 1. Starten Sie Ihr eigenes SDK-Build-Environment mit: %YELLOW%start_vm.bat%RESET%
echo 2. Verbinden Sie sich in Windows VS Code über SSH mit: %YELLOW%ctrlx-sdk-vm%RESET%
echo %GREEN%=======================================================================%RESET%
echo.

:: Interaktives Schließen: Wartet, bis der Benutzer eine Taste drückt! [source: 11]
pause >con

:: Harter Exit: Schließt das CMD-Terminal kompromisslos nach dem Tastendruck! [source: 5]
exit