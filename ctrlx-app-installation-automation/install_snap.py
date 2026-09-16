"""
ctrlX CORE App (Snap) Deployment Automation Script.

This module provides a robust command-line interface to automate the
installation and management of Snap applications on Bosch Rexroth ctrlX CORE
devices via the REST API, featuring highly robust, API-based state transition
and upload handling.

Source: Gemini 3.6 Flash
Edited by: Silas Kuschke
"""

# --- Standard library ---
import copy
import getpass
import os
import re
import time

# --- Third-party libraries ---
import requests
import urllib3

# Disable warnings for self-signed SSL certificates used by ctrlX CORE
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# --- Global configuration ---
CTRLX_CONFIG = {}

# --- Global session ---
HTTP_SESSION = requests.Session()
HTTP_SESSION.verify = False
HTTP_SESSION.trust_env = False  # Bypass system proxies for local communication

# Cache for the successfully detected Scheduler REST payload format.
WORKING_PAYLOAD_FORMAT = None


def configure_connection() -> None:
    """Prompt the user for ctrlX CORE connection details.

    The values are stored in the global configuration dictionary and can later be
    reused for authentication and package installation requests.
    """
    print("\n--- Configure ctrlX CORE Connection (Press Enter for Default) ---")
    ip_in = input("Enter IP Address [192.168.1.1]: ").strip()
    CTRLX_CONFIG['ip'] = ip_in or "192.168.1.1"
    user_in = input("Enter Username [boschrexroth]: ").strip()
    CTRLX_CONFIG['username'] = user_in or "boschrexroth"
    pass_in = getpass.getpass("Enter Password [boschrexroth]: ").strip()
    CTRLX_CONFIG['password'] = pass_in or "boschrexroth"


def fetch_bearer_token() -> bool:
    """Authenticate against the Identity Manager and obtain a bearer token.

    The token is written into the shared HTTP session so that subsequent
    installation and Data Layer requests can be authorized automatically.

    Returns:
        bool: True when authentication succeeds, otherwise False.
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
    Polls 'system/admin/busy' and 'scheduler/admin/state/switching'.
    Waits until both are False. Uses 'is not True' for robust
    backwards-compatibility if nodes are not supported.
    """
    start_time = time.time()
    print("\n[Wait] Verifying system and scheduler are ready for state change...")
    while time.time() - start_time < timeout_seconds:
        is_system_busy = get_datalayer_node_value("system/admin/busy")
        is_scheduler_switching = get_datalayer_node_value(
            "scheduler/admin/state/switching"
        )
        if is_system_busy is not True and is_scheduler_switching is not True:
            print(
                "\r[Success] System is ready (busy=FALSE, switching=FALSE). "
                "Proceeding..."
            )
            return True
        status_msg = (
            f" -> Waiting: System Busy = {is_system_busy}, "
            f"Scheduler Switching = {is_scheduler_switching}"
        )
        print(f"\r{status_msg}", end="", flush=True)
        time.sleep(3)
    print(
        "\n[Warning] Timeout waiting for system readiness. "
        "Will attempt state switch anyway."
    )
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


def wait_for_scheduler_state(
    target_state: str, timeout_seconds: int = 60
) -> bool:
    """Poll the Scheduler operating state until it reaches the target state."""
    start_time = time.time()
    print(
        f"[Info] Waiting for Scheduler to enter '{target_state}' mode..."
    )
    while time.time() - start_time < timeout_seconds:
        if get_scheduler_state() == target_state:
            print(f"[Success] Scheduler is now in '{target_state}' state.")
            return True
        time.sleep(2)
    print(
        f"[Error] Timeout waiting for state transition to '{target_state}'."
    )
    return False


def switch_scheduler_state_when_ready(
    target_state: str, timeout_seconds: int = 300
) -> bool:
    """Wait for readiness and retry the state change until it succeeds."""
    start_time = time.time()
    print(
        f"[Info] Waiting to switch Scheduler to '{target_state}' "
        "when the system is ready..."
    )
    while time.time() - start_time < timeout_seconds:
        if get_scheduler_state() == target_state:
            print(f"[Success] Scheduler is already in '{target_state}' state.")
            return True
        remaining_time = timeout_seconds - (time.time() - start_time)
        readiness_timeout = min(10, max(1, int(remaining_time)))
        if wait_for_system_and_scheduler_ready(readiness_timeout):
            if change_scheduler_state(target_state):
                if wait_for_scheduler_state(target_state, readiness_timeout):
                    return True
        print(
            "[Info] Scheduler state change is not available yet. "
            "Device Admin may still be active; waiting for the next state check."
        )
        time.sleep(5)
    print(
        f"[Error] Timeout expired while switching Scheduler to "
        f"'{target_state}'."
    )
    return False


def get_installed_packages() -> list[dict] | None:
    """Retrieve the installed packages from the package manager."""
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/package-manager/api/v1/packages"
    try:
        response = HTTP_SESSION.get(url, timeout=5)
        response.raise_for_status()
        packages = response.json()
        return packages if isinstance(packages, list) else None
    except Exception:
        return None


def get_installed_package_version(package_name: str) -> str | None:
    """Retrieve the installed version of a package by its snap name."""
    packages = get_installed_packages()
    if packages is None:
        return None
    for package in packages:
        if package.get("name") != package_name:
            continue
        release = package.get("release", {})
        return release.get("version")
    return None


def get_task_status(task_id: str) -> dict | None:
    """Retrieve the status of a background package manager task."""
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/package-manager/api/v1/tasks/{task_id}"
    try:
        response = HTTP_SESSION.get(url, timeout=5)
        response.raise_for_status()
        task_info = response.json()
        return task_info if isinstance(task_info, dict) else None
    except Exception:
        return None


def wait_for_package_version(
    package_name: str,
    target_version: str,
    task_id: str | None = None,
    timeout_seconds: int = 300,
) -> bool:
    """Poll installed packages until the target version is available."""
    start_time = time.time()
    print(
        f"[Info] Waiting for package '{package_name}' to reach version "
        f"'{target_version}'..."
    )
    while time.time() - start_time < timeout_seconds:
        installed_version = get_installed_package_version(package_name)
        if installed_version == target_version:
            print(
                f"\n[Success] Package '{package_name}' is installed at "
                f"version '{target_version}'."
            )
            return True
        progress_text = "unknown"
        if task_id:
            task_info = get_task_status(task_id)
            if task_info:
                progress = task_info.get("progress")
                status = task_info.get("status") or task_info.get("state")
                progress_text = f"{status or 'pending'} ({progress}%)"
        print(
            f"\r -> Installation: {progress_text}; installed version: "
            f"{installed_version or 'not available'}",
            end="",
        )
        time.sleep(2)
    print("\n[Error] Timeout expired while waiting for installation.")
    return False


def get_snap_metadata(snap_path: str) -> tuple[str, str] | None:
    """Extract the snap name and version from a standard snap filename."""
    filename = os.path.basename(snap_path)
    match = re.match(r"^(?P<name>.+)_(?P<version>[^_]+)_(?P<architecture>[^.]+)\.snap$", filename)
    if not match:
        return None
    return match.group("name"), match.group("version")


def install_snap(snap_path: str, package_name: str, target_version: str) -> bool:
    """Upload the Snap and verify the installed package version."""
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/package-manager/api/v1/packages?force=true"
    filename = os.path.basename(snap_path)
    print(f"\n[Info] Uploading '{filename}' to start installation...")
    try:
        with open(snap_path, "rb") as f:
            files = {"file": (filename, f, "application/octet-stream")}
            response = HTTP_SESSION.post(
                url,
                files=files,
                headers={"Accept": "application/json"},
                timeout=120
            )
            if response.status_code == 202:
                task_id = None
                location = response.headers.get("Location")
                if location:
                    task_id = location.strip("/").split("/")[-1]
                print("[Info] Upload accepted. Verifying installed version...")
                return wait_for_package_version(
                    package_name, target_version, task_id
                )
            else:
                print(
                    f"[Error] Upload failed with status "
                    f"{response.status_code}: {response.text}"
                )
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
    snap_metadata = get_snap_metadata(snap_path)
    if not snap_metadata:
        print(
            "[Error] Snap filename must follow '<name>_<version>_<architecture>.snap'."
        )
        return
    package_name, target_version = snap_metadata
    print(
        f"[Info] Target package: '{package_name}', "
        f"version: '{target_version}'"
    )
    if not fetch_bearer_token():
        return

    initial_state = get_scheduler_state()
    print(f"\n[Info] Initial Scheduler state: '{initial_state}'")
    try:
        # --- 1. Ensure system is in SERVICE mode for installation ---
        current_version = get_installed_package_version(package_name)
        if current_version == target_version:
            print(
                f"[Info] Package '{package_name}' version '{target_version}' "
                "is already installed. Skipping upload."
            )
            return
        if initial_state != "SERVICE":
            print("[Info] Switching to SERVICE mode for installation...")
            if not switch_scheduler_state_when_ready("SERVICE"):
                print("[Error] Failed to switch to SERVICE mode. Aborting.")
                return
        else:
            print("[Info] System is already in SERVICE mode. Proceeding directly.")

        # --- 2. Install App ---
        install_ok = install_snap(snap_path, package_name, target_version)
        if install_ok:
            print("\n[SUCCESS] App installation verified.")
        else:
            print("\n[FAILURE] App installation could not be verified.")
    finally:
        # --- 3. Finalize: Restore the initial Scheduler state ---
        if initial_state not in ["UNKNOWN", "SERVICE"]:
            print(
                f"\n[Finalize] Restoring initial Scheduler state "
                f"'{initial_state}'..."
            )
            if not switch_scheduler_state_when_ready(initial_state):
                print(
                    f"[Failure] Could not restore Scheduler state "
                    f"'{initial_state}'."
                )
        try:
            HTTP_SESSION.delete(
                f"https://{CTRLX_CONFIG['ip']}/identity-manager/api/v2/auth/token",
                timeout=10,
            )
        except requests.exceptions.RequestException as e:
            print(f"[Warning] Could not close the REST session: {e}")


if __name__ == "__main__":
    main()
