"""
ctrlX CORE License Deployment Automation Script.

This module provides a command-line interface to automate the installation
of license capability responses (.bin files) on Bosch Rexroth ctrlX CORE devices
via the REST API. It supports single or multi-device installation, secure
credentials storage, and automatic 13-digit serial number retrieval.
"""

import os
import base64
import getpass
import requests
import urllib3

# Disable warnings for self-signed SSL certificates used by ctrlX CORE
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Configuration constants
ENV_FILE = "ctrlx_cores.env"
LICENSE_FOLDER = "./licenses"

# Global HTTP session initialization
HTTP_SESSION = requests.Session()
HTTP_SESSION.verify = False
HTTP_SESSION.trust_env = False  # Bypass system proxies for local communication


def load_cores() -> dict:
    """
    Load saved CORE configurations from the .env file.

    Returns:
        dict: A dictionary mapping IP addresses to credential dicts:
              { ip: { "username": user, "password": password } }
    """
    cores = {}
    if not os.path.exists(ENV_FILE):
        return cores

    with open(ENV_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, val = line.split("=", 1)
                if key.startswith("CORE_"):
                    # Decrypt key back to IP address (replace underscores with dots)
                    ip = key[5:].replace("_", ".")
                    try:
                        # Base64 decode credentials (obfuscated plaintext)
                        decoded = base64.b64decode(val).decode("utf-8")
                        user, password = decoded.split(":", 1)
                        cores[ip] = {"username": user, "password": password}
                    except (base64.binascii.Error, ValueError):
                        # Skip malformed lines
                        continue
    return cores


def save_core(ip: str, user: str, password: str) -> None:
    """
    Save or update a CORE configuration in the .env file with Base64 obfuscation.

    Args:
        ip (str): IP address of the ctrlX CORE.
        user (str): Username.
        password (str): Password.
    """
    key = f"CORE_{ip.replace('.', '_')}"
    plain_creds = f"{user}:{password}"
    encoded_creds = base64.b64encode(plain_creds.encode("utf-8")).decode("utf-8")

    lines = []
    updated = False
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip().startswith(f"{key}="):
                    lines.append(f"{key}={encoded_creds}\n")
                    updated = True
                else:
                    lines.append(line)

    if not updated:
        lines.append(f"{key}={encoded_creds}\n")

    with open(ENV_FILE, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print(f"[Info] Credentials for ctrlX CORE at {ip} saved to {ENV_FILE}")


def fetch_bearer_token(ip: str, user: str, password: str) -> bool:
    """
    Authenticate against the Identity Manager and fetch a Bearer token.

    Args:
        ip (str): IP address of the target.
        user (str): Username.
        password (str): Password.

    Returns:
        bool: True if authentication was successful, False otherwise.
    """
    url = f"https://{ip}/identity-manager/api/v2/auth/token"
    payload = {
        "name": user,
        "password": password
    }
    try:
        print(f"\n[Auth] Connecting to ctrlX CORE at {ip}...")
        response = HTTP_SESSION.post(url, json=payload, timeout=10)
        response.raise_for_status()
        token = response.json().get("access_token")
        if not token:
            print("[Error] 'access_token' not found in response.")
            return False
        HTTP_SESSION.headers.update({"Authorization": f"Bearer {token}"})
        print(f"[Success] Authenticated successfully on {ip}.")
        return True
    except requests.exceptions.RequestException as e:
        print(f"[Error] Connection or authentication failed for {ip}: {e}")
        return False


def fetch_serial_number(ip: str) -> str | None:
    """
    Retrieve the 13-digit hardware serial number of the ctrlX CORE.
    Tries the Typeplate Data Layer path first, followed by diagnostics.

    Args:
        ip (str): IP address of the device.

    Returns:
        str | None: The serial number if found, otherwise None.
    """
    headers = {"Accept": "application/json"}
    
    # 1. Primary Endpoint: Typeplate Data Layer path (Highly specific for ctrlX OS)
    typeplate_url = f"https://{ip}/automation/api/v2/nodes/system/typeplate/ctrlXDeviceId"
    try:
        response = HTTP_SESSION.get(typeplate_url, headers=headers, timeout=5)
        if response.status_code == 200:
            data = response.json()
            raw_val = data.get("value")
            # Extract serial from Data Layer wrapper
            serial = raw_val["value"] if isinstance(raw_val, dict) and "value" in raw_val else raw_val
            if serial:
                serial_str = str(serial).strip().strip('"')
                print(f"[Success] Automatically fetched serial number via Typeplate: {serial_str}")
                return serial_str
    except Exception as e:
        print(f"[Info] Typeplate API node access tried, falling back...")

    # 2. Secondary Endpoint: Modern DeviceAdmin v2 Info (Fallback)
    devadmin_url = f"https://{ip}/deviceadmin/api/v2/information"
    try:
        response = HTTP_SESSION.get(devadmin_url, headers=headers, timeout=5)
        if response.status_code == 200:
            data = response.json()
            device_info = data.get("device", {}) if isinstance(data.get("device"), dict) else data
            serial = device_info.get("serialNumber") or device_info.get("serial")
            if serial:
                print(f"[Success] Automatically fetched serial number via DeviceAdmin: {serial}")
                return str(serial).strip()
    except Exception:
        pass

    # 3. Tertiary Endpoint: Setup API
    setup_url = f"https://{ip}/setup/api/v1/device/info"
    try:
        response = HTTP_SESSION.get(setup_url, headers=headers, timeout=5)
        if response.status_code == 200:
            data = response.json()
            serial = data.get("serialNumber") or data.get("serial")
            if serial:
                print(f"[Success] Automatically fetched serial number via Setup API: {serial}")
                return str(serial).strip()
    except Exception:
        pass

    return None


def upload_license(ip: str, file_path: str) -> bool:
    """
    Upload the license capability response (.bin file) to the ctrlX CORE.

    Args:
        ip (str): IP address of the device.
        file_path (str): Local path to the .bin file.

    Returns:
         bool: True if installation succeeded, False otherwise.
    """
    url = f"https://{ip}/license-manager/api/v1/licenses?withChangeReport=true"
    filename = os.path.basename(file_path)
    print(f"[Info] Uploading license '{filename}' to {ip}...")
    try:
        with open(file_path, "rb") as f:
            files = {"file": (filename, f, "application/octet-stream")}
            response = HTTP_SESSION.post(
                url,
                files=files,
                headers={"Accept": "application/json"},
                timeout=60
            )

            if response.status_code in [200, 201, 204]:
                print(f"[Success] License file '{filename}' successfully installed on {ip}.")
                try:
                    report = response.json()
                    if report:
                        print(f"[Info] Change Report: {report}")
                except Exception:
                    pass
                return True
            else:
                print(f"[Error] Upload failed with HTTP {response.status_code}: {response.text}")
                return False
    except requests.exceptions.RequestException as e:
        print(f"[Error] Network error while uploading license to {ip}: {e}")
        return False


def get_single_core_input() -> dict:
    """
    Prompt the user for connection details with default fallbacks.

    Returns:
         dict: Connection dictionary with IP, username, and password.
    """
    print("\n--- Configure ctrlX CORE Connection (Press Enter for Default) ---")
    ip = input("Enter IP Address [192.168.1.1]: ").strip() or "192.168.1.1"
    user = input("Enter Username [boschrexroth]: ").strip() or "boschrexroth"
    password = getpass.getpass("Enter Password [boschrexroth]: ").strip() or "boschrexroth"
    return {"ip": ip, "username": user, "password": password}


def process_device(ip: str, creds: dict) -> None:
    """
    Execute authentication, serial number detection, and file installation.

    Args:
        ip (str): Target IP.
        creds (dict): Target credentials.
    """
    # 1. Authenticate against the core
    if not fetch_bearer_token(ip, creds["username"], creds["password"]):
        print(f"[Error] Skipping {ip} - Authentication failed.")
        return

    # 2. Retrieve Serial Number (automatically or manually)
    serial = fetch_serial_number(ip)
    if not serial:
        print(f"[Warning] Could not fetch serial number automatically from {ip}.")
        try:
            # Smart default using a generic 13-digit placeholder
            serial = input("Please enter the 13-digit Serial Number manually [1234567890123]: ").strip() or "1234567890123"
        except KeyboardInterrupt:
            print("\n[Info] Manual input interrupted. Using default '1234567890123'.")
            serial = "1234567890123"

    # 3. Resolve path to target license file
    license_file = os.path.join(LICENSE_FOLDER, f"{serial}.bin")
    if not os.path.exists(license_file):
        print(f"[Error] License file '{license_file}' not found.")
        print(f"[Skip] Skipping {ip} due to missing license file.")
        return

    # 4. Perform the upload/install action
    process_ok = upload_license(ip, license_file)
    if not process_ok:
        print(f"[Failure] License installation failed for {ip}.")


def main() -> None:
    """
    Run the license automation flow.
    """
    print("==================================================")
    print(" ctrlX CORE License Deployment Automation Script  ")
    print("==================================================")

    # Automatically ensure license directory exists
    if not os.path.exists(LICENSE_FOLDER):
        os.makedirs(LICENSE_FOLDER)
        print(f"[Info] Created license directory: '{LICENSE_FOLDER}'")

    # Load stored connections from .env
    saved_cores = load_cores()

    print("\nSelect Deployment Mode:")
    print("1) Single ctrlX CORE (Ein einzelnes Gerät bespielen)")
    print("2) Multiple ctrlX COREs (Mehrere Geräte aus .env bespielen)")

    try:
        choice = input("Enter choice (1 or 2): ").strip() or "1"
    except KeyboardInterrupt:
        print("\n[Info] Interrupted. Selecting Single mode by default.")
        choice = "1"

    if choice == "1":
        creds = get_single_core_input()
        ip = creds["ip"]

        # Run process
        process_device(ip, creds)

        # Ask to save details if not already present
        if ip not in saved_cores:
            try:
                save_choice = input(
                    f"\nMöchten Sie die Credentials für {ip} in der .env-Datei speichern? (y/n) [n]: "
                ).strip().lower()
            except KeyboardInterrupt:
                save_choice = "n"
            if save_choice in ["y", "yes"]:
                save_core(ip, creds["username"], creds["password"])

    elif choice == "2":
        if not saved_cores:
            print(f"\n[Warning] No saved devices found in '{ENV_FILE}'.")
            print("Please configure your first device connection details:")
            creds = get_single_core_input()
            ip = creds["ip"]
            save_core(ip, creds["username"], creds["password"])
            saved_cores = load_cores()

        print(f"\n[Info] Starting batch license deployment on {len(saved_cores)} device(s)...")
        for ip, creds in saved_cores.items():
            print(f"\n>>> Processing CORE at {ip} <<<")
            process_device(ip, creds)

    else:
        print("[Error] Invalid choice. Aborting.")


if __name__ == "__main__":
    main()
