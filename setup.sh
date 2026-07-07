#!/bin/bash

# ==============================================================================
# SELBSTHEILUNG: Schutz vor Windows-Zeilenumbrüchen (CRLF -> LF)
# ==============================================================================
if [[ "$0" != "/tmp/clean_setup.sh" ]]; then
    if grep -q $'\r' "$0" 2>/dev/null; then
        echo "⚠️ Windows-Zeilenumbrüche (CRLF) erkannt. Bereinige Skript automatisch..."
        tr -d '\r' < "$0" > /tmp/clean_setup.sh
        chmod +x /tmp/clean_setup.sh
        exec /tmp/clean_setup.sh "$@"
        exit 0
    fi
fi

# Farben für schöne Terminal-Ausgaben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CLEAR='\033[0m'

SETUP_FLAG_FILE="./.setup_completed"

# ==============================================================================
# SCHRITT -2: Globale VPN-Optimierung (.wslconfig) herstellen
# ==============================================================================
WSL_GLOBAL_CONFIG="/mnt/c/Users/$(powershell.exe -Command "echo \$env:USERNAME" | tr -d '\r')/.wslconfig"
if [ ! -f "$WSL_GLOBAL_CONFIG" ] || ! grep -q "networkingMode=mirrored" "$WSL_GLOBAL_CONFIG" 2>/dev/null; then
    echo -e "${YELLOW}⚙️ Optimiere Windows WSL-Konfiguration für VPN-Betrieb...${CLEAR}"
    mkdir -p "$(dirname "$WSL_GLOBAL_CONFIG")"
    cat <<EOF > "$WSL_GLOBAL_CONFIG"
[wsl2]
nestedVirtualization=true
dnsTunneling=true
autoProxy=true
networkingMode=mirrored
EOF
    echo -e "${GREEN}✔ VPN-Optimierung angewendet!${CLEAR}"
    echo -e "${RED}🛑 WICHTIG: Damit die VPN-Einstellungen aktiv werden, muss WSL neu gestartet werden.${CLEAR}"
    echo -e "Bitte schließen Sie dieses Fenster und führen Sie in Ihrer Windows PowerShell aus:"
    echo -e "   ${BLUE}wsl --shutdown${CLEAR}"
    echo -e "Starten Sie danach das Terminal und diese Setup erneut."
    exit 0
fi

# ==============================================================================
# SCHRITT 0: Netzwerk- und Proxy-Guiding (Bosch & Extern)
# ==============================================================================
echo -e "${BLUE}[0/7] Netzwerkkonfiguration & Proxy-Setup...${CLEAR}"
echo "Dieses Setup benötigt eine Internetverbindung, um Docker und das ctrlX VM-Image zu laden."
echo "Bitte wählen Sie Ihre Arbeitsumgebung aus:"
echo "1) Ich bin Bosch-Mitarbeiter (im Bosch-Netzwerk / Corporate VPN)"
echo "2) Ich bin ein externer Partner/Kunde MIT einem Firmen-Proxy"
echo "3) Ich bin ein externer Partner/Kunde OHNE Proxy (Direkte Internetverbindung)"
read -p "Auswahl (1, 2 oder 3): " NET_CHOICE

USE_PROXY=false
CURL_PROXY_OPT=""

if [ "$NET_CHOICE" = "1" ]; then
    # === BOSCH WORKFLOW ===
    USE_PROXY=true
    echo -e "\n${BLUE}➔ Bosch-Netzwerk ausgewählt (VPN-Kompatibilitätsmodus aktiv).${CLEAR}"
    echo "Richte die empfohlene Proxy-Brücke 'px.exe' ein..."
    
    WINDOWS_IP="127.0.0.1"
    
    # Windows-Firewall-Regel für Port 3128 hinzufügen (Verhindert Connection Timeouts in WSL)
    powershell.exe -Command "if (-not (Get-NetFirewallRule -DisplayName 'Px Proxy WSL Gateway' -ErrorAction SilentlyContinue)) { New-NetFirewallRule -DisplayName 'Px Proxy WSL Gateway' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3128 -Enabled True } | Out-Null" 2>/dev/null
    
    PX_RUNNING=$(powershell.exe -Command "Get-Process px -ErrorAction SilentlyContinue" 2>/dev/null)
    
    if [ -z "$PX_RUNNING" ]; then
        echo -e "${YELLOW}⚠️ px.exe läuft nicht im Hintergrund auf Windows.${CLEAR}"
        WIN_DIR=$(wslpath -w "$(pwd)")
        mkdir -p "./tools"
        
        echo "Lade px.exe (Bosch-Proxy-Helper) herunter..."
        curl -L -o "./tools/px.zip" "https://github.com/genotrance/px/releases/download/v0.8.6/px-v0.8.6-windows.zip" &> /dev/null
        if command -v unzip &> /dev/null; then
            unzip -o "./tools/px.zip" -d "./tools/" > /dev/null
            rm -f "./tools/px.zip"
        fi
        
        echo -e "${BLUE}UAC-Abfrage: Bitte bestätigen Sie das Ausführen von px.exe auf Windows...${CLEAR}"
        powershell.exe -Command "Start-Process cmd.exe -ArgumentList '/c cmd.exe /c cd \"$WIN_DIR\tools\" && px.exe --gateway --save --install' -Verb RunAs"
        echo "Warte auf Initialisierung von px.exe (5 Sekunden)..."
        sleep 5
    else
        echo -e "${GREEN}✔ px.exe Proxy-Helper ist aktiv.${CLEAR}"
    fi
    PROXY_URL="http://${WINDOWS_IP}:3128"

elif [ "$NET_CHOICE" = "2" ]; then
    # === EXTERNER KUNDE MIT PROXY ===
    USE_PROXY=true
    echo -e "\n${BLUE}➔ Externer Proxy-Modus ausgewählt.${CLEAR}"
    
    PROXY_ENV_FILE="./proxy.env"
    if [ ! -f "$PROXY_ENV_FILE" ]; then
        echo -e "${YELLOW}Hinweis: Es wurde keine '${PROXY_ENV_FILE}' Datei im Hauptordner gefunden.${CLEAR}"
        echo "Ich erstelle eine Vorlage für Sie."
        cat <<EOF > "$PROXY_ENV_FILE"
# Bitte tragen Sie hier Ihre Firmen-Proxy-URL ein:
CUSTOMER_PROXY_URL=http://ihr-proxy-server.de:8080
EOF
        echo -e "${RED}🛑 AKTION ERFORDERLICH:${CLEAR}"
        echo -e "Bitte öffnen Sie jetzt die neu erstellte Datei ${GREEN}proxy.env${CLEAR} im Projektordner,"
        echo -e "tragen Sie dort Ihre Proxy-Daten ein und starten Sie das Skript danach erneut."
        exit 0
    else
        source "$PROXY_ENV_FILE"
        PROXY_URL="$CUSTOMER_PROXY_URL"
        if [ -z "$PROXY_URL" ] || [[ "$PROXY_URL" == *"ihr-proxy-server"* ]]; then
            echo -e "${RED}❌ FEHLER: In 'proxy.env' ist keine gültige Proxy-URL eingetragen!${CLEAR}"
            echo "Bitte tragen Sie Ihre echten Proxy-Daten ein und starten Sie das Skript neu."
            exit 1
        fi
        echo -e "${GREEN}✔ Eigene Proxy-Konfiguration geladen: $PROXY_URL${CLEAR}"
    fi

else
    # === DIREKTE VERBINDUNG ===
    echo -e "\n${GREEN}✔ Direkte Internetverbindung aktiv. Es wird kein Proxy konfiguriert.${CLEAR}"
    sudo rm -f /etc/apt/apt.conf.d/proxy.conf
fi

# Lokale Proxy-Konfiguration (Komplett ohne sudo -E!)
if [ "$USE_PROXY" = true ]; then
    export http_proxy="$PROXY_URL"
    export https_proxy="$PROXY_URL"
    export no_proxy="localhost,127.0.0.1,.bosch.com"
    CURL_PROXY_OPT="-x $PROXY_URL"
    
    # 1. APT permanent konfigurieren
    echo "Acquire::http::Proxy \"$PROXY_URL\";" | sudo tee /etc/apt/apt.conf.d/proxy.conf > /dev/null
    echo "Acquire::https::Proxy \"$PROXY_URL\";" | sudo tee -a /etc/apt/apt.conf.d/proxy.conf > /dev/null
    
    # 2. Docker Service permanent konfigurieren
    sudo mkdir -p /etc/default
    echo "export http_proxy=\"$PROXY_URL\"" | sudo tee /etc/default/docker > /dev/null
    echo "export https_proxy=\"$PROXY_URL\"" | sudo tee -a /etc/default/docker > /dev/null
    
    echo -e "${GREEN}✔ Proxy-Routing erfolgreich konfiguriert!${CLEAR}\n"
fi

# ==============================================================================
# SCHRITT 1: System-Checks & Auto-Installation von Docker
# ==============================================================================
echo -e "\n${BLUE}[1/7] Überprüfe Systemanforderungen (Docker)...${CLEAR}"

# Prüfen, ob docker-ce installiert ist
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}⚠️ Docker Engine (docker-ce) ist in WSL nicht installiert!${CLEAR}"
    echo "Für dieses Setup wird die kostenlose Docker Engine benötigt."
    read -p "Soll das Skript Docker jetzt vollautomatisch für Sie installieren? (y/n): " INSTALL_DOCKER
    if [[ "$INSTALL_DOCKER" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Starte automatische Docker-Installation. Bitte Ihr Linux-Sudo-Passwort eingeben...${CLEAR}"
        
        # APT-Datenbank aktualisieren
        sudo apt-get update
        for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do 
            sudo apt-get remove -y $pkg 2>/dev/null
        done
        
        # Hilfswerkzeuge installieren
        sudo apt-get install -y ca-certificates curl gnupg unzip net-tools
        sudo install -m 0755 -d /etc/apt/keyrings
        
        # Docker Key laden (Sicherer Download nach /tmp ohne sudo -E)
        curl $CURL_PROXY_OPT -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.asc
        sudo mv /tmp/docker.asc /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        # Offizielles Docker-Repository eintragen
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Docker CE installieren
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        # Gruppenrechte & passwortfreien Start für den Dienst erlauben
        sudo usermod -aG docker $USER
        echo "$USER ALL=(ALL) NOPASSWD: /usr/sbin/service docker *" | sudo tee /etc/sudoers.d/docker-service > /dev/null

        # Autostart in .bashrc sichern
        if ! grep -q "service docker start" ~/.bashrc; then
            cat << 'EOF' >> ~/.bashrc
# --- AUTOMATIC DOCKER ENGINE LAUNCHER ---
if service docker status 2>&1 | grep -q "is not running"; then
    echo "Starting Docker Engine..."
    sudo service docker start > /dev/null 2>&1
fi
EOF
        fi
        
        # Docker-Service sofort starten
        sudo service docker start
        
        echo -e "${GREEN}✔ Docker Engine erfolgreich installiert!${CLEAR}"
        echo -e "${YELLOW}Bitte schließen Sie dieses WSL-Terminal einmal komplett und öffnen Sie es neu, um die Rechte zu aktivieren.${CLEAR}"
        exit 0
    else
        echo -e "${RED}❌ Setup abgebrochen. Docker wird zwingend benötigt.${CLEAR}"
        exit 1
    fi
fi

# Docker-Dienst falls nötig geräuschlos im Hintergrund starten
if service docker status 2>&1 | grep -q "is not running"; then
    echo -e "${YELLOW}Docker-Dienst läuft nicht. Starte Docker Engine...${CLEAR}"
    sudo service docker start > /dev/null 2>&1
fi
echo -e "${GREEN}✔ Docker Engine läuft und ist einsatzbereit.${CLEAR}"

# Kennzeichnen, dass das Erst-Setup abgeschlossen ist
touch "$SETUP_FLAG_FILE" 2>/dev/null

# VS Code CLI Vorhandensein prüfen
HAS_VSCODE=true
if ! command -v code &> /dev/null; then
    HAS_VSCODE=false
fi

# ==============================================================================
# SCHRITT 2: Instanzen-Scanner & Startmenü
# ==============================================================================
echo -e "\n${BLUE}[2/7] Suche nach bestehenden ctrlX-Umgebungen...${CLEAR}"
mkdir -p ./instances

# Sucht alle Unterordner im Verzeichnis "instances"
INSTANCES=($(ls -d ./instances/*/ 2>/dev/null | sed 's|./instances/||g' | sed 's|/||g'))

if [ ${#INSTANCES[@]} -gt 0 ]; then
    echo "Folgende ctrlX-VM-Instanzen wurden gefunden:"
    for i in "${!INSTANCES[@]}"; do
        echo -e "  $((i+1))) ${GREEN}${INSTANCES[$i]}${CLEAR}"
    done
    echo "  n) Neue zusätzliche VM-Instanz erstellen"
    read -p "Wählen Sie eine Aktion (1-${#INSTANCES[@]} oder n): " INSTANCE_ACTION
else
    INSTANCE_ACTION="n"
fi

# ==============================================================================
# SCHRITT 3: Aktionsmenü für bestehende Instanz (Schnellstart)
# ==============================================================================
if [ "$INSTANCE_ACTION" != "n" ]; then
    SELECTED_INDEX=$((INSTANCE_ACTION-1))
    INSTANCE_NAME="${INSTANCES[$SELECTED_INDEX]}"
    echo -e "\n${GREEN}✔ Instanz '$INSTANCE_NAME' ausgewählt!${CLEAR}"
    
    echo -e "\nWas möchten Sie tun?"
    echo -e "1) ${BLUE}Start & Code${CLEAR} - VM starten & VS Code öffnen (Remote-SSH) [Schnellstart]"
    echo -e "2) ${YELLOW}Deploy${CLEAR} - App auf reale ctrlX CORE Steuerung hochladen"
    echo -e "3) ${RED}Stop${CLEAR} - Diese VM-Instanz herunterfahren"
    read -p "Auswahl (1, 2 oder 3): " ACTION_CHOICE

    if [ "$ACTION_CHOICE" = "1" ]; then
        # === VM & VS-CODE SCHNELLSTART ===
        if [ "$(docker ps -q -f name=ctrlx-builder-$INSTANCE_NAME)" ]; then
            echo -e "${GREEN}✔ VM-Container läuft bereits im Hintergrund.${CLEAR}"
        else
            echo "Starte VM-Instanz $INSTANCE_NAME..."
            docker compose --env-file ./instances/$INSTANCE_NAME/.env up -d
            echo -e "${GREEN}✔ Instanz erfolgreich gestartet!${CLEAR}"
            echo "Warte kurz auf den SSH-Dienst der VM (ca. 5 Sekunden)..."
            sleep 5
        fi

        if [ "$HAS_VSCODE" = true ]; then
            echo -e "\n${BLUE}🚀 Starte VS Code und verbinde mit ctrlx-$INSTANCE_NAME...${CLEAR}"
            code.cmd --folder-uri "vscode-remote://ssh-remote+ctrlx-$INSTANCE_NAME/home/boschrexroth" &
            echo -e "${GREEN}✔ VS Code wurde gestartet. Viel Spaß beim Coden!${CLEAR}"
            exit 0
        else
            PORT_EXTRACT=$(grep HOST_SSH_PORT ./instances/$INSTANCE_NAME/.env | cut -d'=' -f2)
            echo -e "${YELLOW}Hinweis: Kein VS Code installiert. Verbinden Sie sich manuell via SSH:${CLEAR}"
            echo -e "   ssh -p $PORT_EXTRACT boschrexroth@127.0.0.1"
            exit 0
        fi

    elif [ "$ACTION_CHOICE" = "2" ]; then
        # === DEPLOYMENT AUTOMATION ===
        echo -e "\n${YELLOW}🚀 Starte ctrlX CORE App Deployment Script...${CLEAR}"
        PY_CMD="python3"
        if ! command -v python3 &> /dev/null; then PY_CMD="python"; fi
        
        if ! command -v $PY_CMD &> /dev/null; then
            echo -e "${RED}❌ FEHLER: Python wurde auf diesem PC nicht gefunden!${CLEAR}"
            exit 1
        fi
        
        $PY_CMD -c "import requests" &> /dev/null
        if [ $? -ne 0 ]; then
            $PY_CMD -m pip install requests urllib3 > /dev/null
        fi

        $PY_CMD deploy.py
        exit 0

    elif [ "$ACTION_CHOICE" = "3" ]; then
        # === STOPP-BEFEHL ===
        echo "Fahre Instanz $INSTANCE_NAME herunter..."
        docker compose --env-file ./instances/$INSTANCE_NAME/.env down
        echo -e "${GREEN}✔ Instanz erfolgreich gestoppt.${CLEAR}"
        exit 0
    else
        echo -e "${RED}❌ Ungültige Auswahl.${CLEAR}"
        exit 1
    fi
fi

# ==============================================================================
# SCHRITT 4: Neue Instanz konfigurieren (Name & Ports)
# ==============================================================================
echo -e "\n${BLUE}[3/7] Neue Instanz konfigurieren...${CLEAR}"
read -p "Geben Sie der neuen Instanz einen Namen (z.B. projektA): " INSTANCE_NAME
INSTANCE_NAME=$(echo "$INSTANCE_NAME" | tr -dc 'a-zA-Z0-9_-')

if [ -z "$INSTANCE_NAME" ]; then
    INSTANCE_NAME="ctrlx_default"
fi

INSTANCE_DIR="./instances/$INSTANCE_NAME"
mkdir -p "$INSTANCE_DIR"

# Dynamische Portprüfung (verhindert Belegungs-Konflikte)
START_SSH_PORT=10022
while netstat -an 2>/dev/null | grep -q ":$START_SSH_PORT "; do
    START_SSH_PORT=$((START_SSH_PORT+1))
done
HOST_SSH_PORT=$START_SSH_PORT

START_DEBUG_PORT=12345
while netstat -an 2>/dev/null | grep -q ":$START_DEBUG_PORT "; do
    START_DEBUG_PORT=$((START_DEBUG_PORT+1))
done
HOST_DEBUG_PORT=$START_DEBUG_PORT

START_WEB_PORT=8080
while netstat -an 2>/dev/null | grep -q ":$START_WEB_PORT "; do
    START_WEB_PORT=$((START_WEB_PORT+1))
done
HOST_WEB_PORT=$START_WEB_PORT

echo -e "${GREEN}✔ Ports erfolgreich zugewiesen:${CLEAR}"
echo -e "   - SSH-Port:   $HOST_SSH_PORT"
echo -e "   - Debug-Port: $HOST_DEBUG_PORT"
echo -e "   - Web-UI-Port: $HOST_WEB_PORT"

# ==============================================================================
# SCHRITT 5: OS Version
# ==============================================================================
echo -e "\n${BLUE}[4/7] Betriebssystem konfigurieren...${CLEAR}"
echo "Unter welcher Version soll diese Instanz laufen?"
echo "1) ctrlX OS v1.xx (basiert auf Ubuntu Core 20)"
echo "2) ctrlX OS v2.xx (basiert auf Ubuntu Core 22) [Standard]"
read -p "Auswahl (1 oder 2): " VERSION_CHOICE

if [ "$VERSION_CHOICE" = "1" ]; then
    SELECTED_VERSION="core20"
    VM_FILE="$INSTANCE_DIR/ubuntu-core20.qcow2"
    DOWNLOAD_URL="https://github.com/boschrexroth/ctrlx-automation-sdk/releases/download/3.4.0/ubuntu-build-env-amd64.qcow2" 
else
    SELECTED_VERSION="core22"
    VM_FILE="$INSTANCE_DIR/ubuntu-core22.qcow2"
    DOWNLOAD_URL="https://github.com/boschrexroth/ctrlx-automation-sdk/releases/download/4.4.0/ubuntu-build-env-amd64.qcow2"
fi

# ==============================================================================
# SCHRITT 6: VM-Image Download
# ==============================================================================
echo -e "\n${BLUE}[5/7] Prüfe ctrlX QEMU-VM-Image...${CLEAR}"
if [ -f "$VM_FILE" ]; then
    echo -e "${GREEN}✔ QEMU-VM-Image existiert bereits im Instanz-Ordner.${CLEAR}"
else
    read -p "Soll das Image jetzt automatisch heruntergeladen werden? (~1.5 GB) (y/n): " DL_CHOICE
    if [[ "$DL_CHOICE" =~ ^[Yy]$ ]]; then
        echo "Lade VM-Image herunter... Bitte warten..."
        curl $CURL_PROXY_OPT -L -o "$VM_FILE" "$DOWNLOAD_URL"
        echo -e "${GREEN}✔ Download erfolgreich abgeschlossen!${CLEAR}"
    else
        echo -e "${RED}❌ Setup abgebrochen.${CLEAR} Bitte legen Sie die VM-Datei manuell ab unter: $VM_FILE"
        exit 1
    fi
fi

# ==============================================================================
# SCHRITT 7: SSH-Verbindungen & Security KVM-Fix
# ==============================================================================
echo -e "\n${BLUE}[6/7] Konfiguriere SSH und sichere KVM-Rechte...${CLEAR}"

# KVM-Rechte sicher im Hintergrund über wsl.conf anpassen (Group-660-Lösung)
WSL_CONF_PATH="/etc/wsl.conf"
if [ -f "$WSL_CONF_PATH" ]; then
    if ! grep -q "chmod 660 /dev/kvm" "$WSL_CONF_PATH" 2>/dev/null; then
        sudo sed -i '/\[boot\]/a command = chown root:kvm /dev/kvm && chmod 660 /dev/kvm' "$WSL_CONF_PATH"
        sudo usermod -a -G kvm $USER
    fi
fi

# SSH-Key-Generierung (Passwortlos)
SSH_CONFIG_DIR="$HOME/.ssh"
mkdir -p "$SSH_CONFIG_DIR"
MY_KEY="$SSH_CONFIG_DIR/id_rsa"
if [ ! -f "$MY_KEY" ] && [ ! -f "$SSH_CONFIG_DIR/id_ed25519" ]; then
    ssh-keygen -q -t rsa -b 4096 -N "" -f "$MY_KEY"
else
    if [ -f "$SSH_CONFIG_DIR/id_ed25519" ]; then
        MY_KEY="$SSH_CONFIG_DIR/id_ed25519"
    fi
fi

# Ziel in ~/.ssh/config eintragen
SSH_CONFIG_FILE="$SSH_CONFIG_DIR/config"
if ! grep -q "Host ctrlx-$INSTANCE_NAME" "$SSH_CONFIG_FILE" 2>/dev/null; then
    cat <<EOF >> "$SSH_CONFIG_FILE"

Host ctrlx-$INSTANCE_NAME
    HostName 127.0.0.1
    User boschrexroth
    Port $HOST_SSH_PORT
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    IdentityFile $MY_KEY
EOF
fi

# ==============================================================================
# SCHRITT 8: .env-Konfigurationsdatei schreiben
# ==============================================================================
echo -e "${BLUE}[7/7] Schreibe lokale Konfigurationsdaten...${CLEAR}"
if [ "$USE_PROXY" = true ]; then
    cat <<EOF > "$INSTANCE_DIR/.env"
INSTANCE_NAME=$INSTANCE_NAME
CTRLX_VERSION=$SELECTED_VERSION
HOST_SSH_PORT=$HOST_SSH_PORT
HOST_DEBUG_PORT=$HOST_DEBUG_PORT
HOST_WEB_PORT=$HOST_WEB_PORT
http_proxy=$PROXY_URL
https_proxy=$PROXY_URL
no_proxy=localhost,127.0.0.1,.bosch.com
HOST_PROXY=http://127.0.0.1:3128
EOF
else
    cat <<EOF > "$INSTANCE_DIR/.env"
INSTANCE_NAME=$INSTANCE_NAME
CTRLX_VERSION=$SELECTED_VERSION
HOST_SSH_PORT=$HOST_SSH_PORT
HOST_DEBUG_PORT=$HOST_DEBUG_PORT
HOST_WEB_PORT=$HOST_WEB_PORT
EOF
fi

# ==========================================
# VS CODE ERWEITERUNGEN INSTALLIEREN
# ==========================================
if [ "$HAS_VSCODE" = true ]; then
    echo "Installiere offizielle Bosch Rexroth VS Code Extensions..."
    code --install-extension ms-vscode-remote.remote-ssh --force > /dev/null
    code --install-extension ms-vscode.cpptools --force > /dev/null
    code --install-extension ms-python.python --force > /dev/null
fi

# ==========================================
# AUSGABE DER INSTRUKTIONEN (FINISH)
# ==========================================
echo -e "\n${GREEN}=========================================================="
echo "🎉 SETUP ERFOLGREICH BEENDET!"
echo -e "==========================================================${CLEAR}"
echo "Starten Sie Ihre neue Instanz jetzt mit:"
echo -e "${BLUE}   docker compose --env-file $INSTANCE_DIR/.env up -d --build${CLEAR}"
echo -e "\nKopieren Sie den SSH-Key (einmalig nach Bootzeit von ca. 1 Min):"
echo -e "${YELLOW}   ssh-copy-id -p $HOST_SSH_PORT boschrexroth@127.0.0.1${CLEAR}"
echo -e "\nDanach können Sie das Skript einfach erneut starten, um VS Code"
echo "automatisch mit der VM zu verbinden!"
echo "=========================================================="

# === WICHTIGER ARCHITEKTURHINWEIS ===
echo -e "\n${RED}=========================================================="
echo -e "⚠️  WICHTIGER HINWEIS ZUR PAKET-INSTALLATION (APT UPDATE/UPGRADE) "
echo -e "==========================================================${CLEAR}"
echo -e "Sie können innerhalb der VM 'sudo apt update && sudo apt upgrade'"
echo -e "ausführen, um Ihr Build-System zu aktualisieren."
echo -e ""
echo -e "🛑 ${YELLOW}ABER ACHTUNG FÜR DIE APP-ENTWICKLUNG:${CLEAR}"
echo -e "Die reale ctrlX CORE Steuerung läuft unter ${BLUE}Ubuntu Core${CLEAR}."
echo -e "Dort gibt es ${RED}KEIN apt-System${CLEAR} und das Dateisystem ist read-only!"
echo -e ""
echo -e "Wenn Sie zusätzliche Bibliotheken in Ihrer App benötigen:"
echo -e "  1. Installieren Sie diese ${RED}NICHT${CLEAR} einfach nur manuell via apt in der VM."
echo -e "  2. Definieren Sie die Pakete zwingend in Ihrer ${GREEN}snapcraft.yaml${CLEAR}"
echo -e "     unter ${BLUE}stage-packages${CLEAR} oder ${BLUE}parts${CLEAR}."
echo -e ""
echo -e "Nur so werden die Abhängigkeiten direkt in Ihr fertiges Snap-Paket"
echo -e "integriert, sodass die App später auf der echten Steuerung läuft!"
echo -e "=========================================================="
