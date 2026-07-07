"""
ctrlX CORE App (Snap) Deployment Automation Script.

This module provides a robust command-line interface to automate the installation
and management of Snap applications on Bosch Rexroth ctrlX CORE devices via the
REST API, featuring highly robust, API-based state transition and upload handling.
"""

import os
import time
import getpass
import requests
import urllib3
import copy

# Disable warnings for self-signed SSL certificates used by ctrlX CORE
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Global configuration and HTTP session initialization
CTRLX_CONFIG = {}
HTTP_SESSION = requests.Session()
HTTP_SESSION.verify = False
HTTP_SESSION.trust_env = False  # Bypass system proxies for local communication

# Cache for the successfully detected Scheduler REST payload format
WORKING_PAYLOAD_FORMAT = None

def configure_connection() -> None:
    """Prompt the user for ctrlX CORE connection details."""
    print("\n--- Configure ctrlX CORE Connection (Press Enter for Default) ---")
    ip_in = input("Enter IP Address [192.168.1.1]: ").strip()
    CTRLX_CONFIG['ip'] = ip_in or "192.168.1.1"
    user_in = input("Enter Username [boschrexroth]: ").strip()
    CTRLX_CONFIG['username'] = user_in or "boschrexroth"
    pass_in = getpass.getpass("Enter Password [boschrexroth]: ").strip()
    CTRLX_CONFIG['password'] = pass_in or "boschrexroth"

def fetch_bearer_token() -> bool:
    """Authenticate against the Identity Manager and get a Bearer token."""
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

def get_datalayer_node_value(node_path: str) -> any:
    """Generic function to read a value from any Data Layer node."""
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/automation/api/v2/nodes/{node_path}"
    try:
        response = HTTP_SESSION.get(url, timeout=5)
        if response.status_code == 200:
            raw_val = response.json().get("value")
            if isinstance(raw_val, dict) and "value" in raw_val:
                return raw_val["value"]
            return raw_val
    except Exception:
        pass
    return None

def wait_for_system_and_scheduler_ready(timeout_seconds: int = 180) -> bool:
    """
    Polls 'system/admin/busy' and 'scheduler/admin/state/switching' until both are False.
    Uses 'is not True' for robust backwards-compatibility if nodes are not supported.
    """
    start_time = time.time()
    print("\n[Wait] Verifying system and scheduler are ready for state change...")
    while time.time() - start_time < timeout_seconds:
        is_system_busy = get_datalayer_node_value("system/admin/busy")
        is_scheduler_switching = get_datalayer_node_value("scheduler/admin/state/switching")

        if is_system_busy is not True and is_scheduler_switching is not True:
            print("\r[Success] System is ready (busy=FALSE, switching=FALSE). Proceeding...")
            return True
        
        status_msg = f" -> Waiting: System Busy = {is_system_busy}, Scheduler Switching = {is_scheduler_switching}"
        print(f"\r{status_msg}", end="", flush=True)
        time.sleep(3)
        
    print("\n[Warning] Timeout waiting for system readiness. Will attempt state switch anyway.")
    return False

def change_scheduler_state(target_state: str) -> bool:
    """Request a change of the scheduler operating state."""
    global WORKING_PAYLOAD_FORMAT
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/automation/api/v2/nodes/scheduler/admin/state"
    payloads = [
        {"type": "string", "value": target_state}, 
        {"value": target_state},
        {"value": {"state": target_state}}, 
        {"type": "object", "value": {"state": target_state}}
    ]
    if WORKING_PAYLOAD_FORMAT:
        p_copy = copy.deepcopy(WORKING_PAYLOAD_FORMAT)
        if isinstance(p_copy.get("value"), dict):
            p_copy["value"]["state"] = target_state
        else:
            p_copy["value"] = target_state
        payloads.insert(0, p_copy)
    for p in payloads:
        try:
            response = HTTP_SESSION.put(url, json=p, timeout=10)
            if response.status_code in [200, 204]:
                WORKING_PAYLOAD_FORMAT = p
                return True
        except requests.exceptions.RequestException:
            continue
    return False

def get_scheduler_state() -> str:
    """Retrieve the current Scheduler operating state from the Data Layer."""
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/automation/api/v2/nodes/scheduler/admin/state"
    try:
        response = HTTP_SESSION.get(url, timeout=5)
        if response.status_code == 200:
            raw_val = response.json().get("value")
            if isinstance(raw_val, dict):
                return raw_val.get("state", "UNKNOWN").upper()
            return str(raw_val).upper() if raw_val else "UNKNOWN"
    except Exception:
        pass
    return "UNKNOWN"

def wait_for_scheduler_state(target_state: str, timeout_seconds: int = 60) -> bool:
    """Poll the Scheduler operating state until it reaches the target state."""
    start_time = time.time()
    print(f"[Info] Waiting for Scheduler to enter '{target_state}' mode...")
    while time.time() - start_time < timeout_seconds:
        if get_scheduler_state() == target_state:
            print(f"[Success] Scheduler is now in '{target_state}' state.")
            return True
        time.sleep(2)
    print(f"[Error] Timeout waiting for state transition to '{target_state}'.")
    return False

def get_task_status(task_id: str) -> dict | None:
    """Retrieve the status of a background package manager task."""
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/package-manager/api/v1/tasks/{task_id}"
    try:
        response = HTTP_SESSION.get(url, timeout=5)
        response.raise_for_status()
        return response.json()
    except Exception:
        return None

def wait_for_task_completion(task_id: str, timeout_seconds: int = 300) -> bool:
    """Poll the task status endpoint until the installation task is complete."""
    start_time = time.time()
    print(f"[Info] Waiting for installation task '{task_id}' to complete...")
    while time.time() - start_time < timeout_seconds:
        task_info = get_task_status(task_id)
        if not task_info:
            print("\n[Info] Task tracking ID disappeared. Assuming successful completion.")
            return True
        
        status = task_info.get("status", "unknown").lower()
        progress = task_info.get("progress", 0)
        print(f"\r -> Installation status: {status.upper()} ({progress}%)", end="")
        
        if status == "succeeded":
            print("\n[Success] Installation task reported 'succeeded'.")
            return True
        if status in ["failed", "canceled"]:
            error_details = task_info.get("error", "No details provided.")
            print(f"\n[Error] Installation task failed with status '{status}'. Details: {error_details}")
            return False
        time.sleep(2)
        
    print("\n[Error] Timeout expired while waiting for installation.")
    return False

def install_snap(snap_path: str) -> bool:
    """Uploads the Snap and monitors the installation task."""
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/package-manager/api/v1/packages?force=true"
    filename = os.path.basename(snap_path)
    print(f"\n[Info] Uploading '{filename}' to start installation...")
    try:
        with open(snap_path, "rb") as f:
            files = {"file": (filename, f, "application/octet-stream")}
            response = HTTP_SESSION.post(url, files=files, headers={"Accept": "application/json"}, timeout=120)
            
            if response.status_code == 202:
                task_id = None
                # Robustes Parsing: Fange leere/Text-Antworten sauber ab
                try:
                    response_data = response.json()
                    task_id = response_data.get("id") or response_data.get("taskId")
                except Exception:
                    pass  # Kein gültiges JSON zurückgegeben -> Nutze Fallback auf Header
                
                if not task_id:
                    location = response.headers.get("Location")
                    if location:
                        task_id = location.strip("/").split("/")[-1]
                        print(f"[Info] Extracted task ID from Location header: {task_id}")
                        
                if not task_id:
                    print("[Error] API accepted request (202) but returned no task ID.")
                    return False
                    
                return wait_for_task_completion(task_id)
            else:
                print(f"[Error] Upload failed with status {response.status_code}: {response.text}")
                return False
    except requests.exceptions.RequestException as e:
        print(f"[Error] Network error during snap upload: {e}")
        return False

def main() -> None:
    """Execute the full automated app installation workflow."""
    print("=== ctrlX CORE App (Snap) Deployment Script ===")
    configure_connection()
    
    snap_path = input("Enter path to .snap file: ").strip()
    if not (snap_path and os.path.exists(snap_path)):
        print("[Error] A valid .snap file path is required.")
        return

    if not fetch_bearer_token():
        return

    # --- 1. Get initial Scheduler state ---
    initial_state = get_scheduler_state()
    print(f"\n[Info] Current Scheduler state: '{initial_state}'")
    
    switched_to_service = False
    if initial_state == "OPERATING":
        print("[Info] Switching to SERVICE mode for installation...")
        if not (change_scheduler_state("SERVICE") and wait_for_scheduler_state("SERVICE")):
            print("[Error] Failed to switch to SERVICE mode. Aborting.")
            return
        switched_to_service = True
    elif initial_state != "SERVICE":
        print(f"[Error] Scheduler is in unsupported state '{initial_state}'. Aborting.")
        return

    # --- 2. Install App ---
    install_ok = install_snap(snap_path)
    
    # --- 3. Restore Scheduler State ---
    if switched_to_service:
        print("\n[Info] Restoring system back to OPERATING mode.")
        if install_ok:
            # Das System wartet hier sauber, bis der Upload und die Installation abgeschlossen sind
            wait_for_system_and_scheduler_ready()
        else:
            print("[Warning] Installation failed. Attempting to restore state anyway...")

        restored = False
        for attempt in range(1, 6):
            if change_scheduler_state("OPERATING") and wait_for_scheduler_state("OPERATING"):
                restored = True
                break
            print(f"[Warning] Restore Attempt {attempt}/5 failed. Retrying in 10s...")
            time.sleep(10)

        if restored:
            print("\n[SUCCESS] System successfully restored to OPERATING mode.")
            print("Installation " + ("succeeded." if install_ok else "FAILED."))
        else:
            print("\n[FAILURE] FAILED to restore OPERATING mode. Please check ctrlX CORE manually.")
    elif install_ok:
        print("\n[SUCCESS] Deployment completed successfully in SERVICE mode.")
    else:
        print("\n[FAILURE] Deployment failed in SERVICE mode.")

if __name__ == "__main__":
    main()
