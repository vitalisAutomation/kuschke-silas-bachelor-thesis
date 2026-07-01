"""
Robust, Sphinx-compliant Flask Backend for the ctrlX Dashboard App.
"""

import os
import getpass
from threading import Lock
import requests
import urllib3
from dotenv import load_dotenv
from flask import Flask, jsonify, send_from_directory, request
from flask_cors import CORS
from flask_socketio import SocketIO, emit

# --- INITIAL SETUP ---
load_dotenv()
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# We are in production if running inside the Snap confinement, otherwise development
IS_DEVELOPMENT = os.getenv("APP_ENVIRONMENT") == "development"

CTRLX_CONFIG = {}
HTTP_SESSION = requests.Session()
HTTP_SESSION.verify = False
HTTP_SESSION.trust_env = False

CONFIG_LOCK = Lock()

# WICHTIG: Standardmäßige, robuste Initialisierung ohne Absturzrisiko im Container!
app = Flask(__name__, static_folder="static", static_url_path="")

# Configure SocketIO and CORS
if IS_DEVELOPMENT:
    allowed_origins = ["http://localhost:4200", "https://localhost:4200"]
    CORS(app, resources={r"/api/*": {"origins": allowed_origins}})
    socketio = SocketIO(app, cors_allowed_origins=allowed_origins, async_mode="eventlet")
    print("--- RUNNING IN DEVELOPMENT MODE ---")
else:
    socketio = SocketIO(app, cors_allowed_origins="*", async_mode="eventlet")
    print("--- RUNNING IN PRODUCTION MODE ---")

THREAD_LOCK = Lock()
background_thread = None

METRIC_PATHS = {
    "state": "scheduler/admin/state",
    "cpu": "framework/metrics/system/cpu-utilisation-percent",
    "ram_used_percent": "framework/metrics/system/memused-percent",
    "storage_used_percent": "framework/metrics/system/storage-used-percent",
}

def authenticate_to_core() -> bool:
    if not IS_DEVELOPMENT:
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
            return True
        return False
    except Exception:
        return False

def fetch_metrics_from_core() -> dict:
    with CONFIG_LOCK:
        ip = "127.0.0.1" if not IS_DEVELOPMENT else CTRLX_CONFIG.get("ip", "localhost")
    base_url = f"https://{ip}/automation/api/v2/nodes"
    metrics_data = {}
    for key, path in METRIC_PATHS.items():
        try:
            response = HTTP_SESSION.get(f"{base_url}/{path}", timeout=2)
            if response.status_code == 401 and authenticate_to_core():
                response = HTTP_SESSION.get(f"{base_url}/{path}", timeout=2)
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

def metrics_polling_task() -> None:
    while True:
        metrics = fetch_metrics_from_core()
        socketio.emit("metrics_update", metrics)
        socketio.sleep(2)

@socketio.on("connect")
def handle_connect() -> None:
    initial_metrics = fetch_metrics_from_core()
    emit("metrics_update", initial_metrics)
    global background_thread
    with THREAD_LOCK:
        if background_thread is None:
            background_thread = socketio.start_background_task(target=metrics_polling_task)

@app.route("/api/state", methods=["POST"])
def set_scheduler_state() -> tuple:
    data = request.get_json()
    if not data or "state" not in data:
        return jsonify({"error": "Missing 'state'"}), 400
    target_state = data["state"].upper()
    with CONFIG_LOCK:
        ip = "127.0.0.1" if not IS_DEVELOPMENT else CTRLX_CONFIG.get("ip", "localhost")
    url = f"https://{ip}/automation/api/v2/nodes/scheduler/admin/state"
    payload = {"type": "object", "value": {"state": target_state}}
    try:
        response = HTTP_SESSION.put(url, json=payload, timeout=5)
        if response.status_code == 401 and authenticate_to_core():
            response = HTTP_SESSION.put(url, json=payload, timeout=5)
        if response.ok:
            socketio.emit("metrics_update", fetch_metrics_from_core())
            return jsonify({"status": "success", "state": target_state}), 200
        return jsonify({"error": "Failed"}), response.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# --- FRONTEND ROUTING ---
@app.route("/", defaults={"path": ""})
@app.route("/<path:path>")
def serve_frontend(path: str):
    """
    Dynamically serve Angular Frontend files from the static directory.
    """
    # If the file exists in our static directory, serve it directly
    if path != "" and os.path.exists(os.path.join(app.static_folder, path)):
        return send_from_directory(app.static_folder, path)

    # Fallback to Angular index.html
    return send_from_directory(app.static_folder, "index.html")

if __name__ == "__main__":
    if IS_DEVELOPMENT:
        with CONFIG_LOCK:
            CTRLX_CONFIG['ip'] = "192.168.1.1"
            CTRLX_CONFIG['username'] = "boschrexroth"
            CTRLX_CONFIG['password'] = "boschrexroth"
        authenticate_to_core()
        socketio.run(app, host="0.0.0.0", port=5001)
    else:
        # Production mode inside the container
        socketio.run(app, host="0.0.0.0", port=5001)
