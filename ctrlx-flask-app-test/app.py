"""
ctrlX CORE Datalayer Console Client.

This module provides a command-line interface to interact with the Bosch Rexroth
ctrlX CORE Datalayer REST API. It allows querying system metrics and changing
the controller's operating state.
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
    """
    Prompt the user for ctrlX CORE connection details.

    If the user presses Enter without typing, fallback standard values
    (IP: '192.168.1.1', User/Password: 'boschrexroth') are applied.
    The password input is masked for security.
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
    """
    Authenticate against the Identity Manager of the ctrlX CORE.

    Retrieves a valid Bearer token and updates the global HTTP session headers
    for all subsequent API calls.

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


def read_datalayer_value(path: str) -> dict or None:
    """
    Read a value from a specific ctrlX Data Layer node.

    :param path: The Data Layer node path (e.g., 'scheduler/admin/state').
    :type path: str
    :return: The JSON response dictionary from the node if successful,
             None otherwise.
    :rtype: dict or None
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
    """
    Change the scheduler operating state (OPERATING, SETUP, SERVICE).

    Sends a PUT request to the 'scheduler/admin/state' node using the exact
    payload structure analyzed from the ctrlX Web-UI network request.

    :param target_state: The target state ('OPERATING', 'SETUP', 'SERVICE').
    :type target_state: str
    :return: True if state transition was successful and verified,
             False otherwise.
    :rtype: bool
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

        # --- VERIFICATION LOGIC CORRECTED ---
        # Verify the actual state of the controller
        current_data = read_datalayer_value("scheduler/admin/state")
        actual_state = ""
        if isinstance(current_data.get("value"), dict):
            # Correctly extract state from the nested object: {'state': 'SETUP'}
            actual_state = current_data.get("value", {}).get("state")
        else:
            # Fallback for simple string values
            actual_state = current_data.get("value")

        if current_data and actual_state == target_state:
            print(f"\n[SUCCESS] Controller state verified as '{target_state}'.")
            return True

        print(f"\n[WARNING] Silent Fail! API OK, but state is "
              f"'{actual_state}'.")
        return False

    except requests.exceptions.RequestException as e:
        print(f"\n[Error] State transition request failed: {e}")
        if 'response' in locals() and response.text:
            print(f"Controller details: {response.text}")
        return False


def show_menu() -> str:
    """
    Display the interactive main console menu.

    :return: The user's menu choice as a string.
    :rtype: str
    """
    print("\n--- Main Menu ---")
    print("1. Query current CPU utilization")
    print("2. Query current operating state (Operating/Setup/Service)")
    print("3. Set operating state")
    print("4. Reconfigure connection details")
    print("0. Exit application")
    return input("Please select an option: ")


def main() -> None:
    """
    Execute the main application loop.

    Handles the CLI menu routing and manages the connection states.
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
            # --- STATUS READOUT LOGIC CORRECTED ---
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
