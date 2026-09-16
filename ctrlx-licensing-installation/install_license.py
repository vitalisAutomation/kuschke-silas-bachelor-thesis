"""
ctrlX CORE License Deployment Automation Script.

This module provides a command-line interface to automate the installation
of license capability responses (.bin files) on Bosch Rexroth ctrlX CORE devices
via the REST API. It supports single or multi-device installation, secure
credentials storage, and automatic 13-digit serial number retrieval.

Source: Gemini 3.6 Flash
Edited by: Silas Kuschke
"""

import getpass
import json
import os
import re
from pathlib import Path

import keyring
import requests
import urllib3

# Disable warnings for self-signed SSL certificates used by ctrlX CORE
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# --- Configuration ---
BASE_DIR = Path(__file__).resolve().parent
CORE_CONFIG_FILE = BASE_DIR / "ctrlx_cores.json"
LICENSE_FOLDER = BASE_DIR / "licenses"
KEYRING_SERVICE = "ctrlx-licensing-installation"

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


def close_session(ip: str) -> None:
    """Close the authenticated REST session and remove its bearer token."""
    try:
        HTTP_SESSION.delete(
            f"https://{ip}/identity-manager/api/v2/auth/token",
            timeout=10,
        )
    except requests.exceptions.RequestException as e:
        print(f"[Warning] Could not close the REST session for {ip}: {e}")
    finally:
        HTTP_SESSION.headers.pop("Authorization", None)


def load_cores() -> dict:
    """
    Loads CORE addresses and usernames from the local JSON configuration.

    Passwords are retrieved from the operating system credential store and are
    never written to the configuration file.
    
    Returns:
        dict: A dictionary containing saved IP configurations and credentials.
    """
    cores = {}
    if not CORE_CONFIG_FILE.exists():
        return cores
    try:
        with CORE_CONFIG_FILE.open("r", encoding="utf-8") as f:
            entries = json.load(f)
        for entry in entries:
            ip = entry["ip"]
            username = entry["username"]
            password = keyring.get_password(KEYRING_SERVICE, ip)
            if password is not None:
                cores[ip] = {"username": username, "password": password}
    except (OSError, json.JSONDecodeError, KeyError, TypeError, keyring.errors.KeyringError) as e:
        print(f"[Warning] Could not load saved CORE configurations: {e}")
    return cores


def save_core(ip: str, user: str, password: str) -> None:
    """
    Saves a CORE username to JSON and its password to the OS credential store.
    """
    try:
        keyring.set_password(KEYRING_SERVICE, ip, password)
        entries = []
        if CORE_CONFIG_FILE.exists():
            with CORE_CONFIG_FILE.open("r", encoding="utf-8") as f:
                entries = json.load(f)
        entries = [entry for entry in entries if entry.get("ip") != ip]
        entries.append({"ip": ip, "username": user})
        with CORE_CONFIG_FILE.open("w", encoding="utf-8") as f:
            json.dump(entries, f, indent=2)
            f.write("\n")
        print(f"[Info] CORE '{ip}' saved; password stored in the OS credential store.")
    except (OSError, json.JSONDecodeError, TypeError, keyring.errors.KeyringError) as e:
        print(f"[Error] Could not save credentials for {ip}: {e}")


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

        serial_str = str(serial).strip('"') if serial is not None else ""
        if re.fullmatch(r"\d{13}", serial_str):
            print(f"[Success] Fetched serial number via Typeplate: {serial_str}")
            return serial_str
        print("[Error] Retrieved device ID is not a 13-digit serial number.")
            
    except requests.exceptions.RequestException as e:
        print(f"[Error] Could not fetch serial number: {e}")
    except (KeyError, AttributeError) as e:
        print(f"[Error] Could not parse serial number from response: {e}")
        
    return None


def upload_license(ip: str, file_path: str) -> bool:
    """
    Uploads a license file and reports the server's change result.

    Returns:
        bool: True when the license was accepted or already active.
    """
    url = f"https://{ip}/license-manager/api/v1/capabilities?withChangeReport=true"
    filename = os.path.basename(file_path)
    print(f"\n[Upload] Uploading '{filename}' via PUT to the correct endpoint...")

    try:
        with open(file_path, "rb") as license_stream:
            files = {"file": (filename, license_stream, "application/octet-stream")}
            headers = {
                "Accept": "application/json",
                "Origin": f"https://{ip}",
                "Referer": f"https://{ip}/package-manager/licenses",
            }
            response = HTTP_SESSION.put(
                url, headers=headers, files=files, timeout=60
            )

        if response.status_code == 400:
            try:
                error_data = response.json()
                if not isinstance(error_data, dict):
                    return False
                already_processed = (
                    error_data.get("detailedDiagnosisCode") == "0C7A0202"
                    or "already processed" in error_data.get("dynamicDescription", "").lower()
                )
                if already_processed:
                    print(f"[SUCCESS] License '{filename}' is already active.")
                    return True
            except (AttributeError, TypeError, ValueError):
                pass

        if response.status_code not in [200, 201, 204]:
            print(f"[Error] Server rejected the upload with status {response.status_code}.")
            try:
                error_data = response.json()
                reason = (
                    error_data.get("dynamicDescription", response.text)
                    if isinstance(error_data, dict)
                    else response.text
                )
            except (AttributeError, TypeError, ValueError):
                reason = response.text
            print(f"[Diag] Reason: {reason}")
            return False

        print(f"[SUCCESS] License file '{filename}' was successfully processed.")
        try:
            change_report = response.json()
            added_licenses = (
                change_report.get("added", [])
                if isinstance(change_report, dict)
                else []
            )
            if added_licenses:
                print("\n[Report] New licenses added to the device:")
                for license_info in added_licenses:
                    license_name = (
                        license_info.get("name")
                        or license_info.get("id")
                        or "Unknown License"
                    )
                    print(f"  -> + {license_name}")
            else:
                print("[Report] No new licenses were added (already up-to-date).")
        except (AttributeError, TypeError, ValueError):
            print(f"[Diag] Server response (not JSON): {response.text}")
        return True
    except (OSError, requests.exceptions.RequestException) as e:
        print(f"[Error] Could not upload license file: {e}")
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
    password = getpass.getpass("Enter Password: ").strip()
    return {"ip": ip, "username": user, "password": password}


def process_device(ip: str, creds: dict) -> bool:
    """Run installation and verification for one CORE and return its result."""
    try:
        if not fetch_bearer_token(ip, creds["username"], creds["password"]):
            return False
        serial = fetch_serial_number(ip)
        if not serial:
            print("[Fatal] Could not determine device serial number. Aborting.")
            return False
        license_file = LICENSE_FOLDER / f"{serial}.bin"
        if not license_file.is_file():
            print(f"[Error] License file '{license_file}' not found.")
            return False
        if not upload_license(ip, str(license_file)):
            print(f"[Failure] License installation for {ip} reported an error.")
            return False
        if not verify_license_installation(ip, serial):
            print(f"[Failure] License verification for {ip} failed.")
            return False
        print(f"[Finished] Licensing process for {ip} completed successfully.")
        return True
    finally:
        close_session(ip)


def main():
    """
    Main execution flow.
    """
    print("=" * 50)
    print(" ctrlX CORE License Deployment Automation Script")
    print("=" * 50)

    if not LICENSE_FOLDER.exists():
        LICENSE_FOLDER.mkdir(parents=True)
        print(f"[Info] Created license directory: '{LICENSE_FOLDER}'")

    saved_cores = load_cores()

    print("\nSelect Deployment Mode:")
    print("1) Single ctrlX CORE")
    print("2) Multiple ctrlX COREs from saved configuration")

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
                print(f"\n[Warning] No saved devices in '{CORE_CONFIG_FILE}'. Add one first.")
                return
            results = {}
            for ip, creds in saved_cores.items():
                print(f"\n>>> Processing CORE at {ip} <<<")
                results[ip] = process_device(ip, creds)
            print("\nDeployment summary:")
            for ip, successful in results.items():
                status = "SUCCESS" if successful else "FAILED"
                print(f"  {ip}: {status}")
        else:
            print("[Error] Invalid choice.")
    except KeyboardInterrupt:
        print("\n[Info] Operation cancelled by user.")


if __name__ == "__main__":
    main()
