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

LOG_FILE="./setup_install.log"
> "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CLEAR='\033[0m'

NET_CHOICE=$1
WINDOWS_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')

echo -e "${BLUE}=========================================================="
echo -e "      ctrlX OS SDK Build-Environment & SSH Installation   "
echo -e "==========================================================${CLEAR}\n"

# ==============================================================================
# SCHRITT -1: Globale VPN-Optimierung (.wslconfig) herstellen & erzwingen
# ==============================================================================
WSL_GLOBAL_CONFIG="/mnt/c/Users/${WINDOWS_USER}/.wslconfig"
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
# SCHRITT 0: Proxy-Verankerung auf Linux-Ebene
# ==============================================================================
USE_PROXY=false
if [ "$NET_CHOICE" = "1" ]; then
    USE_PROXY=true
    PROXY_URL="http://127.0.0.1:3128"
    echo -e "${GREEN}✔ Koppele Linux an das aktive Bosch-Proxy-Tool (127.0.0.1:3128)...${CLEAR}"
elif [ "$NET_CHOICE" = "2" ]; then
    USE_PROXY=true
    source "./proxy.env" 2>/dev/null
    PROXY_URL="$CUSTOMER_PROXY_URL"
    echo -e "${GREEN}✔ Koppele Linux an Firmen-Proxy: $PROXY_URL${CLEAR}"
fi

if [ "$USE_PROXY" = true ]; then
    export http_proxy="$PROXY_URL"
    export https_proxy="$PROXY_URL"
    export no_proxy="localhost,127.0.0.1,.bosch.com"
    CURL_PROXY_OPT="-x $PROXY_URL"
    
    echo "Acquire::http::Proxy \"$PROXY_URL\";" | sudo tee /etc/apt/apt.conf.d/proxy.conf > /dev/null
    echo "Acquire::https::Proxy \"$PROXY_URL\";" | sudo tee -a /etc/apt/apt.conf.d/proxy.conf > /dev/null
fi

# ==============================================================================
# SCHRITT 1: Docker-Engine in WSL installieren
# ==============================================================================
echo -e "\n${BLUE}[1/5] Installiere Docker Engine in WSL...${CLEAR}"
sudo groupadd docker 2>/dev/null
sudo usermod -aG docker $USER 2>/dev/null

if ! command -v docker &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg unzip net-tools
    sudo install -m 0755 -d /etc/apt/keyrings
    
    curl $CURL_PROXY_OPT -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
    
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    DOCKER_CODENAME="noble"
    if [[ "$CODENAME" != "resolute" && "$CODENAME" != "noble" ]]; then DOCKER_CODENAME="$CODENAME"; fi
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $DOCKER_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Docker systemd Proxy-Drop-In schreiben
if [ "$USE_PROXY" = true ]; then
    sudo mkdir -p /etc/systemd/system/docker.service.d
    cat <<EOF | sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf > /dev/null
[Service]
Environment="HTTP_PROXY=$PROXY_URL"
Environment="HTTPS_PROXY=$PROXY_URL"
Environment="NO_PROXY=localhost,127.0.0.1,.bosch.com"
EOF
fi

sudo systemctl daemon-reload
sudo systemctl restart docker.socket 2>/dev/null
sudo service docker start

# ==============================================================================
# SCHRITT 2: QEMU-Image Download über Linux (Falls noch nicht im Ordner)
# ==============================================================================
echo -e "\n${BLUE}[2/5] Prüfe ctrlX OS Build-Image...${CLEAR}"
mkdir -p "./instances"
VM_FILE="./instances/ubuntu-build-env-core22.qcow2"

if [ ! -f "$VM_FILE" ]; then
    echo "Lade das offizielle App Build-Environment (core22) von Rexroth herunter..."
    curl $CURL_PROXY_OPT -L -o "$VM_FILE" "https://github.com/boschrexroth/ctrlx-automation-sdk/releases/download/4.4.0/ubuntu-build-env-amd64.qcow2"
    echo -e "${GREEN}✔ Download erfolgreich abgeschlossen!${CLEAR}"
fi

# ==============================================================================
# SCHRITT 3: Container über Docker Compose starten
# ==============================================================================
echo -e "\n${BLUE}[3/5] Zünde ctrlX OS KVM-Container über Docker Compose...${CLEAR}"
docker compose down 2>/dev/null
docker compose up -d --build

# ==============================================================================
# SCHRITT 4: Erzeuge das direkte Start-Skript für QEMU im Container
# ==============================================================================
echo -e "\n${BLUE}[4/5] Erzeuge Start-Skript für QEMU im Container...${CLEAR}"
docker exec -d ctrlx-sdk-builder bash -c "echo 'qemu-system-x86_64 -m 4G -smp 2 -drive file=/workspace/instances/ubuntu-build-env-core22.qcow2,format=qcow2,if=virtio -net nic,model=virtio -net user,hostfwd=tcp::22-:22 -enable-kvm -nographic' > /usr/local/bin/start-vm && chmod +x /usr/local/bin/start-vm"

# Startet die VM im Hintergrund des Containers
docker exec -d ctrlx-sdk-builder bash -c "/usr/local/bin/start-vm"

# ==============================================================================
# SCHRITT 5: VS Code Windows-Extensions vorinstallieren
# ==============================================================================
echo -e "\n${BLUE}[5/5] Bereite VS Code Extensions vor...${CLEAR}"
code --install-extension ms-vscode-remote.remote-ssh --force > /dev/null 2>&1

echo -e "\n${GREEN}=========================================================="
echo "🎉 SETUP ERFOLGREICH BEENDET!"
echo -e "==========================================================${CLEAR}"
echo "Die ctrlX OS-VM läuft jetzt hochperformant via QEMU im Docker-Container."
echo -e "\n👉 ${YELLOW}SO VERBINDEN SIE SICH MIT VS CODE:${CLEAR}"
echo "  1. Öffnen Sie VS Code auf Windows."
echo "  2. Drücken Sie F1 und wählen Sie: 'Remote-SSH: Connect to Host...'"
echo "  3. Wählen Sie aus der Liste: 'ctrlx-sdk-container'"
echo -e "  4. VS Code verbindet sich passwortlos direkt mit Ihrem ctrlX-Build-System!\n"
echo "=========================================================="

echo -e "\n${YELLOW}Press enter to finish...${CLEAR}"
read
