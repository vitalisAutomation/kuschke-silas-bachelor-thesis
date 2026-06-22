"""
Flask Backend for the ctrlX Dashboard App.

This single backend supports two run modes based on the APP_ENVIRONMENT
environment variable:

- 'production': (Default) Runs inside the ctrlX CORE snap. Serves the
  compiled Angular frontend and communicates with the local Data Layer.
- 'development': Runs on a local PC. Provides a CORS-enabled API for an
  external Angular development server (ng serve) and connects to a remote
  ctrlX CORE over the network.

Now powered by WebSockets (Flask-SocketIO) for real-time metric pushes and
encrypted HTTPS / WSS communication.
"""

import os
import getpass
import time
from threading import Lock
import requests
import urllib3
from dotenv import load_dotenv
from flask import Flask, jsonify, send_from_directory, request
from flask_cors import CORS
from flask_socketio import SocketIO, emit

# --- INITIAL SETUP ---
load_dotenv()

# Disable warnings for self-signed SSL certificates used by ctrlX CORE
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Determine the run environment
IS_DEVELOPMENT = os.getenv("APP_ENVIRONMENT") == "development"

# Global store for connection details and session object
CTRLX_CONFIG = {}
HTTP_SESSION = requests.Session()
HTTP_SESSION.verify = False
HTTP_SESSION.trust_env = False  # Always bypass system-level proxies

CONFIG_LOCK = Lock()

# Initialize Flask App
app = Flask(__name__, static_folder="static", static_url_path="")

# Configure SocketIO and CORS based on the environment
if IS_DEVELOPMENT:
    # Allow secure connections from the local Angular dev server
    CORS(app, resources={r"/api/*": {"origins": "https://localhost:4200"}})
    socketio = SocketIO(app, cors_allowed_origins="https://localhost:4200", async_mode="eventlet")
    print("--- RUNNING IN DEVELOPMENT MODE (HTTPS & WSS ACTIVE) ---")
else:
    # Production uses general CORS; encryption is offloaded to ctrlX Nginx proxy
    socketio = SocketIO(app, cors_allowed_origins="*", async_mode="eventlet")
    print("--- RUNNING IN PRODUCTION MODE (Nginx Reverse Proxy handles SSL) ---")

# Thread lock for SocketIO background tasks
THREAD_LOCK = Lock()
background_thread = None

# --- DATA LAYER CONFIGURATION ---
METRIC_PATHS = {
    "state": "scheduler/admin/state",
    "cpu": "framework/metrics/system/cpu-utilisation-percent",
    "ram_used_percent": "framework/metrics/system/memused-percent",
    "storage_used_percent": "framework/metrics/system/storage-used-percent",
}

def authenticate_to_core() -> bool:
    """
    Authenticate against the Identity Manager of the ctrlX CORE.

    The authentication method depends on the current environment:
    - Production: Authentication is handled by the system context (assumes token is local).
    - Development: Performs a remote HTTPS login using configured credentials.

    :return: True if authentication succeeded, False otherwise.
    :rtype: bool
    """
    if not IS_DEVELOPMENT:
        print("[Info] Production mode: Assuming local token is available.")
        return True
        
    with CONFIG_LOCK:
        ip = CTRLX_CONFIG.get("ip")
        if not ip: return False
        url = f"https://{ip}/identity-manager/api/v2/auth/token"
        payload = {
            "name": CTRLX_CONFIG["username"],
            "password": CTRLX_CONFIG["password"]
        }
        
    try:
        response = HTTP_SESSION.post(url, json=payload, timeout=5)
        response.raise_for_status()
        token = response.json().get("access_token")
        if token:
            HTTP_SESSION.headers.update({"Authorization": f"Bearer {token}"})
            print(f"[Success] Authenticated with remote ctrlX at {ip}.")
            return True
        print("[Error] 'access_token' not found in response.")
        return False
    except requests.exceptions.RequestException as e:
        print(f"[Error] Remote authentication failed: {e}")
        return False

def fetch_metrics_from_core() -> dict:
    """
    Query all configured system metrics from the ctrlX CORE Data Layer.

    Reads values such as scheduler state, CPU utilization, RAM usage, 
    and disk storage. Re-authenticates automatically if a 401 Unauthorized status is returned.

    :return: A dictionary containing the retrieved metrics.
    :rtype: dict
    """
    with CONFIG_LOCK:
        ip = "127.0.0.1" if not IS_DEVELOPMENT else CTRLX_CONFIG.get("ip", "localhost")
        
    base_url = f"https://{ip}/automation/api/v2/nodes"
    metrics_data = {}
    
    for key, path in METRIC_PATHS.items():
        try:
            response = HTTP_SESSION.get(f"{base_url}/{path}", timeout=2)
            if response.status_code == 401:  # Token expired
                print("[Info] Token expired during polling. Re-authenticating...")
                if authenticate_to_core():
                    response = HTTP_SESSION.get(f"{base_url}/{path}", timeout=2) # Retry
            
            if response.ok:
                raw_val = response.json().get("value")
                if key == "state" and isinstance(raw_val, dict):
                    metrics_data[key] = raw_val.get("state", "UNKNOWN")
                else:
                    metrics_data[key] = raw_val
            else:
                metrics_data[key] = "N/A"
        except Exception:
            metrics_data[key] = "Error"
            
    return metrics_data

# --- WEBSOCKET BACKGROUND LOOP ---
def metrics_polling_task() -> None:
    """
    Cyclic background task to poll metrics from the ctrlX CORE.

    Executes infinitely, fetching metrics every 2 seconds and pushing 
    them to all connected WebSocket clients via the 'metrics_update' event.
    """
    print("[WebSocket] Background polling task started.")
    while True:
        metrics = fetch_metrics_from_core()
        socketio.emit("metrics_update", metrics)
        socketio.sleep(2)  # Eventlet-compatible sleep

# --- WEBSOCKET EVENTS ---
@socketio.on("connect")
def handle_connect() -> None:
    """
    Handle incoming WebSocket client connections.

    Triggers an immediate metrics push upon connection and starts the 
    background polling task thread if it is not already running.
    """
    print(f"[WebSocket] Client connected: {request.sid}")
    
    # Send immediate update on connection to prevent empty UI
    initial_metrics = fetch_metrics_from_core()
    emit("metrics_update", initial_metrics)
    
    global background_thread
    with THREAD_LOCK:
        if background_thread is None:
            background_thread = socketio.start_background_task(target=metrics_polling_task)

@socketio.on("disconnect")
def handle_disconnect() -> None:
    """
    Handle WebSocket client disconnections.
    """
    print(f"[WebSocket] Client disconnected: {request.sid}")

# --- REST-API FOR STATE CHANGES ---
@app.route("/api/state", methods=["POST"])
def set_scheduler_state() -> tuple:
    """
    Change the controller's scheduler state (OPERATING, SETUP, SERVICE).

    Expects a JSON body containing the target state. Sends a PUT request to the 
    ctrlX CORE scheduler node. Pushes updated metrics immediately to all clients.

    :return: A tuple containing a JSON response and the HTTP status code.
    :rtype: tuple
    """
    data = request.get_json()
    if not data or "state" not in data:
        return jsonify({"error": "Missing 'state' in request body"}), 400
        
    target_state = data["state"].upper()
    if target_state not in ["OPERATING", "SETUP", "SERVICE"]:
        return jsonify({"error": "Invalid state. Choose OPERATING, SETUP or SERVICE."}), 400

    with CONFIG_LOCK:
        ip = "127.0.0.1" if not IS_DEVELOPMENT else CTRLX_CONFIG.get("ip", "localhost")

    url = f"https://{ip}/automation/api/v2/nodes/scheduler/admin/state"
    payload = {
        "type": "object",
        "value": {
            "state": target_state
        }
    }

    try:
        print(f"[Info] Sending transition to '{target_state}'...")
        response = HTTP_SESSION.put(url, json=payload, timeout=5)
        
        if response.status_code == 401:
            print("[Info] Token expired during transition. Re-authenticating...")
            if authenticate_to_core():
                response = HTTP_SESSION.put(url, json=payload, timeout=5)

        if response.ok:
            # Emit updated metrics immediately via WebSockets to keep all UIs in sync
            updated_metrics = fetch_metrics_from_core()
            socketio.emit("metrics_update", updated_metrics)
            return jsonify({"status": "success", "state": target_state}), 200
        else:
            return jsonify({
                "error": "State transition failed",
                "status_code": response.status_code,
                "details": response.json() if response.text else "No details"
            }), response.status_code
            
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Connection error: {str(e)}"}), 500

@app.route("/", defaults={"path": ""})
@app.route("/<path:path>")
def serve_frontend(path: str):
    """
    Serve the compiled Angular frontend.

    This route is only active in production mode. Serves 'index.html' 
    for routing fallbacks or specific files if they exist in the static directory.

    :param path: The requested static file path.
    :type path: str
    :return: The requested file or the index.html page.
    """
    if IS_DEVELOPMENT:
        return jsonify({
            "status": "Backend is running in development mode.",
            "message": "The Angular frontend must be served separately via 'ng serve'."
        })
    if path != "" and os.path.exists(os.path.join(app.static_folder, path)):
        return send_from_directory(app.static_folder, path)
    return send_from_directory(app.static_folder, "index.html")

# --- MAIN EXECUTION ---
if __name__ == "__main__":
    if IS_DEVELOPMENT:
        # Prompt for remote ctrlX details when running locally
        with CONFIG_LOCK:
            ip_in = input("Enter ctrlX IP Address [192.168.1.1]: ").strip()
            CTRLX_CONFIG['ip'] = ip_in or "192.168.1.1"
            user_in = input("Enter Username [boschrexroth]: ").strip()
            CTRLX_CONFIG['username'] = user_in or "boschrexroth"
            pass_in = getpass.getpass("Enter Password [boschrexroth]: ").strip()
            CTRLX_CONFIG['password'] = pass_in or "boschrexroth"
        
        # Try to connect, but do not crash the server if the Core is offline
        try:
            authenticate_to_core()
        except Exception as e:
            print(f"[Warning] Initial connection to ctrlX CORE failed (Core might be offline): {e}")
        
        # Secure Eventlet configuration
        cert_file = "cert.pem"
        key_file = "key.pem"
        
        # Check if local SSL certificates exist
        if os.path.exists(cert_file) and os.path.exists(key_file):
            print(f"[SSL] Starting secure server on https://localhost:5001")
            # For Eventlet, pass certfile and keyfile directly
            socketio.run(app, host="0.0.0.0", port=5001, certfile=cert_file, keyfile=key_file)
        else:
            print("[SSL Warning] 'cert.pem' or 'key.pem' not found in workspace!")
            print("[SSL Warning] Falling back to unencrypted http://localhost:5001 for development.")
            print("[SSL Warning] To enable HTTPS, generate certificates or run: pip install trustme")
            socketio.run(app, host="0.0.0.0", port=5001)
    else:
        # PRODUCTION MODE (on ctrlX CORE): 
        # The built-in Nginx reverse proxy of the CORE handles SSL offloading.
        # Inside the snap container, we communicate via unencrypted HTTP/WS on port 5001.
        socketio.run(app, host="0.0.0.0", port=5001)
