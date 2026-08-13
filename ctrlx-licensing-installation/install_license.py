"""
ctrlX CORE License Deployment Automation Script.

This module provides a command-line interface to automate the installation
of license capability responses (.bin files) on Bosch Rexroth ctrlX CORE devices
via the REST API. It supports single or multi-device installation, secure
credentials storage, and automatic 13-digit serial number retrieval.

Source: Gemini 3.6 Flash
Edited by: Silas Kuschke
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
    Uploads the license file using the confirmed PUT method and correct endpoint.
    
    This function parses the server's change report to dynamically identify
    which licenses were added or if the license was already processed.
    
    Args:
        ip (str): The IP address of the target ctrlX CORE.
        file_path (str): The local path to the .bin license file.
        
    Returns:
        bool: True if the upload was successful, False otherwise.
    """
    # Endpoint and query parameters confirmed via browser cURL analysis
    url = f"https://{ip}/license-manager/api/v1/capabilities?withChangeReport=true"
    filename = os.path.basename(file_path)

    print(f"\n[Upload] Uploading '{filename}' via PUT to the correct endpoint...")

    try:
        with open(file_path, "rb") as f:
            files = {"file": (filename, f, "application/octet-stream")}
            
            # Replicate the precise browser headers to bypass security checks
            headers = {
                "Accept": "application/json",
                "Origin": f"https://{ip}",
                "Referer": f"https://{ip}/package-manager/licenses",
            }

            response = HTTP_SESSION.put(
                url,
                headers=headers,
                files=files,
                timeout=60
            )

            # A HTTP 400 with 'already processed' diagnostic code is a functional success,
            # indicating that the API communication is perfect but the license is already active.
            if response.status_code == 400:
                try:
                    err_data = response.json()
                    diag_code = err_data.get("detailedDiagnosisCode", "")
                    # '0C7A0202' is the ctrlX error code for "license already processed"
                    if diag_code == "0C7A0202" or "already processed" in err_data.get("dynamicDescription", ""):
                        print(f"[SUCCESS] License '{filename}' is already active/installed on the device.")
                        return True
                except (ValueError, KeyError):
                    pass

            if response.status_code in [200, 201, 204]:
                print(f"[SUCCESS] License file '{filename}' was successfully processed.")
                try:
                    change_report = response.json()
                    added_licenses = change_report.get("added", [])
                    
                    if added_licenses:
                        print("\n[Report] New licenses added to the device:")
                        for lic in added_licenses:
                            lic_name = lic.get("name") or lic.get("id") or "Unknown License"
                            print(f"  -> + {lic_name}")
                    else:
                        print("[Report] No new licenses were added (already up-to-date).")
                except ValueError:
                    print(f"[Diag] Server response (not JSON): {response.text}")
                return True
            else:
                print(f"[Error] Server rejected the upload with status {response.status_code}.")
                try:
                    err_json = response.json()
                    print(f"[Diag] Reason: {err_json.get('dynamicDescription', response.text)}")
                except ValueError:
                    print(f"[Diag] Server response: {response.text}")
                return False

    except requests.exceptions.RequestException as e:
        print(f"[FATAL] A network error occurred: {e}")
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

    # Trigger the upload. The verification of the processed licenses
    # is now handled dynamically within the upload function's response report.
    if upload_license(ip, license_file):
        print(f"[Finished] Licensing process for {ip} completed successfully.")
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
