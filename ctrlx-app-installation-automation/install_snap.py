#!/usr/bin/env python3
"""
Python script to install a Snap App on a Bosch Rexroth ctrlX CORE via REST API.

This script runs fully interactively. It prompts the user for connection
details, automatically applying defaults upon pressing Enter, while requiring
a valid path to a local .snap package.

The script switches the controller's Scheduler to SERVICE mode to allow
installation, uploads/installs the snap, and returns the Scheduler back to
OPERATING mode.

All docstrings in this module conform to the Sphinx documentation standard.
"""

import os
import time
import getpass
import requests
import urllib3

# Disable warnings for self-signed SSL certificates, which are common on ctrlX.
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Global session object to reuse connections and authentication headers.
HTTP_SESSION = requests.Session()
HTTP_SESSION.verify = False  # Do not verify SSL certificate
HTTP_SESSION.trust_env = False  # Bypass system-level proxies


def authenticate(ip, username, password) -> bool:
    """
    Authenticate against the ctrlX CORE Identity Manager to get a bearer token.

    :param ip: The IP address of the ctrlX CORE.
    :type ip: str
    :param username: The username for authentication.
    :type username: str
    :param password: The password for the user.
    :type password: str
    :return: True if authentication is successful, False otherwise.
    :rtype: bool
    """
    url = f"https://{ip}/identity-manager/api/v2/auth/token"
    payload = {"name": username, "password": password}
    try:
        print(f"[Auth] Connecting to ctrlX CORE at {ip}...")
        response = HTTP_SESSION.post(url, json=payload, timeout=10)
        response.raise_for_status()
        token = response.json().get("access_token")
        if token:
            HTTP_SESSION.headers.update({"Authorization": f"Bearer {token}"})
            print("[Success] Authentication successful.")
            return True
        print("[Error] 'access_token' not found in authentication response.")
        return False
    except requests.exceptions.RequestException as e:
        print(f"[Error] Authentication failed: {e}")
        return False


def get_controller_info(ip) -> tuple[str, str]:
    """
    Read the electronic typeplate to determine the hardware model and architecture.

    :param ip: The IP address of the ctrlX CORE.
    :type ip: str
    :return: A tuple containing the determined model name and the expected
             architecture ('arm', 'amd64', or 'unknown').
    :rtype: tuple[str, str]
    """
    url = f"https://{ip}/system/api/v1/typeplate"
    try:
        response = HTTP_SESSION.get(url, timeout=5)
        response.raise_for_status()
        data = response.json()
        json_str = str(data).upper()

        model, arch = "Unknown", "unknown"
        if "X2" in json_str:
            model, arch = "ctrlX CORE X2", "arm"
        elif "X3" in json_str:
            model, arch = "ctrlX CORE X3", "arm"
        elif "X5" in json_str:
            model, arch = "ctrlX CORE X5", "amd64"
        elif "X7" in json_str:
            model, arch = "ctrlX CORE X7", "amd64"
        elif "VIRTUAL" in json_str or "VCORE" in json_str:
            model, arch = "ctrlX COREvirtual", "amd64"

        specific_name = data.get("typeName") or data.get("component")
        if specific_name:
            model = f"{specific_name} ({model})"

        return model, arch
    except requests.exceptions.RequestException as e:
        print(f"[Warning] Could not read typeplate: {e}")
        return "Unknown (Read Error)", "unknown"


def check_architecture_compatibility(
        snap_path, expected_arch) -> bool:
    """
    Check if the Snap filename is compatible with the controller's architecture.

    :param snap_path: The file path to the .snap package.
    :type snap_path: str
    :param expected_arch: The expected architecture ('arm' or 'amd64').
    :type expected_arch: str
    :return: True if compatible, False on mismatch.
    :rtype: bool
    """
    if expected_arch == "unknown":
        print("[Warning] Target architecture is unknown. Skipping check.")
        return True

    filename = os.path.basename(snap_path).lower()
    is_snap_arm = any(x in filename for x in ["arm64", "armhf"])
    is_snap_amd64 = any(x in filename for x in ["amd64", "x86_64"])
    is_snap_all = "_all.snap" in filename

    if is_snap_all:
        print("[Check] Snap is architecture-independent ('all'). OK.")
        return True

    mismatch = False
    if expected_arch == "arm" and is_snap_amd64 and not is_snap_arm:
        mismatch = True
        print("\n[ARCH_MISMATCH] Error: Security and operational risk!")
        print(" -> Controller is ARM-based (e.g., X2/X3).")
        print(f" -> Snap filename '{filename}' implies an AMD64 build.")
    elif expected_arch == "amd64" and is_snap_arm and not is_snap_amd64:
        mismatch = True
        print("\n[ARCH_MISMATCH] Error: Security and operational risk!")
        print(" -> Controller is AMD64-based (e.g., X5/X7, Virtual).")
        print(f" -> Snap filename '{filename}' implies an ARM build.")

    if mismatch:
        # Prompt user if they want to override the safety block
        override = input(
            "[Prompt] Override architecture mismatch? (y/N): "
        ).strip().lower()
        if override == "y":
            print("[Info] Proceeding with forced installation.")
            return True
        return False

    print("[Check] Architecture compatibility check passed.")
    return True


def get_scheduler_state(ip) -> str | None:
    """
    Retrieve the current Scheduler state from the Data Layer.

    Expected return states are SERVICE, SETUP, or OPERATING.

    :param ip: The IP address of the ctrlX CORE.
    :type ip: str
    :return: The current state as a string, or None if the request fails.
    :rtype: str | None
    """
    url = f"https://{ip}/automation/api/v2/nodes/scheduler/admin/state"
    try:
        response = HTTP_SESSION.get(url, timeout=5)
        response.raise_for_status()
        raw_val = response.json().get("value")
        if isinstance(raw_val, dict):
            return raw_val.get("state", "UNKNOWN").upper()
        return str(raw_val).upper()
    except requests.exceptions.RequestException as e:
        print(f"[Error] Failed to retrieve system state: {e}")
        return None


def set_scheduler_state(ip, target_state) -> bool:
    """
    Request a change of the Scheduler state (SERVICE, SETUP, or OPERATING).

    :param ip: The IP address of the ctrlX CORE.
    :type ip: str
    :param target_state: The desired state: 'SERVICE', 'SETUP', or 'OPERATING'.
    :type target_state: str
    :return: True if the request was sent successfully, False otherwise.
    :rtype: bool
    """
    url = f"https://{ip}/automation/api/v2/nodes/scheduler/admin/state"
    # The ctrlX Data Layer expects a structured value object
    payload = {
        "type": "string",
        "value": {
            "state": target_state
        }
    }
    try:
        print(f"[Info] Requesting switch to Scheduler state '{target_state}'...")
        response = HTTP_SESSION.put(url, json=payload, timeout=10)
        response.raise_for_status()
        return True
    except requests.exceptions.RequestException as e:
        print(f"[Error] Failed to switch Scheduler to '{target_state}': {e}")
        return False


def wait_for_scheduler_state(ip, target_state, timeout_seconds=60) -> bool:
    """
    Poll the Scheduler state until it reaches the target state or times out.

    :param ip: The IP address of the ctrlX CORE.
    :type ip: str
    :param target_state: The desired state (e.g. 'SERVICE' or 'OPERATING').
    :type target_state: str
    :param timeout_seconds: Maximum time to wait in seconds.
    :type timeout_seconds: int
    :return: True if the target state was reached, False on timeout.
    :rtype: bool
    """
    start_time = time.time()
    print(f"[Info] Waiting for Scheduler to enter '{target_state}' mode...")
    while time.time() - start_time < timeout_seconds:
        current_state = get_scheduler_state(ip)
        if current_state == target_state:
            print(f"[Success] Scheduler is now in '{target_state}' state.")
            return True
        time.sleep(2)
    print(f"[Error] Timeout expired while waiting for '{target_state}' state.")
    return False


def install_snap(ip, snap_path) -> bool:
    """
    Upload and install the Snap package on the controller.

    The POST request is blocking and only returns after the installation is
    complete, hence the long timeout.

    :param ip: The IP address of the ctrlX CORE.
    :type ip: str
    :param snap_path: The local file path to the .snap package.
    :type snap_path: str
    :return: True if installation was successful, False otherwise.
    :rtype: bool
    """
    url = f"https://{ip}/system/api/v1/apps"
    filename = os.path.basename(snap_path)

    if not os.path.exists(snap_path):
        print(f"[Error] Snap file not found at path: {snap_path}")
        return False

    print(f"[Info] Uploading and installing '{filename}' (Timeout: 5 min)...")
    try:
        with open(snap_path, "rb") as f:
            files = {"file": (filename, f, "application/octet-stream")}
            response = HTTP_SESSION.post(url, files=files, timeout=300)

            if response.status_code in [200, 201, 204]:
                print("[Success] App installation completed successfully.")
                return True
            else:
                print(f"[Error] Installation failed with status code "
                      f"{response.status_code}: {response.text}")
                return False
    except requests.exceptions.RequestException as e:
        print(f"[Error] Network error during snap upload: {e}")
        return False


def main():
    """
    Main entry point for the script. Collects user input interactively
    and orchestrates the entire pre-check, switch, and upload flow.
    """
    print("=== ctrlX CORE App (Snap) Deployment Script ===")

    # Interactive connection details with fallback defaults
    ip_in = input("Enter ctrlX IP Address [192.168.1.1]: ").strip()
    ip = ip_in or "192.168.1.1"

    user_in = input("Enter Username [boschrexroth]: ").strip()
    username = user_in or "boschrexroth"

    pass_in = getpass.getpass("Enter Password [boschrexroth]: ").strip()
    password = pass_in or "boschrexroth"

    # Strict path input loop (no default allowed)
    snap_path = ""
    while not snap_path:
        path_in = input("Enter path to .snap file: ").strip()
        if not path_in:
            print("[Error] Snap file path is required.")
            continue
        if not os.path.exists(path_in):
            print(f"[Error] File does not exist at: '{path_in}'. "
                  f"Please try again.")
            continue
        snap_path = path_in

    # 1. Authenticate
    if not authenticate(ip, username, password):
        return

    # 2. Hardware and Architecture Check
    print("\n[Sanity Check] Starting pre-flight checks...")
    model, arch = get_controller_info(ip)
    print(f"[Sanity Check] Detected hardware: {model} "
          f"(Expected architecture: {arch.upper()})")

    if not check_architecture_compatibility(snap_path, arch):
        print("[Error] Aborting installation due to architecture mismatch.")
        return
    print("[Sanity Check] OK. Proceeding with installation.\n")

    # 3. Retrieve and change scheduler state to SERVICE
    initial_state = get_scheduler_state(ip)
    if not initial_state:
        return
    print(f"[Info] Current Scheduler state before installation: "
          f"'{initial_state}'")

    switched_to_service = False
    # If scheduler is running in OPERATING (run) or SETUP mode, switch to SERVICE
    if initial_state in ["OPERATING", "SETUP", "RUN"]:
        if not (set_scheduler_state(ip, "SERVICE") and
                wait_for_scheduler_state(ip, "SERVICE")):
            return
        switched_to_service = True
    elif initial_state != "SERVICE":
        print(f"[Error] Scheduler is in an unsupported state: '{initial_state}'. "
              f"Aborting.")
        return

    # 4. Upload and install the app
    install_ok = install_snap(ip, snap_path)

    # 5. Restore Scheduler state to OPERATING if we changed it
    if switched_to_service:
        print("[Info] Restoring system back to OPERATING mode.")
        if not (set_scheduler_state(ip, "OPERATING") and
                wait_for_scheduler_state(ip, "OPERATING")):
            print("[Warning] Failed to switch Scheduler back to OPERATING.")

    if install_ok:
        print("\nDeployment completed successfully.")
    else:
        print("\nDeployment failed.")


if __name__ == "__main__":
    main()
