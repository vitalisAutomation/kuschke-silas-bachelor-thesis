"""
ctrlX CORE App License Deployment Automation Script.

This module provides a robust command-line interface to automate the upload
and management of ctrlX App licenses (capability responses) on Bosch Rexroth
ctrlX CORE devices via the License Manager REST API.
"""

import os
import getpass
import requests
import urllib3

# Disable warnings for self-signed SSL certificates used by ctrlX CORE
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Global configuration and HTTP session initialization
CTRLX_CONFIG = {}
HTTP_SESSION = requests.Session()
HTTP_SESSION.verify = False
HTTP_SESSION.trust_env = False  # Bypass system proxies for local communication


def configure_connection() -> None:
    """
    Prompt the user for ctrlX CORE connection details.

    Applies default connection parameters (IP: '192.168.1.1', User/Password:
    'boschrexroth') upon pressing Enter. Masking is applied to the password.
    """
    print("\n--- Configure ctrlX CORE Connection (Press Enter for Default) ---")
    ip_in = input("Enter IP Address [192.168.1.1]: ").strip()
    CTRLX_CONFIG['ip'] = ip_in or "192.168.1.1"

    user_in = input("Enter Username [boschrexroth]: ").strip()
    CTRLX_CONFIG['username'] = user_in or "boschrexroth"

    pass_in = getpass.getpass("Enter Password [boschrexroth]: ").strip()
    CTRLX_CONFIG['password'] = pass_in or "boschrexroth"


def fetch_bearer_token() -> bool:
    """
    Authenticate against the Identity Manager of the ctrlX CORE.

    Retrieves a valid OAuth2 Bearer token and updates the global HTTP session
    headers for all subsequent API requests.

    :return: True if authentication succeeded, False otherwise.
    :rtype: bool
    """
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/identity-manager/api/v2/auth/token"
    payload = {
        "name": CTRLX_CONFIG["username"],
        "password": CTRLX_CONFIG["password"]
    }

    try:
        print(f"[Auth] Connecting to ctrlX CORE at {ip}...")
        response = HTTP_SESSION.post(url, json=payload, timeout=10)
        response.raise_for_status()

        token = response.json().get("access_token")
        if not token:
            print("[Error] 'access_token' not found in response.")
            return False

        HTTP_SESSION.headers.update({"Authorization": f"Bearer {token}"})
        print("[Success] Connected and authenticated successfully.")
        return True

    except requests.exceptions.RequestException as e:
        print(f"[Error] Connection or authentication failed: {e}")
        return False


def get_serial_number() -> str | None:
    """
    Retrieve the unique serial number of the ctrlX CORE.

    Queries the electronic typeplate API of the controller and extracts
    the hardware serial number.

    :return: The resolved serial number string, or None if the query fails.
    :rtype: str or None
    """
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/system/api/v1/typeplate"

    try:
        response = HTTP_SESSION.get(url, timeout=5)
        response.raise_for_status()
        data = response.json()

        # Extract the serial number from the typeplate data
        serial = (
            data.get("serialNumber")
            or data.get("serial_number")
            or data.get("serial")
        )
        return str(serial) if serial else None

    except requests.exceptions.RequestException as e:
        print(f"[Warning] Could not read serial number from typeplate: {e}")
        return None


def upload_license(license_path: str) -> bool:
    """
    Upload a ctrlX App license (.bin) to the License Manager.

    Performs pre-flight validation by matching the filename (serial number)
    against the controller's actual serial number. Uploads the raw binary
    content using the REST API.

    :param license_path: The local file path to the license (.bin) file.
    :type license_path: str
    :return: True if the license was successfully uploaded, False otherwise.
    :rtype: bool
    """
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/license-manager/api/v1/capabilities?withChangeReport=true"

    filename = os.path.basename(license_path)
    # Extract expected serial number from filename (e.g., '123456789' from '123456789.bin')
    serial_from_file = os.path.splitext(filename)[0]

    # --- 1. Pre-flight Check: Is this license meant for this CORE? ---
    print("\n[Sanity Check] Verifying serial number compatibility...")
    actual_serial = get_serial_number()

    if not actual_serial:
        print("[Error] Aborting upload: Could not retrieve controller's serial number.")
        return False

    print(f"[Check] Controller Serial: {actual_serial}")
    print(f"[Check] License File Serial: {serial_from_file}")

    if actual_serial != serial_from_file:
        print("\n[SERIAL_MISMATCH] Warning: Operational risk!")
        print(" -> The license file is configured for a different controller.")
        override = input("[Prompt] Override serial mismatch and upload anyway? (y/N): ").strip().lower()
        if override != 'y':
            print("[Info] Upload aborted by user.")
            return False

    # --- 2. Upload raw binary file content ---
    print(f"\n[Info] Uploading license '{filename}' to License Manager...")
    try:
        with open(license_path, "rb") as f:
            file_content = f.read()

        headers = {
            "Content-Type": "application/octet-stream",
            "Accept": "application/json"
        }

        # PUT request uploads the license binary data directly
        response = HTTP_SESSION.put(url, data=file_content, headers=headers, timeout=30)

        if response.status_code == 200:
            print("[Success] License uploaded successfully.")
            # Print the change report returned by the API
            try:
                report = response.json()
                added = report.get("added", [])
                removed = report.get("removed", [])
                if added:
                    print("\nAdded capabilities/licenses:")
                    for cap in added:
                        print(f" - {cap.get('name')} (v{cap.get('version')})")
                if removed:
                    print("\nRemoved capabilities/licenses:")
                    for cap in removed:
                        print(f" - {cap.get('name')} (v{cap.get('version')})")
            except ValueError:
                pass
            return True
        else:
            print(f"[Error] Upload failed with status {response.status_code}: {response.text}")
            return False

    except requests.exceptions.RequestException as e:
        print(f"[Error] Network error during license upload: {e}")
        return False


def main() -> None:
    """
    Execute the automated license upload workflow.

    Requests connection data, authenticates, validates file availability,
    runs safety checks against controller serial numbers, and deploys the license.
    """
    print("=== ctrlX CORE App License Deployment Script ===")
    configure_connection()

    license_path = ""
    while not license_path:
        path_in = input("Enter path to .bin license file: ").strip()
        if not path_in:
            print("[Error] License file path is required.")
        elif not os.path.exists(path_in):
            print(f"[Error] File does not exist at: '{path_in}'. Please try again.")
        elif not path_in.endswith(".bin"):
            print("[Error] File must be a '.bin' license file.")
        else:
            license_path = path_in

    if not fetch_bearer_token():
        return

    upload_ok = upload_license(license_path)

    if upload_ok:
        print("\nDeployment completed successfully.")
    else:
        print("\nDeployment failed.")


if __name__ == "__main__":
    main()
