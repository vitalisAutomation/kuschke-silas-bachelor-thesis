#!/usr/bin/env python3
"""
Python script to install a Snap App on a Bosch Rexroth ctrlX CORE via REST API.

This script provides a command-line interface to automate the installation of
a Snap package (.snap file) onto a ctrlX CORE controller. It includes a
crucial pre-flight check to ensure the architecture of the Snap package
(ARM64/AMD64) is compatible with the target controller's hardware model
(e.g., X2/X3 vs. X5/X7).

The process involves:
1. Authenticating with the controller.
2. Reading the controller's typeplate to determine its hardware architecture.
3. Verifying the Snap file's architecture against the controller's.
4. Switching the controller to "setup" mode if it's in "run" mode.
5. Uploading and installing the Snap package.
6. Switching the controller back to its original mode.

:Example:
    python install_snap.py \\
        --ip 192.168.1.1 \\
        --user boschrexroth \\
        --password mysecret \\
        --file ./path/to/my-app_1.0.0_arm64.snap
"""

import os
import time
import argparse
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
        snap_path, expected_arch, force=False) -> bool:
    """
    Check if the Snap filename is compatible with the controller's architecture.

    :param snap_path: The file path to the .snap package.
    :type snap_path: str
    :param expected_arch: The expected architecture ('arm' or 'amd64').
    :type expected_arch: str
    :param force: If True, bypasses the check and returns True.
    :type force: bool
    :return: True if compatible or forced, False on mismatch.
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
        if force:
            print(" -> [!] Warning ignored as '--force' is active.")
            return True
        return False

    print("[Check] Architecture compatibility check passed.")
    return True


def get_system_state(ip) -> str | None:
    """
    Retrieve the current operating state of the system ('setup' or 'run').

    :param ip: The IP address of the ctrlX CORE.
    :type ip: str
    :return: The current state as a string, or None if the request fails.
    :rtype: str | None
    """
    url = f"https://{ip}/system/api/v1/state"
    try:
        response = HTTP_SESSION.get(url, timeout=5)
        response.raise_for_status()
        return response.json().get("state")
    except requests.exceptions.RequestException as e:
        print(f"[Error] Failed to retrieve system state: {e}")
        return None


def set_system_state(ip, target_state) -> bool:
    """
    Request a change of the system's operating state.

    :param ip: The IP address of the ctrlX CORE.
    :type ip: str
    :param target_state: The desired state, either 'setup' or 'run'.
    :type target_state: str
    :return: True if the request was sent successfully, False otherwise.
    :rtype: bool
    """
    url = f"https://{ip}/system/api/v1/state"
    payload = {"state": target_state}
    try:
        print(f"[Info] Requesting switch to '{target_state}' mode...")
        response = HTTP_SESSION.put(url, json=payload, timeout=10)
        response.raise_for_status()
        return True
    except requests.exceptions.RequestException as e:
        print(f"[Error] Failed to switch system state to '{target_state}': {e}")
        return False


def wait_for_state(ip, target_state, timeout_seconds=60) -> bool:
    """
    Poll the system state until it reaches the target state or a timeout occurs.

    :param ip: The IP address of the ctrlX CORE.
    :type ip: str
    :param target_state: The desired state to wait for ('setup' or 'run').
    :type target_state: str
    :param timeout_seconds: Maximum time to wait in seconds.
    :type timeout_seconds: int
    :return: True if the target state was reached, False on timeout.
    :rtype: bool
    """
    start_time = time.time()
    print(f"[Info] Waiting for system to enter '{target_state}' mode...")
    while time.time() - start_time < timeout_seconds:
        current_state = get_system_state(ip)
        if current_state == target_state:
            print(f"[Success] System is now in '{target_state}' mode.")
            return True
        time.sleep(2)
    print(f"[Error] Timeout expired while waiting for '{target_state}' mode.")
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
    Main entry point for the script. Parses arguments and orchestrates the
    installation process.
    """
    parser = argparse.ArgumentParser(
        description="ctrlX CORE App (Snap) Installer via REST API.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--ip", default="192.168.1.1", help="ctrlX CORE IP address."
    )
    parser.add_argument(
        "--user", default="boschrexroth", help="Username for login."
    )
    parser.add_argument(
        "--password", default="boschrexroth", help="Password for login."
    )
    parser.add_argument(
        "--file", required=True, help="Path to the .snap installation package."
    )
    parser.add_argument(
        "--force", action="store_true",
        help="Ignore architecture mismatch warnings and force installation."
    )

    args = parser.parse_args()

    if not authenticate(args.ip, args.user, args.password):
        return

    print("\n[Sanity Check] Starting pre-flight checks...")
    model, arch = get_controller_info(args.ip)
    print(f"[Sanity Check] Detected hardware: {model} "
          f"(Expected architecture: {arch.upper()})")

    if not check_architecture_compatibility(args.file, arch, args.force):
        print("Installation aborted due to architecture mismatch. "
              "Use '--force' to override.")
        return
    print("[Sanity Check] OK. Proceeding with installation.\n")

    initial_state = get_system_state(args.ip)
    if not initial_state:
        return
    print(f"[Info] Current system state before installation: '{initial_state}'")

    switched_to_setup = False
    if initial_state == "run":
        if not (set_system_state(args.ip, "setup") and
                wait_for_state(args.ip, "setup")):
            return
        switched_to_setup = True
    elif initial_state != "setup":
        print(f"[Error] System is in an unknown state: '{initial_state}'. "
              "Aborting.")
        return

    install_ok = install_snap(args.ip, args.file)

    if switched_to_setup:
        print("[Info] Switching system back to 'run' mode.")
        if not (set_system_state(args.ip, "run") and
                wait_for_state(args.ip, "run")):
            print("[Warning] Failed to switch system back to 'run' mode.")

    if install_ok:
        print("\nDeployment completed successfully.")
    else:
        print("\nDeployment failed.")


if __name__ == "__main__":
    main()
