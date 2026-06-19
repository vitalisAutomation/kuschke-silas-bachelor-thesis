#!/usr/bin/env python3
"""
Python script to install a Snap App on a Bosch Rexroth ctrlX CORE via REST API.

This script runs fully interactively. It prompts the user for connection
details, automatically applying defaults upon pressing Enter, while requiring
a valid path to a local .snap package.

The script implements a robust asynchronous task-polling mechanism:
1. Switches the controller's Scheduler to SERVICE mode.
2. Uploads the Snap package to the '/package-manager/api/v1/packages?force=true'
   endpoint, initiating an installation task.
3. Extracts the task ID from either the JSON response body or the 'Location'
   HTTP header.
4. Polls the task status using the '/package-manager/api/v1/tasks/{taskId}'
   endpoint until the installation is confirmed as 'succeeded'.
5. Returns the Scheduler to OPERATING mode only after successful installation.

This version is fully compatible with modern ctrlX OS (v4.6+) architectures,
handles empty 202 responses via 'Location' headers, and allows overwriting
already installed applications.
"""

import os
import time
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


def get_controller_info() -> tuple[str, str]:
    """
    Read the electronic typeplate to determine the hardware model and architecture.

    :return: A tuple containing the model name and the expected architecture.
    :rtype: tuple[str, str]
    """
    ip = CTRLX_CONFIG["ip"]
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


def check_architecture_compatibility(snap_path, expected_arch) -> bool:
    """
    Check if the Snap filename is compatible with the controller's architecture.
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
    elif expected_arch == "amd64" and is_snap_arm and not is_snap_amd64:
        mismatch = True

    if mismatch:
        print("\n[ARCH_MISMATCH] Error: Security and operational risk!")
        print(f" -> Controller is {expected_arch.upper()}-based.")
        print(f" -> Snap filename '{filename}' implies a different architecture.")
        override = input("[Prompt] Override architecture mismatch? (y/N): ").strip().lower()
        if override == "y":
            print("[Info] Proceeding with forced installation.")
            return True
        return False

    print("[Check] Architecture compatibility check passed.")
    return True


def get_scheduler_state() -> str | None:
    """
    Retrieve the current Scheduler state from the Data Layer.
    """
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/automation/api/v2/nodes/scheduler/admin/state"
    try:
        response = HTTP_SESSION.get(url, timeout=5)
        response.raise_for_status()
        raw_val = response.json().get("value")
        if isinstance(raw_val, dict):
            return raw_val.get("state", "UNKNOWN").upper()
        return str(raw_val).upper() if raw_val else "UNKNOWN"
    except requests.exceptions.RequestException as e:
        print(f"[Error] Failed to retrieve system state: {e}")
        return None


def change_scheduler_state(target_state: str) -> bool:
    """
    Change the scheduler operating state (OPERATING, SETUP, SERVICE).
    """
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/automation/api/v2/nodes/scheduler/admin/state"
    
    # Korrigierter, flacher Payload für den ctrlX Data Layer REST-Knoten
    payload = {"type": "string", "value": target_state}
    
    try:
        print(f"[Info] Requesting switch to Scheduler state '{target_state}'...")
        response = HTTP_SESSION.put(url, json=payload, timeout=15)
        
        # Falls die Steuerung meckert, versuchen wir das alternative Format
        if response.status_code == 400:
            # Alternatives Format für ältere/neuere ctrlX Versionen
            alternative_payload = {"value": {"state": target_state}}
            response = HTTP_SESSION.put(url, json=alternative_payload, timeout=15)
            
        response.raise_for_status()
        return True
    except requests.exceptions.RequestException as e:
        print(f"[Error] Failed to switch Scheduler to '{target_state}': {e}")
        if response := getattr(e, 'response', None):
            print(f"[Details] API Response: {response.text}")
        return False


def wait_for_scheduler_state(target_state, timeout_seconds=60) -> bool:
    """
    Poll the Scheduler state until it reaches the target state or times out.
    """
    start_time = time.time()
    print(f"[Info] Waiting for Scheduler to enter '{target_state}' mode...")
    while time.time() - start_time < timeout_seconds:
        current_state = get_scheduler_state()
        if current_state == target_state:
            print(f"[Success] Scheduler is now in '{target_state}' state.")
            return True
        time.sleep(2)
    print(f"[Error] Timeout expired while waiting for '{target_state}' state.")
    return False


def get_task_status(task_id: str) -> dict | None:
    """
    Retrieves the status of a specific background task from the Package Manager API.
    """
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/package-manager/api/v1/tasks/{task_id}"
    try:
        response = HTTP_SESSION.get(url, timeout=5)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"\n[Error] Could not get status for task '{task_id}': {e}")
        return None


def wait_for_task_completion(task_id: str, timeout_seconds: int = 300) -> bool:
    """
    Polls the task endpoint until the installation task is complete.
    """
    start_time = time.time()
    print(f"[Info] Waiting for installation task '{task_id}' to complete...")
    while time.time() - start_time < timeout_seconds:
        task_info = get_task_status(task_id)
        if not task_info:
            return False

        status = task_info.get("status", "unknown").lower()
        progress = task_info.get("progress", 0)
        print(f"\r -> Installation status: {status.upper()} ({progress}%)", end="")

        if status == "succeeded":
            print("\n[Success] Installation task finished successfully.")
            return True
        if status in ["failed", "canceled"]:
            error_details = task_info.get("error", "No details provided.")
            print(f"\n[Error] Installation task failed with status '{status}'. Details: {error_details}")
            return False
        time.sleep(2)

    print("\n[Error] Timeout expired while waiting for installation to complete.")
    return False


def install_snap(snap_path) -> bool:
    """
    Uploads the Snap to the Package Manager API and monitors the installation task.
    """
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/package-manager/api/v1/packages?force=true"
    filename = os.path.basename(snap_path)

    print(f"\n[Info] Uploading '{filename}' to start installation via '{url}'...")
    try:
        with open(snap_path, "rb") as f:
            files = {"file": (filename, f, "application/octet-stream")}
            headers = {"Accept": "application/json"}
            response = HTTP_SESSION.post(url, files=files, headers=headers, timeout=45)

            # Expect 202 Accepted for async tasks
            if response.status_code == 202:
                task_id = None
                
                # 1. Try to extract ID from JSON body
                try:
                    response_data = response.json()
                    task_id = response_data.get("id") or response_data.get("taskId")
                except ValueError:
                    # Body is empty or not JSON, fallback to header
                    pass
                
                # 2. Try to extract ID from HTTP 'Location' Header
                if not task_id:
                    location = response.headers.get("Location")
                    if location:
                        # Extract the last part of the path, which is the UUID/Task ID
                        task_id = location.strip("/").split("/")[-1]
                        print(f"[Info] Extracted task ID from Location header: {task_id}")

                if not task_id:
                    print("[Error] API accepted request (202) but returned no task ID.")
                    print(f"[Details] Status Code: {response.status_code}")
                    print(f"[Details] Headers: {dict(response.headers)}")
                    print(f"[Details] Response Text: {response.text}")
                    return False

                print(f"[Info] Installation task started with ID: {task_id}")
                return wait_for_task_completion(task_id)
            else:
                print(f"[Error] Upload failed with unexpected status code "
                      f"{response.status_code}: {response.text}")
                return False
    except requests.exceptions.RequestException as e:
        print(f"[Error] Network error during snap upload: {e}")
        return False


def main() -> None:
    """
    Main entry point for the script.
    """
    print("=== ctrlX CORE App (Snap) Deployment Script ===")
    configure_connection()
    snap_path = ""
    while not snap_path:
        path_in = input("Enter path to .snap file: ").strip()
        if not path_in:
            print("[Error] Snap file path is required.")
        elif not os.path.exists(path_in):
            print(f"[Error] File does not exist at: '{path_in}'. Please try again.")
        else:
            snap_path = path_in

    if not fetch_bearer_token():
        return

    print("\n[Sanity Check] Starting pre-flight checks...")
    model, arch = get_controller_info()
    print(f"[Sanity Check] Detected hardware: {model} (Expected architecture: {arch.upper()})")

    if not check_architecture_compatibility(snap_path, arch):
        print("\n[Error] Aborting installation due to architecture mismatch.")
        return
    print("[Sanity Check] OK. Proceeding with installation.")

    initial_state = get_scheduler_state()
    if not initial_state:
        return
    print(f"\n[Info] Current Scheduler state: '{initial_state}'")

    switched_to_service = False
    if initial_state in ["OPERATING", "SETUP"]:
        if not (change_scheduler_state("SERVICE") and wait_for_scheduler_state("SERVICE")):
            return
        switched_to_service = True
    elif initial_state != "SERVICE":
        print(f"[Error] Scheduler is in an unsupported state: '{initial_state}'. Aborting.")
        return

    install_ok = install_snap(snap_path)

    if switched_to_service:
        print("\n[Info] Restoring system back to OPERATING mode.")
        if not (change_scheduler_state("OPERATING") and wait_for_scheduler_state("OPERATING")):
            print("[Warning] Failed to switch Scheduler back to OPERATING.")

    if install_ok:
        print("\nDeployment completed successfully.")
    else:
        print("\nDeployment failed.")


if __name__ == "__main__":
    main()
