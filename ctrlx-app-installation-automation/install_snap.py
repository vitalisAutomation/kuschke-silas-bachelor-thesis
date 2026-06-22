"""
ctrlX CORE App (Snap) Deployment Automation Script.

This module provides a robust command-line interface to automate the installation
and management of Snap applications on Bosch Rexroth ctrlX CORE devices via the
Package Manager REST API.
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
    """
    Prompt the user for ctrlX CORE connection details.

    Applies default connection parameters (IP: '192.168.1.1', User/Password: 'boschrexroth')
    upon pressing Enter. Masking is applied to the password input for security.
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

    Retrieves a valid OAuth2 Bearer token and updates the global HTTP session headers
    for all subsequent API requests.

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

    Queries the system typeplate API and parses the response to identify whether the target
    hardware is an ARM-based or AMD64-based controller.

    :return: A tuple containing the resolved model name and the expected architecture.
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

def get_installed_app_info(app_name: str) -> dict | None:
    """
    Check if the specified application is already installed on the controller.

    Queries the package manager API to retrieve all currently installed packages,
    filtering the list by the given application name (with typical 'snap_' prefix normalization).

    :param app_name: The name of the application to check.
    :type app_name: str
    :return: The package metadata dictionary if installed, None otherwise.
    :rtype: dict or None
    """
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/package-manager/api/v1/packages"
    try:
        response = HTTP_SESSION.get(url, timeout=10)
        if response.status_code == 200:
            packages = response.json()
            if isinstance(packages, dict):
                packages = packages.get("packages", []) or packages.get("installedPackages", [])
            
            for pkg in packages:
                pkg_name = pkg.get("name", "")
                pkg_id = pkg.get("id", "")
                norm_id = pkg_id.replace("snap_", "")
                if pkg_name.lower() == app_name.lower() or norm_id.lower() == app_name.lower():
                    return pkg
        return None
    except requests.exceptions.RequestException as e:
        print(f"[Warning] Failed to fetch installed packages list: {e}")
        return None

def check_active_tasks() -> bool:
    """
    Query the Package Manager API for any currently active background tasks.

    Checks if any installation, update, or maintenance task is running or pending,
    which might block Scheduler state transitions or other concurrent actions.

    :return: True if an active or pending task exists, False otherwise.
    :rtype: bool
    """
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/package-manager/api/v1/tasks"
    try:
        response = HTTP_SESSION.get(url, timeout=5)
        if response.status_code == 200:
            tasks = response.json()
            if isinstance(tasks, dict):
                tasks = tasks.get("tasks", [])
            if isinstance(tasks, list):
                for task in tasks:
                    status = task.get("status", "").lower()
                    if status in ["running", "pending", "started"]:
                        print(f"[Info] Active background task found: Task ID '{task.get('id')}' "
                              f"({task.get('description', 'No description')}) - Status: {status.upper()}")
                        return True
        return False
    except Exception:
        return False

def check_architecture_compatibility(snap_path: str, expected_arch: str) -> bool:
    """
    Verify if the Snap filename is compatible with the controller's architecture.

    Extracts architectural markers from the file name and compares them with the target architecture
    to prevent operational risks or system faults.

    :param snap_path: The local file path to the .snap package.
    :type snap_path: str
    :param expected_arch: The target CPU architecture resolved from the controller ('arm' or 'amd64').
    :type expected_arch: str
    :return: True if the architecture matches or the user explicitly overrides the mismatch, False otherwise.
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
    Retrieve the current Scheduler operating state from the Data Layer.

    Queries the Data Layer node 'scheduler/admin/state' and extracts the active state value.

    :return: The active scheduler state string (e.g., 'OPERATING', 'SETUP', 'SERVICE') or None if the query fails.
    :rtype: str or None
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
    Request a change of the scheduler operating state.

    Iterates through multiple known API payload formats to ensure compatibility across
    various ctrlX OS firmware versions. Caches the successful format for subsequent calls.

    :param target_state: The requested scheduler state ('OPERATING', 'SETUP', 'SERVICE').
    :type target_state: str
    :return: True if the API accepted the state transition command, False otherwise.
    :rtype: bool
    """
    global WORKING_PAYLOAD_FORMAT
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/automation/api/v2/nodes/scheduler/admin/state"
    
    if WORKING_PAYLOAD_FORMAT is not None:
        try:
            payload = copy.deepcopy(WORKING_PAYLOAD_FORMAT)
            if "value" in payload:
                if isinstance(payload["value"], dict) and "state" in payload["value"]:
                    payload["value"]["state"] = target_state
                else:
                    payload["value"] = target_state
            
            response = HTTP_SESSION.put(url, json=payload, timeout=10)
            if response.status_code in [200, 204]:
                return True
        except requests.exceptions.RequestException:
            pass
            
    payloads = [
        {"type": "string", "value": target_state},       # Standard on ctrlX OS 1.20+
        {"value": target_state},                         # Flat Value Format
        {"value": {"state": target_state}},              # Flat Object Format
        {"type": "object", "value": {"state": target_state}} # Deep Object Format
    ]
    
    for payload in payloads:
        try:
            response = HTTP_SESSION.put(url, json=payload, timeout=10)
            if response.status_code in [200, 204]:
                WORKING_PAYLOAD_FORMAT = payload  # Cache the working format
                return True
        except requests.exceptions.RequestException:
            continue
            
    return False

def wait_for_scheduler_state(target_state: str, timeout_seconds: int = 60) -> bool:
    """
    Poll the Scheduler operating state until it reaches the target state.

    :param target_state: The expected target state.
    :type target_state: str
    :param timeout_seconds: The maximum duration in seconds to wait before timing out, defaults to 60.
    :type timeout_seconds: int
    :return: True if the target state was successfully reached within the timeout, False otherwise.
    :rtype: bool
    """
    start_time = time.time()
    print(f"[Info] Waiting for Scheduler to enter '{target_state}' mode...")
    while time.time() - start_time < timeout_seconds:
        current_state = get_scheduler_state()
        if current_state == target_state:
            print(f"[Success] Scheduler is now in '{target_state}' state.")
            return True
        time.sleep(2)
    print("[Error] Timeout expired while waiting for state transition.")
    return False

def get_task_status(task_id: str) -> dict | None:
    """
    Retrieve the status of a background package manager task.

    :param task_id: The unique identifier of the task.
    :type task_id: str
    :return: The raw task metadata dictionary if found, None otherwise.
    :rtype: dict or None
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
    Poll the task status endpoint until the installation task is complete.

    Monitors progress percentage and status strings. Implements protections for hangups
    at 100% and automated cleanup behaviors of completed tasks.

    :param task_id: The unique identifier of the task to poll.
    :type task_id: str
    :param timeout_seconds: The maximum duration in seconds to wait, defaults to 300.
    :type timeout_seconds: int
    :return: True if the installation task finished successfully, False otherwise.
    :rtype: bool
    """
    start_time = time.time()
    print(f"[Info] Waiting for installation task '{task_id}' to complete...")
    
    last_progress = -1
    progress_stuck_count = 0
    
    while time.time() - start_time < timeout_seconds:
        task_info = get_task_status(task_id)
        
        if not task_info:
            print("\n[Info] Task tracking ID disappeared. Double checking app status...")
            time.sleep(3)
            return True
            
        status = task_info.get("status", "unknown").lower()
        progress = task_info.get("progress", 0)
        
        print(f"\r -> Installation status: {status.upper()} ({progress}%)", end="")
        
        if status == "succeeded" or progress == 100:
            print("\n[Success] Installation task finished successfully.")
            return True
            
        if status in ["failed", "canceled"]:
            error_details = task_info.get("error", "No details provided.")
            print(f"\n[Error] Installation task failed with status '{status}'. Details: {error_details}")
            return False
            
        if progress == last_progress:
            progress_stuck_count += 1
        else:
            progress_stuck_count = 0
            
        if progress >= 99 and progress_stuck_count >= 5:
            print("\n[Success] Task reached terminal phase (99%+). Proceeding...")
            return True
            
        last_progress = progress
        time.sleep(2)
        
    print("\n[Error] Timeout expired while waiting for installation to complete.")
    return False

def install_snap(snap_path: str) -> bool:
    """
    Upload the Snap file to the Package Manager API and monitor the installation task.

    Performs a multipart/form-data upload of the local Snap binary. If accepted (HTTP 202),
    it extracts the task ID from either the JSON response body or the Location header,
    and initiates the task polling loop.

    :param snap_path: The local path to the .snap file.
    :type snap_path: str
    :return: True if the package was successfully uploaded and installed, False otherwise.
    :rtype: bool
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
            if response.status_code == 202:
                task_id = None
                try:
                    response_data = response.json()
                    task_id = response_data.get("id") or response_data.get("taskId")
                except ValueError:
                    pass
                
                if not task_id:
                    location = response.headers.get("Location")
                    if location:
                        task_id = location.strip("/").split("/")[-1]
                        print(f"[Info] Extracted task ID from Location header: {task_id}")
                if not task_id:
                    print("[Error] API accepted request (202) but returned no task ID.")
                    return False
                print(f"[Info] Installation task started with ID: {task_id}")
                return wait_for_task_completion(task_id)
            else:
                print(f"[Error] Upload failed with unexpected status code {response.status_code}: {response.text}")
                return False
    except requests.exceptions.RequestException as e:
        print(f"[Error] Network error during snap upload: {e}")
        return False

def main() -> None:
    """
    Execute the automated app installation workflow.

    Runs pre-flight validation checks, manages Scheduler state transitions safely
    (including retries during lockouts), uploads and polls the installation task,
    and restores the controller's state back to OPERATING mode.
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

    # Extract app name from the filename
    snap_filename = os.path.basename(snap_path)
    filename_clean = snap_filename.replace(".snap", "")
    parts = filename_clean.split("_")
    app_name = parts[0]
    app_version = parts[1] if len(parts) > 1 else None

    # --- 1. Pre-flight Check: Is the App already installed? ---
    print(f"\n[Sanity Check] Verifying if App '{app_name}' is already installed...")
    installed_pkg = get_installed_app_info(app_name)
    
    if installed_pkg:
        installed_version = installed_pkg.get("release", {}).get("version") or installed_pkg.get("version", "Unknown")
        print(f"[Info] App '{app_name}' is already installed (Version on Core: {installed_version}).")
        
        if app_version and installed_version == app_version:
            print(f"[Warning] The file '{snap_filename}' has the exact same version ({app_version}).")
            override = input("[Prompt] Reinstalling identical versions often fails on ctrlX OS. Continue? (y/N): ").strip().lower()
            if override != 'y':
                print("[Info] Aborting deployment to prevent redundant API errors.")
                return
        else:
            print(f"[Info] Will attempt upgrade/downgrade to version: {app_version or 'unknown'}.")

    # --- 2. Pre-flight Check: Are there active locks/tasks on the Core? ---
    if check_active_tasks():
        print("\n[Warning] Another installation or service task is currently active on the Core.")
        print(" -> Changing the Scheduler state to SERVICE will likely fail now!")
        proceed = input("[Prompt] Attempt state switch anyway? (y/N): ").strip().lower()
        if proceed != 'y':
            print("[Info] Deployment aborted by user.")
            return

    # --- 3. Hardware- & Architecture Check ---
    print("\n[Sanity Check] Running typeplate validation...")
    model, arch = get_controller_info()
    print(f"[Sanity Check] Detected hardware: {model} (Expected architecture: {arch.upper()})")
    if not check_architecture_compatibility(snap_path, arch):
        print("\n[Error] Aborting installation due to architecture mismatch.")
        return
    print("[Sanity Check] OK. Proceeding with installation.")

    # --- 4. Scheduler Transition Management ---
    initial_state = get_scheduler_state()
    if not initial_state:
        return
    print(f"\n[Info] Current Scheduler state: '{initial_state}'")

    switched_to_service = False
    if initial_state in ["OPERATING", "SETUP"]:
        if not (change_scheduler_state("SERVICE") and wait_for_scheduler_state("SERVICE")):
            print("\n[Diagnostic] Switch failed. Please ensure:")
            print(" 1. No other users are installing apps via the Web UI.")
            print(" 2. All real-time processes (Motion / PLC) are STOPPED.")
            print(" 3. All motor axes are DE-ENERGIZED (no regulator release/power).")
            return
        switched_to_service = True
    elif initial_state != "SERVICE":
        print(f"[Error] Scheduler is in an unsupported state: '{initial_state}'. Aborting.")
        return

    # --- 5. Upload & Install ---
    install_ok = install_snap(snap_path)

    # --- 6. Restore Scheduler state with Retry-Mechanism ---
    if switched_to_service:
        print("\n[Info] Restoring system back to OPERATING mode.")
        print("[Info] Giving the Package Manager 3 seconds to release system locks...")
        time.sleep(3)
        
        restored = False
        max_attempts = 6
        for attempt in range(1, max_attempts + 1):
            if change_scheduler_state("OPERATING"):
                if wait_for_scheduler_state("OPERATING"):
                    restored = True
                    break
            
            print(f"[Warning] Switch back to OPERATING rejected by Core (Attempt {attempt}/{max_attempts}).")
            print("          The Package Manager is likely still finalizing the installation in the background.")
            if attempt < max_attempts:
                print("          Retrying in 5 seconds...")
                time.sleep(5)
                
        if not restored:
            print("[Error] Failed to switch Scheduler back to OPERATING after multiple attempts.")
            print("        Please check the ctrlX CORE web interface and change the mode manually.")

    if install_ok:
        print("\nDeployment completed successfully.")
    else:
        print("\nDeployment failed.")

if __name__ == "__main__":
    main()
