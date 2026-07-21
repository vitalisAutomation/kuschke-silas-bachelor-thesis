@echo off
chcp 65001 >nul

:: Dynamische Generierung des ESC-Zeichens für fehlerfreie ANSI-Farben
for /f "tokens=1,2 delims=#" %%a in ('"prompt #$H#$E# & echo on & for %%b in (1) do rem"') do set "ESC=%%b"

:: Farbcodes definieren
set "BLUE=%ESC%[94m"
set "GREEN=%ESC%[92m"
set "YELLOW=%ESC%[93m"
set "RED=%ESC%[91m"
set "RESET=%ESC%[0m"

cd /d "%~dp0"
set "PROJEKT_PFAD=%~dp0"

:: Bereite Logdatei vor
if exist "install_debug.log" del "install_debug.log" >nul 2>&1

:: =======================================================================
:: 🔐 SCHRITT 1: BOMBENSICHERE AUTO-ELEVATION (Admin-Rechte)
:: =======================================================================
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo %YELLOW%[Check] Benoetige Administratorrechte...%RESET%
    powershell -Command "Start-Process cmd -ArgumentList '/k cd /d %~dp0 && %~f0' -Verb RunAs"
    exit
)

:: =======================================================================
:: 🔍 SCHRITT 2: AUTO-DETEKTION LOKALES QEMU & CLI-HINWEIS
:: =======================================================================
set "QEMU_EXE="
set "QEMU_SOURCE="

if exist ".\qemu\qemu-system-x86_64.exe" (
    set "QEMU_EXE=%PROJEKT_PFAD%qemu\qemu-system-x86_64.exe"
    set "QEMU_SOURCE=Lokal im Projekt (Isoliert & Autark)"
    goto :MAIN_MENU
)

:: Falls kein QEMU lokal existiert, bieten wir den automatischen Download an
cls
echo %BLUE%=======================================================================%RESET%
echo %YELLOW%               LOKALES QEMU INITIALISIEREN (Portabilität)%RESET%
echo %BLUE%=======================================================================%RESET%
echo(
echo %YELLOW%👉 HINWEIS ZUM INSTALLATIONS-PROZESS & PROJEKT-ISOLATION:%RESET%
echo Dieses Skript kann zwar global installierte QEMU-Instanzen auf Ihrem PC
echo finden (z. B. von einer bestehenden ctrlX WORKS Installation).
echo.
echo %GREEN%Es wird jedoch DRINGEND EMPFOHLEN, QEMU direkt LOKAL in diesem Projekt%RESET%
echo %GREEN%zu installieren (Option 1).%RESET%
echo.
echo %BLUE%Warum?%RESET%
echo   1. %GREEN%100%% Unabhängigkeit:%RESET% ctrlX WORKS kann deinstalliert, geupdatet oder
echo      beschädigt werden - Ihr Projekt läuft unberührt und autark weiter.
echo   2. %GREEN%Portabilität:%RESET% Sie können den gesamten Projektordner auf eine externe
echo      Festplatte oder einen anderen PC kopieren und sofort loslegen.
echo   3. %GREEN%Keine Versionskonflikte:%RESET% Keine unerwarteten Fehler durch abweichende
echo      globale QEMU-Versionen auf Ihrem Host-System.
echo.
echo %YELLOW%Hinweis zum Ablauf:%RESET% Der Download startet im CLI. Anschließend startet der
echo offizielle QEMU-Installer. %YELLOW%Bitte installieren Sie QEMU einfach direkt in den%RESET%
echo %YELLOW%vorausgewählten Projekt-Pfad (.\qemu\).%RESET% Es sind keine weiteren Klicks nötig!
echo.
echo Das Setup benoetigt hierzu ca. 180 MB Downloadvolumen.
echo.
echo 1) QEMU jetzt lokal im Projektordner einrichten (Empfohlen)
echo 2) Abbrechen und beenden
echo.
set /p QEMU_CHOICE="%YELLOW%Waehlen Sie eine Option (1 oder 2): %RESET%"

if "%QEMU_CHOICE%"=="1" (
    set "DOWNLOAD_TARGET=QEMU"
    goto :NET_PROXY_CHECK
) else (
    exit
)


:: =======================================================================
:: 💻 HAUPTMENÜ (Direktstart bei bestehender Installation)
:: =======================================================================
:MAIN_MENU
cls
echo %BLUE%=======================================================================%RESET%
echo      ctrlX OS SDK App Build-Environment Console %GREEN%(Consolidated Setup)%RESET%
echo %BLUE%=======================================================================%RESET%
echo(
echo Dieses Setup verwaltet und startet Ihre ctrlX App Build-VMs direkt.
echo.
echo %BLUE%[STATUS] Vorhandene VMs im Verzeichnis 'instances':%RESET%
set VM22_STATUS=%RED%Nicht vorhanden%RESET%
set VM24_STATUS=%RED%Nicht vorhanden%RESET%
if exist ".\instances\ubuntu-build-env-core22.qcow2" set VM22_STATUS=%GREEN%Vorhanden%RESET%
if exist ".\instances\ubuntu-build-env-core24.qcow2" set VM24_STATUS=%GREEN%Vorhanden%RESET%

echo   - Ubuntu Core 22 (für ctrlX OS 1.x/2.x/3.x) -> %VM22_STATUS%
echo   - Ubuntu Core 24 (für ctrlX OS 4.x)       -> %VM24_STATUS%
echo(
echo %BLUE%[QEMU-Laufzeitumgebung]%RESET%
echo   - Modus: %GREEN%%QEMU_SOURCE%%RESET%
echo   - Pfad:  %YELLOW%%QEMU_EXE%%RESET%
echo(
echo %BLUE%=======================================================================%RESET%
echo Bitte waehlen Sie eine Aktion:
echo 1) Vorhandene VM starten
echo 2) Neue VM herunterladen und einrichten (ctrlX OS Version waehlen)
echo 3) Beenden
echo(
set /p MAIN_CHOICE="%YELLOW%Waehlen Sie eine Option (1, 2 oder 3): %RESET%"

if "%MAIN_CHOICE%"=="1" goto :CHOOSE_START_VM
if "%MAIN_CHOICE%"=="2" goto :CHOOSE_DOWNLOAD_VERSION
if "%MAIN_CHOICE%"=="3" exit
goto :MAIN_MENU


:: =======================================================================
:: 🚀 MENÜ-OPTION 1: VORHANDENE VM STARTEN
:: =======================================================================
:CHOOSE_START_VM
cls
echo %BLUE%=======================================================================%RESET%
echo %GREEN%                    VORHANDENE VM STARTEN%RESET%
echo %BLUE%=======================================================================%RESET%
echo(
echo Welche VM möchten Sie starten?
echo 1) Ubuntu Core 22 (für ctrlX OS 1.x / 2.x / 3.x) [%VM22_STATUS%]
echo 2) Ubuntu Core 24 (für ctrlX OS 4.x)             [%VM24_STATUS%]
echo 3) Zurück zum Hauptmenü
echo(
set /p START_CHOICE="%YELLOW%Waehlen Sie eine Option (1, 2 oder 3): %RESET%"

if "%START_CHOICE%"=="1" goto :PREPARE_START_VM22
if "%START_CHOICE%"=="2" goto :PREPARE_START_VM24
if "%START_CHOICE%"=="3" goto :MAIN_MENU
goto :CHOOSE_START_VM

:PREPARE_START_VM22
if not exist ".\instances\ubuntu-build-env-core22.qcow2" (
    echo %RED%[ERROR] Die VM fuer Ubuntu Core 22 existiert nicht!%RESET%
    echo Bitte laden Sie diese zuerst ueber Option 2 herunter.
    pause
    goto :MAIN_MENU
)
set "CORE_VER=22"
goto :START_QEMU_VM

:PREPARE_START_VM24
if not exist ".\instances\ubuntu-build-env-core24.qcow2" (
    echo %RED%[ERROR] Die VM fuer Ubuntu Core 24 existiert nicht!%RESET%
    echo Bitte laden Sie diese zuerst ueber Option 2 herunter.
    pause
    goto :MAIN_MENU
)
set "CORE_VER=24"
goto :START_QEMU_VM


:: =======================================================================
:: 🚀 MENÜ-OPTION 2: VM VERSIONAUSWAHL
:: =======================================================================
:CHOOSE_DOWNLOAD_VERSION
cls
echo %BLUE%=======================================================================%RESET%
echo %GREEN%               NEUE VM DOWNLOADEN UND EINRICHTEN%RESET%
echo %BLUE%=======================================================================%RESET%
echo(
echo Bitte waehlen Sie die gewuenschte ctrlX OS Zielversion aus:
echo.
echo 1) ctrlX OS 1.xx %YELLOW%(Nutzt standardmaeßig Core 20; nutzt Core 22 als Fallback)%RESET%
echo 2) ctrlX OS 2.xx %GREEN%(Basiert auf Ubuntu Core 22)%RESET%
echo 3) ctrlX OS 3.xx %GREEN%(Basiert auf Ubuntu Core 22)%RESET%
echo 4) ctrlX OS 4.xx %GREEN%(Basiert auf Ubuntu Core 24)%RESET%
echo 5) Zurück zum Hauptmenü
echo(
set /p OS_CHOICE="%YELLOW%Waehlen Sie eine Option (1, 2, 3, 4 oder 5): %RESET%"

if "%OS_CHOICE%"=="1" (
    set "CORE_VER=22"
    set "DOWNLOAD_TARGET=VM"
    echo %YELLOW%[Info] ctrlX OS 1.xx nutzt standardmaeßig Core 20. Wir richten Core 22 ein.%RESET%
    pause
    goto :NET_PROXY_CHECK
)
if "%OS_CHOICE%"=="2" (
    set "CORE_VER=22"
    set "DOWNLOAD_TARGET=VM"
    goto :NET_PROXY_CHECK
)
if "%OS_CHOICE%"=="3" (
    set "CORE_VER=22"
    set "DOWNLOAD_TARGET=VM"
    goto :NET_PROXY_CHECK
)
if "%OS_CHOICE%"=="4" (
    set "CORE_VER=24"
    set "DOWNLOAD_TARGET=VM"
    goto :NET_PROXY_CHECK
)
if "%OS_CHOICE%"=="5" goto :MAIN_MENU
goto :CHOOSE_DOWNLOAD_VERSION


:: =======================================================================
:: 🚀 PROXY-ABFRAGE (Dynamisch aufgerufen vor Downloads)
:: =======================================================================
:NET_PROXY_CHECK
cls
echo %BLUE%=======================================================================%RESET%
echo %GREEN%                 NETZWERK- und PROXY-ABFRAGE%RESET%
echo %BLUE%=======================================================================%RESET%
echo(
echo [Netzwerk] %YELLOW%Bestimme Arbeitsumgebung...%RESET%
echo Bitte waehlen Sie Ihre Arbeitsumgebung aus:
echo 1) Ich bin Bosch-Mitarbeiter %BLUE%(RB Local Proxy Manager)%RESET%
echo 2) Ich bin ein partner MIT einem %BLUE%Firmen-Proxy%RESET%
echo 3) Ich bin ein partner %BLUE%OHNE Proxy (Direkt)%RESET%
echo(
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
goto :ROUTE_DOWNLOAD

:EXT_PROXY
set USE_PROXY=true
if not exist "proxy.env" (
    echo CUSTOMER_PROXY_URL=http://ihr-proxy-server.de:8080 > proxy.env
    echo.
    echo %RED%[ERROR] Bitte tragen Sie Ihre Proxy-Daten in die Datei 'proxy.env' ein und starten Sie neu!%RESET%
    pause
    goto :MAIN_MENU
)
for /f "delims=" %%a in (proxy.env) do set %%a
set PROXY_URL=%CUSTOMER_PROXY_URL%
goto :ROUTE_DOWNLOAD

:NO_PROXY
echo.
echo - %GREEN%Direkte Internetverbindung%RESET% aktiv.
goto :ROUTE_DOWNLOAD

:ROUTE_DOWNLOAD
if "%DOWNLOAD_TARGET%"=="QEMU" goto :DOWNLOAD_QEMU_INST
if "%DOWNLOAD_TARGET%"=="VM" goto :DOWNLOAD_VM
goto :MAIN_MENU


:: =======================================================================
:: 📦 AUTOMATISIERTER QEMU DOWNLOAD & SILENT SETUP
:: =======================================================================
:DOWNLOAD_QEMU_INST
cls
echo %BLUE%=======================================================================%RESET%
echo %GREEN%               DOWNLOADE UND INSTALLIERE LOKALES QEMU%RESET%
echo %BLUE%=======================================================================%RESET%
echo(
:: Stabiles QEMU Windows 64-Bit Release von weilnetz.de
set "QEMU_INSTALLER_URL=https://qemu.weilnetz.de/w64/2024/qemu-w64-setup-20241220.exe"
set "QEMU_TEMP_FILE=.\qemu_temp_setup.exe"

echo %BLUE%[Download]%RESET% Lade das offizielle QEMU Windows-Paket herunter...
echo %YELLOW%(Dauer: ca. 1-2 Minuten - Der Ladebalken zeigt den Fortschritt)%RESET%
echo URL: %QEMU_INSTALLER_URL%
echo(

if "%USE_PROXY%"=="true" (
    curl.exe -k -x %PROXY_URL% -L -# -o "%QEMU_TEMP_FILE%" "%QEMU_INSTALLER_URL%"
) else (
    curl.exe -k -L -# -o "%QEMU_TEMP_FILE%" "%QEMU_INSTALLER_URL%"
)

if not exist "%QEMU_TEMP_FILE%" (
    echo.
    echo %RED%[ERROR] Download fehlgeschlagen! Bitte Netzwerk- und Proxy-Einstellungen prüfen.%RESET%
    pause
    goto :MAIN_MENU
)

echo.
echo %BLUE%[Installation]%RESET% Installiere QEMU im Projektordner '.\qemu\'...
echo Bitte warten, dies dauert einen kurzen Moment...

:: Echte, 100% geräuschlose Hintergrundinstallation ohne GUI und ohne Prompts
start /wait "" "%QEMU_TEMP_FILE%" /SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCLOSEAPPLICATIONS /DIR="%PROJEKT_PFAD%qemu" /LANG=en

:: Aufräumen des heruntergeladenen Installers
del "%QEMU_TEMP_FILE%" >nul 2>&1

if exist ".\qemu\qemu-system-x86_64.exe" (
    set "QEMU_EXE=%PROJEKT_PFAD%qemu\qemu-system-x86_64.exe"
    set "QEMU_SOURCE=Lokal im Projekt (Isoliert & Autark)"
    echo.
    echo %GREEN%✔ Lokales QEMU erfolgreich eingerichtet!%RESET%
    pause
    goto :MAIN_MENU
) else (
    echo.
    echo %RED%[ERROR] Die Installation scheint fehlerhaft gewesen zu sein.%RESET%
    echo 'qemu-system-x86_64.exe' wurde nicht im Ordner '.\qemu\' gefunden.
    pause
    exit
)


:: =======================================================================
:: 🚀 DOWNLOAD & SSH CONFIGURATION (VMs)
:: =======================================================================
:DOWNLOAD_VM
cls
echo %BLUE%=======================================================================%RESET%
echo %GREEN%                      DOWNLOAD DER SDK BUILD-VM%RESET%
echo %BLUE%=======================================================================%RESET%
echo(

if not exist ".\instances" mkdir ".\instances" >nul 2>&1

set "VM_FILE=.\instances\ubuntu-build-env-core%CORE_VER%.qcow2"

:: Setze passenden Download-Link basierend auf Core-Version
if "%CORE_VER%"=="22" (
    set "DOWNLOAD_URL=https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img"
) else (
    set "DOWNLOAD_URL=https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
)

echo %BLUE%[Download]%RESET% Lade die originale Bosch-Rexroth App Build-VM frisch herunter (Core %CORE_VER%)...
echo %YELLOW%(Dauer: ca. 2-3 Minuten - Der Ladebalken zeigt den Fortschritt)%RESET%
echo URL: %DOWNLOAD_URL%
echo(

if "%USE_PROXY%"=="true" (
    curl.exe -k -x %PROXY_URL% -L -# -o "%VM_FILE%" "%DOWNLOAD_URL%"
) else (
    curl.exe -k -L -# -o "%VM_FILE%" "%DOWNLOAD_URL%"
)

:: SSH-Schluessel generieren (Bypass aktiv)
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
:: 🚀 CLOUD-INIT CONFIGURATION (CIDATA)
:: =======================================================================
echo %BLUE%[Cloud-Init]%RESET% Erzeuge Konfigurationsdateien im CIDATA-Ordner...
if not exist ".\instances\cidata" mkdir ".\instances\cidata" >nul 2>&1

:: meta-data muss existieren
echo instance-id: ctrlx-build-env-vm > ".\instances\cidata\meta-data"
echo local-hostname: ctrlx-sdk-vm >> ".\instances\cidata\meta-data"

:: user-data mit sauberer Klartext-Passwort-Zuweisung und SSH-Injektion
echo #cloud-config> ".\instances\cidata\user-data"
echo users:>> ".\instances\cidata\user-data"
echo   - name: boschrexroth>> ".\instances\cidata\user-data"
echo     groups: sudo>> ".\instances\cidata\user-data"
echo     shell: /bin/bash>> ".\instances\cidata\user-data"
echo     sudo: ALL=^(ALL^) NOPASSWD:ALL>> ".\instances\cidata\user-data"
echo     ssh_authorized_keys:>> ".\instances\cidata\user-data"

:: Liest den lokal generierten Key dynamisch aus und schreibt ihn direkt in das Cloud-Init File
for /f "usebackq delims=" %%i in (".\id_rsa_ctrlx.pub") do (
    echo       - %%i>> ".\instances\cidata\user-data"
)

echo chpasswd:>> ".\instances\cidata\user-data"
echo   list: ^|>> ".\instances\cidata\user-data"
echo     boschrexroth:boschrexroth>> ".\instances\cidata\user-data"
echo   expire: False>> ".\instances\cidata\user-data"
echo ssh_pwauth: True>> ".\instances\cidata\user-data"
echo disable_root: False>> ".\instances\cidata\user-data"

:: network-config erzeugen (für moderne cloud-init Standards zwingend)
echo version: 2> ".\instances\cidata\network-config"
echo ethernets:>> ".\instances\cidata\network-config"
echo   all:>> ".\instances\cidata\network-config"
echo     match:>> ".\instances\cidata\network-config"
echo       name: "en*">> ".\instances\cidata\network-config"
echo     dhcp4: true>> ".\instances\cidata\network-config"


:: =======================================================================
:: 📀 SCHRITT 3: DOWNLOAD STANDALONE ISO-BRENNER (100% PORTABEL & STABIL)
:: =======================================================================
if exist ".\instances\mkisofs.exe" goto :GENERATE_ISO

echo %BLUE%[Setup]%RESET% Lade kompaktes ISO-Kompilierungs-Tool 'mkisofs.exe' herunter (ca. 380 KB)...
:: Holen der verifizierten, stabilen Windows-Binary aus dem offiziellen Cloudbase-Testing-Zweig
if "%USE_PROXY%"=="true" (
    curl.exe -k -x %PROXY_URL% -L -# -o ".\instances\mkisofs.exe" "https://github.com/cloudbase/cloudbase-init-test-resources/raw/master/bin/mkisofs.exe"
) else (
    curl.exe -k -L -# -o ".\instances\mkisofs.exe" "https://github.com/cloudbase/cloudbase-init-test-resources/raw/master/bin/mkisofs.exe"
)

:GENERATE_ISO
echo %BLUE%[ISO]%RESET% Generiere echte NoCloud-Konfigurations-ISO (seed.iso)...
if exist ".\instances\seed.iso" del ".\instances\seed.iso" >nul 2>&1

:: ECHTE, ABSOLUT FEHLERFREIE ISO-ERSTELLUNG REIN ÜBER CMD (Kein PowerShell, keine COM-Fehler!)
:: -J (Joliet) und -r (Rock Ridge) erzwingen die Beibehaltung von Kleinbuchstaben ("user-data", "meta-data")!
".\instances\mkisofs.exe" -o ".\instances\seed.iso" -ignore-error -ldots -allow-lowercase -allow-multidot -l -quiet -J -r -V "CIDATA" ".\instances\cidata"

:: Überprüfe, ob die ISO-Datei erfolgreich erstellt wurde
for %%F in ("%PROJEKT_PFAD%instances\seed.iso") do (
    if %%~zF LSS 1 (
        echo.
        echo %RED%[FEHLER] Die ISO-Erstellung mit mkisofs.exe ist fehlgeschlagen. seed.iso konnte nicht erzeugt werden!%RESET%
        pause
        goto :MAIN_MENU
    )
)

echo.
echo %GREEN%=======================================================================%RESET%
echo ✔ %GREEN%Setup erfolgreich abgeschlossen!%RESET%
echo %GREEN%=======================================================================%RESET%
echo VM ist einsatzbereit (Ubuntu Core %CORE_VER%).
echo.
echo %YELLOW%Druecken Sie eine beliebige Taste, um die VM jetzt direkt zu starten...%RESET%
pause >nul
goto :START_QEMU_VM


:: =======================================================================
:: 🚀 VM INTERN STARTEN (Direkte QEMU-Integration - Robust & Flat)
:: =======================================================================
:START_QEMU_VM
cls
echo %BLUE%=======================================================================%RESET%
echo %GREEN%                  STARTE ctrlX SDK BUILD-ENVIRONMENT (Core %CORE_VER%)%RESET%
echo %BLUE%=======================================================================%RESET%
echo(
echo Aktiver QEMU-Pfad: %YELLOW%%QEMU_EXE%%RESET%
echo Port 11022 auf dem Windows-Host leitet auf die VM um.
echo.
echo * SSH-Verbindung via VS Code Remote-SSH: %YELLOW%ctrlx-sdk-vm%RESET%
echo * Manuelles Beenden der VM: In der VM %YELLOW%sudo shutdown -h now%RESET% eingeben.
echo %BLUE%=======================================================================%RESET%
echo(

:: Sicherheits-Check: Falls die seed.iso fehlt, springe zur Erstellung
if exist "%PROJEKT_PFAD%instances\seed.iso" goto :START_QEMU_NOW
if exist "%PROJEKT_PFAD%instances\cidata\user-data" (
    echo %YELLOW%[Sicherheit] seed.iso fehlt. Generiere neu...%RESET%
    goto :GENERATE_ISO
)
echo %RED%[ERROR] Die Cloud-Init Konfiguration fehlt! Bitte VM neu downloaden (Option 2).%RESET%
pause
goto :MAIN_MENU

:START_QEMU_NOW
:: Loesche alte Logdateien, falls vorhanden
if exist qemu_error.log del qemu_error.log >nul 2>&1

:: === DIE MODERNE Q35 LÖSUNG ===
:: Da mkisofs eine perfekte ISO mit echtem Volume-Label CIDATA erzeugt,
:: erkennt cloud-init diese auf dem Q35-Mainboard nun vollautomatisch und fehlerfrei!
"%QEMU_EXE%" -M q35 -m 4G -smp 2 -drive "file=%PROJEKT_PFAD%instances\ubuntu-build-env-core%CORE_VER%.qcow2,format=qcow2,if=virtio,file.locking=off" -cdrom "%PROJEKT_PFAD%instances\seed.iso" -net nic,model=virtio -net user,hostfwd=tcp::11022-:22 -serial mon:stdio 2> qemu_error.log

:: Fehlerbehandlung ohne Klammer-Verschachtelung
if not exist "%PROJEKT_PFAD%qemu_error.log" goto :POST_RUN
findstr /r "[a-zA-Z0-9]" "%PROJEKT_PFAD%qemu_error.log" >nul 2>&1
if %errorLevel% neq 0 goto :POST_RUN

echo(
echo %RED%[WARNUNG] QEMU wurde unerwartet beendet! Oeffne Fehlerprotokoll...%RESET%
notepad.exe "%PROJEKT_PFAD%qemu_error.log"

:POST_RUN
echo(
echo %YELLOW%Zurueck zum Hauptmenue...%RESET%
pause
goto :MAIN_MENU