"""Minimal demo application for testing ctrlX CORE REST interactions.

This script serves as a lightweight Flask-based test client for Bosch Rexroth
ctrlX CORE systems. It demonstrates how to authenticate, read Data Layer
values, and change the scheduler state over HTTPS using the local controller API.

The script is intended for exploratory testing and validation workflows before
production deployment.
"""

import getpass
import json
import time
import requests
import urllib3

# Disable warnings for self-signed SSL certificates used by ctrlX CORE
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Global configuration and HTTP session initialization
CTRLX_CONFIG = {}
HTTP_SESSION = requests.Session()
HTTP_SESSION.verify = False

# Bypass system proxies (e.g., corporate proxies) for local communication
HTTP_SESSION.trust_env = False

def configure_connection() -> None:
    """Prompt the user for ctrlX CORE connection details.

    If the user presses Enter without typing, fallback values are used:
    IP 192.168.1.1, username and password set to boschrexroth.
    The password prompt masks the input for security.
    """
    print("\n--- Configure ctrlX CORE Connection (Press Enter for Default) ---")
    # Prompt for IP address
    ip_in = input("Enter IP Address [192.168.1.1]: ").strip()
    CTRLX_CONFIG['ip'] = ip_in or "192.168.1.1"
    # Prompt for username
    user_in = input("Enter Username [boschrexroth]: ").strip()
    CTRLX_CONFIG['username'] = user_in or "boschrexroth"
    # Masked prompt for password
    pass_in = getpass.getpass("Enter Password [boschrexroth]: ").strip()
    CTRLX_CONFIG['password'] = pass_in or "boschrexroth"
    print("-" * 65)

def fetch_bearer_token() -> bool:
    """Authenticate against the ctrlX CORE Identity Manager.

    Retrieves a valid bearer token and stores it in the shared HTTP session.
    This token is then used for subsequent requests to the ctrlX Data Layer and
    scheduler endpoints.

    Returns:
        bool: True if authentication succeeds, otherwise False.
    """
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/identity-manager/api/v2/auth/token"
    payload = {
        "name": CTRLX_CONFIG["username"],
        "password": CTRLX_CONFIG["password"]
    }
    try:
        response = HTTP_SESSION.post(url, json=payload, timeout=5)
        response.raise_for_status()
        token_data = response.json()
        token = token_data.get("access_token")
        if not token:
            print("\n[Error] 'access_token' not found in response.")
            return False
        # Apply Bearer token to all future requests in this session
        HTTP_SESSION.headers.update({"Authorization": f"Bearer {token}"})
        print("\n[Success] Connected and authenticated successfully.")
        return True
    except requests.exceptions.RequestException as e:
        print(f"\n[Error] Connection or authentication failed: {e}")
        return False

def read_datalayer_value(path: str) -> dict | None:
    """Read a value from a specific ctrlX Data Layer node.

    Args:
        path: The node path, for example ``scheduler/admin/state``.

    Returns:
        dict | None: Parsed JSON payload returned by the controller, or None when
        the request fails.
    """
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/automation/api/v2/nodes/{path}"
    try:
        response = HTTP_SESSION.get(url, timeout=5)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"\n[Error] Data Layer read failed for '{path}': {e}")
        return None

def change_scheduler_state(target_state: str) -> bool:
    """Change the ctrlX scheduler operating state.

    The function sends the exact payload structure used by the controller admin
    API and validates the result by reading the state back from the Data Layer.

    Args:
        target_state: One of ``OPERATING``, ``SETUP`` or ``SERVICE``.

    Returns:
        bool: True when the requested state is confirmed, otherwise False.
    """
    ip = CTRLX_CONFIG["ip"]
    url = f"https://{ip}/automation/api/v2/nodes/scheduler/admin/state"
    # Exact payload structure expected by the ctrlX Datalayer enum types
    payload = {
        "type": "object",
        "value": {
            "state": target_state
        }
    }
    print(f"\nSending command '{target_state}' to '{url}' via PUT...")
    try:
        response = HTTP_SESSION.put(url, json=payload, timeout=10)
        response.raise_for_status()
        print(f"[Info] API accepted command with status {response.status_code}.")
        print("Verifying actual controller status...")
        time.sleep(1.5)  # Short delay to let the controller switch states
        
        # Verify the actual state of the controller
        current_data = read_datalayer_value("scheduler/admin/state")
        actual_state = ""
        if current_data:
            val_data = current_data.get("value")
            if isinstance(val_data, dict):
                # Correctly extract state from the nested object: {'state': 'SETUP'}
                actual_state = val_data.get("state", "")
            else:
                # Fallback for simple string values
                actual_state = str(val_data)
                
        if current_data and actual_state == target_state:
            print(f"\n[SUCCESS] Controller state verified as '{target_state}'.")
            return True
        print(f"\n[WARNING] Silent Fail! API OK, but state is '{actual_state}'.")
        return False
    except requests.exceptions.RequestException as e:
        print(f"\n[Error] State transition request failed: {e}")
        return False

def show_menu() -> str:
    """Display the interactive CLI menu and return the selected option.

    Returns:
        str: User input representing the requested action.
    """
    print("\n--- Main Menu ---")
    print("1. Query current CPU utilization")
    print("2. Query current operating state (Operating/Setup/Service)")
    print("3. Set operating state")
    print("4. Reconfigure connection details")
    print("0. Exit application")
    return input("Please select an option: ")

def main() -> None:
    """Run the interactive ctrlX CORE test console.

    The function establishes the controller connection, authenticates, and then
    loops through the available Data Layer actions until the user exits.
    """
    configure_connection()
    if not fetch_bearer_token():
        return
    while True:
        choice = show_menu()
        if choice == '1':
            # Query CPU utilization
            data = read_datalayer_value(
                "framework/metrics/system/cpu-utilisation-percent"
            )
            if data:
                print(f"\n>>> Current CPU Usage: {data.get('value', 'N/A')} %")
        elif choice == '2':
            # Query current state
            data = read_datalayer_value("scheduler/admin/state")
            if data:
                # Correctly extract the state from the nested object if needed
                state_value = data.get('value')
                if isinstance(state_value, dict):
                    actual_state = state_value.get('state', 'UNKNOWN')
                else:
                    actual_state = state_value or 'UNKNOWN'
                print(f"\n>>> Current Operating State: {actual_state}")
        elif choice == '3':
            # Set target operating state
            print("\n  --- Select Target Operating State ---")
            print("  o) OPERATING")
            print("  t) SETUP")
            print("  s) SERVICE")
            sub_choice = input("  Your choice: ").lower()
            command = None
            if sub_choice == 'o':
                command = "OPERATING"
            elif sub_choice == 't':
                command = "SETUP"
            elif sub_choice == 's':
                command = "SERVICE"
            else:
                print("\n[Warning] Invalid selection.")
                continue
            change_scheduler_state(command)
        elif choice == '4':
            # Reconfigure connection
            configure_connection()
            fetch_bearer_token()
        elif choice == '0':
            print("\nExiting application. Goodbye.")
            break
        else:
            print("\n[Warning] Invalid option, please try again.")

if __name__ == "__main__":
    main()
