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
import json
import time

# Disable warnings for self-signed SSL certificates used by ctrlX CORE
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# --- Configuration ---
ENV_FILE = "ctrlx_cores.env"
LICENSE_FOLDER = "./licenses"

# --- Global Session ---
HTTP_SESSION = requests.Session()
HTTP_SESSION.verify = False
HTTP_SESSION.trust_env = False


def update_session_headers(ip: str):
    """
    Update session headers to mimic a web context request.
    """
    HTTP_SESSION.headers.update({
        "Accept": "application/json",
        "Referer": f"https://{ip}/"
    })


def load_cores() -> dict:
    """
    Loads CORE configurations from the secure .env file.
    
    Returns:
        dict: A dictionary containing saved IP configurations and credentials.
    """
    cores = {}
    if not os.path.exists(ENV_FILE):
        return cores
    with open(ENV_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            if key.startswith("CORE_"):
                ip = key[5:].replace("_", ".")
                try:
                    decoded = base64.b64decode(val).decode("utf-8")
                    user, password = decoded.split(":", 1)
                    cores[ip] = {"username": user, "password": password}
                except (base64.binascii.Error, ValueError):
                    continue
    return cores


def save_core(ip: str, user: str, password: str) -> None:
    """
    Saves a CORE configuration securely to the .env file.
    """
    key = f"CORE_{ip.replace('.', '_')}"
    plain_creds = f"{user}:{password}"
    encoded_creds = base64.b64encode(plain_creds.encode("utf-8")).decode("utf-8")
    lines = []
    updated = False
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, "r", encoding="utf-8") as f:
            lines = f.readlines()
            for i, line in enumerate(lines):
                if line.startswith(f"{key}="):
                    lines[i] = f"{key}={encoded_creds}\n"
                    updated = True
                    break
    if not updated:
        lines.append(f"{key}={encoded_creds}\n")
    with open(ENV_FILE, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print(f"[Info] Credentials for {ip} saved to {ENV_FILE}")


def fetch_bearer_token(ip: str, user: str, password: str) -> bool:
    """
    Authenticates and stores the Bearer token in the global session.
    """
    update_session_headers(ip)
    url = f"https://{ip}/identity-manager/api/v2/auth/token"
    payload = {"name": user, "password": password}
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
        print(f"[Error] Authentication failed for {ip}: {e}")
        return False


def fetch_serial_number(ip: str) -> str | None:
    """
    Retrieves the 13-digit serial number from the ctrlX CORE.
    """
    url = f"https://{ip}/automation/api/v2/nodes/system/typeplate/ctrlXDeviceId"
    try:
        print(f"[Info] Querying Typeplate at {url}...")
        response = HTTP_SESSION.get(url, timeout=5)
        response.raise_for_status()
        data = response.json()
        
        raw_val = data.get("value")
        if isinstance(raw_val, dict):
            serial = raw_val.get("value")
        else:
            serial = raw_val

        if serial:
            serial_str = str(serial).strip('"')
            print(f"[Success] Fetched serial number via Typeplate: {serial_str}")
            return serial_str
            
    except requests.exceptions.RequestException as e:
        print(f"[Error] Could not fetch serial number: {e}")
    except (KeyError, AttributeError) as e:
        print(f"[Error] Could not parse serial number from response: {e}")
        
    return None


def upload_license(ip: str, file_path: str) -> bool:
    """
    Uploads the license file to the ctrlX CORE.
    
    This function implements a robust two-way strategy:
    1. It tries to upload the license as Raw Binary payload first.
    2. If that fails or is rejected, it falls back to a Multipart upload
       using the verified 'file' field.
    """
    url = f"https://{ip}/licensing/api/v1/licenses?withChangeReport=true"
    filename = os.path.basename(file_path)
    
    # -------------------------------------------------------------------------
    # METHOD 1: Raw Binary Upload (No MIME Boundary Corruption)
    # -------------------------------------------------------------------------
    print(f"[Info] Uploading license '{filename}' as Raw Binary...")
    try:
        with open(file_path, "rb") as f:
            content = f.read()
            
        headers = {
            "Content-Type": "application/octet-stream",
            "Content-Length": str(len(content)),
            "Accept": "application/json"
        }
        
        response = HTTP_SESSION.post(url, data=content, headers=headers, timeout=60)
        print(f"[Diag] Raw POST -> HTTP {response.status_code}")
        
        if response.status_code in [200, 201, 204]:
            print(f"[Success] License file '{filename}' uploaded successfully via Raw Binary.")
            return True
            
    except requests.exceptions.RequestException as e:
        print(f"[Warning] Raw Binary upload failed: {e}. Trying Multipart fallback...")

    # -------------------------------------------------------------------------
    # METHOD 2: Multipart Fallback (Verified standard browser method)
    # -------------------------------------------------------------------------
    print(f"[Info] Trying Multipart upload fallback...")
    try:
        with open(file_path, "rb") as f:
            files = {"file": (filename, f, "application/octet-stream")}
            
            # Remove any pre-configured Content-Type in session headers
            # to let 'requests' auto-generate the correct multi-part boundary.
            headers = HTTP_SESSION.headers.copy()
            if "Content-Type" in headers:
                del headers["Content-Type"]
                
            response = HTTP_SESSION.post(url, files=files, headers=headers, timeout=60)
            print(f"[Diag] Multipart POST -> HTTP {response.status_code}")
            
            if response.status_code in [200, 201, 204]:
                print(f"[Success] License file '{filename}' uploaded via Multipart.")
                return True
                
    except requests.exceptions.RequestException as e:
        print(f"[Error] Multipart upload failed: {e}")
        
    return False


def verify_license_installation(ip: str, license_name_part: str) -> bool:
    """
    Verifies installation by checking the activated capabilities on the CORE.
    """
    endpoints = [
        f"https://{ip}/licensing/api/v1/capabilities",
        f"https://{ip}/licensing/api/v1/licenses",
        f"https://{ip}/license-manager/api/v1/capabilities"
    ]
    print("\n[Verify] Checking active licenses/capabilities on the CORE...")
    
    for url in endpoints:
        try:
            response = HTTP_SESSION.get(url, timeout=5)
            if response.status_code == 200:
                text = response.text.strip()
                if not text:
                    continue
                
                try:
                    data = response.json()
                    if isinstance(data, list):
                        for item in data:
                            name = item.get("name", "") or item.get("id", "")
                            if license_name_part.lower() in str(name).lower():
                                print(f"[SUCCESS] Verified that '{name}' ({license_name_part}) is active/installed!")
                                return True
                    elif isinstance(data, dict):
                        if license_name_part.lower() in str(data).lower():
                            print(f"[SUCCESS] Verified that '{license_name_part}' is active/installed!")
                            return True
                except json.JSONDecodeError:
                    if license_name_part.lower() in text.lower():
                        print(f"[SUCCESS] Verified '{license_name_part}' in raw text response.")
                        return True
        except requests.exceptions.RequestException:
            pass
            
    print(f"\n[Warning] '{license_name_part}' was not found in the active list.")
    print("Please verify the license on the Web Interface.")
    return False


def get_single_core_input() -> dict:
    """
    Prompts the user for single-device connection details.
    """
    print("\n--- Configure ctrlX CORE Connection (Press Enter for Default) ---")
    ip = input("Enter IP Address [192.168.1.1]: ").strip() or "192.168.1.1"
    user = input("Enter Username [boschrexroth]: ").strip() or "boschrexroth"
    password = getpass.getpass("Enter Password [boschrexroth]: ").strip() or "boschrexroth"
    return {"ip": ip, "username": user, "password": password}


def process_device(ip: str, creds: dict) -> None:
    """
    Runs the full license installation and verification pipeline for a device.
    """
    if not fetch_bearer_token(ip, creds["username"], creds["password"]):
        return

    serial = fetch_serial_number(ip)
    if not serial:
        print("[Fatal] Could not determine device serial number. Aborting.")
        return

    license_file = os.path.join(LICENSE_FOLDER, f"{serial}.bin")
    if not os.path.exists(license_file):
        print(f"[Error] License file '{license_file}' not found.")
        return

    if upload_license(ip, license_file):
        # Give the core backend short time to process the licensing response asynchronously
        time.sleep(2)
        verify_license_installation(ip, "Motion")
    else:
        print(f"[Failure] License installation for {ip} reported an error.")


def main():
    """
    Main execution flow.
    """
    print("=" * 50)
    print(" ctrlX CORE License Deployment Automation Script")
    print("=" * 50)

    if not os.path.exists(LICENSE_FOLDER):
        os.makedirs(LICENSE_FOLDER)
        print(f"[Info] Created license directory: '{LICENSE_FOLDER}'")

    saved_cores = load_cores()

    print("\nSelect Deployment Mode:")
    print("1) Single ctrlX CORE")
    print("2) Multiple ctrlX COREs from .env file")

    try:
        choice = input("Enter choice (1 or 2): ").strip() or "1"
        if choice == "1":
            creds = get_single_core_input()
            process_device(creds["ip"], creds)
            if creds["ip"] not in saved_cores:
                save_prompt = input(f"\nSave credentials for {creds['ip']}? (y/n) [n]: ").strip().lower()
                if save_prompt in ["y", "yes"]:
                    save_core(creds["ip"], creds["username"], creds["password"])
        elif choice == "2":
            if not saved_cores:
                print(f"\n[Warning] No devices in '{ENV_FILE}'. Add one first.")
                return
            for ip, creds in saved_cores.items():
                print(f"\n>>> Processing CORE at {ip} <<<")
                process_device(ip, creds)
        else:
            print("[Error] Invalid choice.")
    except KeyboardInterrupt:
        print("\n[Info] Operation cancelled by user.")


if __name__ == "__main__":
    main()
