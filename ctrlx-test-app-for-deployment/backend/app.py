"""
Flask Backend for the ctrlX Dashboard App.

This single backend supports two run modes based on the APP_ENVIRONMENT
environment variable:
- 'production': (Default) Runs inside the ctrlX CORE snap. Serves the
  compiled Angular frontend and communicates with the local Data Layer.
- 'development': Runs on a local PC. Provides a CORS-enabled API for an
  external Angular development server (ng serve) and connects to a remote
  ctrlX CORE over the network.

Now powered by WebSockets (Flask-SocketIO) for real-time metric pushes.
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
from flask_socketio import SocketIO, emit  # <-- Neu hinzugefügt

# --- INITIAL SETUP ---
load_dotenv()
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

IS_DEVELOPMENT = os.getenv("APP_ENVIRONMENT") == "development"

# Global store for connection details and session object
CTRLX_CONFIG = {}
HTTP_SESSION = requests.Session()
HTTP_SESSION.verify = False
HTTP_SESSION.trust_env = False  # Always bypass system-level proxies

CONFIG_LOCK = Lock()

# Initialize Flask App & SocketIO
app = Flask(__name__, static_folder="static", static_url_path="")

# SocketIO Setup mit CORS-Freigabe für Entwicklungsumgebung
if IS_DEVELOPMENT:
    CORS(app, resources={r"/api/*": {"origins": "http://localhost:4200"}})
    socketio = SocketIO(app, cors_allowed_origins="http://localhost:4200", async_mode="eventlet")
    print("--- RUNNING IN DEVELOPMENT MODE (WEBSOCKETS ACTIVE) ---")
else:
    socketio = SocketIO(app, cors_allowed_origins="*", async_mode="eventlet")
    print("--- RUNNING IN PRODUCTION MODE (WEBSOCKETS ACTIVE) ---")

# Thread lock für die Hintergrund-Tasks von SocketIO
THREAD_LOCK = Lock()
background_thread = None

# --- DATA LAYER & AUTHENTICATION ---
METRIC_PATHS = {
    "state": "scheduler/admin/state",
    "cpu": "framework/metrics/system/cpu-utilisation-percent",
    "ram_used_percent": "framework/metrics/system/memused-percent",
    "storage_used_percent": "framework/metrics/system/storage-used-percent",
}

def authenticate_to_core() -> bool:
    """Authenticates against the ctrlX CORE."""
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
    """Helper method to query all raw metrics from the ctrlX CORE."""
    with CONFIG_LOCK:
        ip = "127.0.0.1" if not IS_DEVELOPMENT else CTRLX_CONFIG.get("ip", "localhost")
        
    base_url = f"https://{ip}/automation/api/v2/nodes"
    metrics_data = {}
    
    for key, path in METRIC_PATHS.items():
        try:
            response = HTTP_SESSION.get(f"{base_url}/{path}", timeout=2)
            if response.status_code == 401:  # Token abgelaufen
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
def metrics_polling_task():
    """
    Zyklischer Hintergrund-Task, der die ctrlX-Daten alle 2 Sekunden ausliest
    und via WebSocket an alle verbundenen Web-Clients pushed.
    """
    print("[WebSocket] Background polling task started.")
    while True:
        metrics = fetch_metrics_from_core()
        # Pushe Daten über den Kanal 'metrics_update'
        socketio.emit("metrics_update", metrics)
        socketio.sleep(2)  # Eventlet-kompatibles Sleep (wichtig!)

# --- WEBSOCKET EVENTS ---
@socketio.on("connect")
def handle_connect():
    """Wird ausgelöst, wenn sich ein Browser-Client verbindet."""
    print(f"[WebSocket] Client connected: {request.sid}")
    
    # Sofortiger Push beim ersten Verbindungsaufbau, damit das UI nicht leer startet
    initial_metrics = fetch_metrics_from_core()
    emit("metrics_update", initial_metrics)
    
    # Starte den Hintergrund-Polling-Thread, falls er noch nicht läuft
    global background_thread
    with THREAD_LOCK:
        if background_thread is None:
            background_thread = socketio.start_background_task(target=metrics_polling_task)

@socketio.on("disconnect")
def handle_disconnect():
    print(f"[WebSocket] Client disconnected: {request.sid}")

# --- REST-API FÜR STATE-WECHSEL (Bleibt bestehen) ---
@app.route("/api/state", methods=["POST"])
def set_scheduler_state() -> tuple:
    """API endpoint to change the controller's scheduler state."""
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
            # Sofort neues Datenpaket über WebSockets an alle Clients senden,
            # um die Umschaltung augenblicklich im UI zu zeigen!
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
    """Serves the compiled Angular frontend (production only)."""
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
        with CONFIG_LOCK:
            ip_in = input("Enter ctrlX IP Address [192.168.1.1]: ").strip()
            CTRLX_CONFIG['ip'] = ip_in or "192.168.1.1"
            user_in = input("Enter Username [boschrexroth]: ").strip()
            CTRLX_CONFIG['username'] = user_in or "boschrexroth"
            pass_in = getpass.getpass("Enter Password [boschrexroth]: ").strip()
            CTRLX_CONFIG['password'] = pass_in or "boschrexroth"
        
        authenticate_to_core()

    # Wichtig: app.run() wird durch socketio.run() ersetzt!
    socketio.run(app, host="0.0.0.0", port=5001)
