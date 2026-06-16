"""
Flask Backend for the ctrlX Dashboard App.

This single backend supports two run modes based on the APP_ENVIRONMENT
environment variable:

- 'production': (Default) Runs inside the ctrlX CORE snap. Serves the
  compiled Angular frontend and communicates with the local Data Layer.
- 'development': Runs on a local PC. Provides a CORS-enabled API for an
  external Angular development server (ng serve) and connects to a remote
  ctrlX CORE over the network.
"""

import os
import getpass
from threading import Lock

import requests
import urllib3
from dotenv import load_dotenv
from flask import Flask, jsonify, send_from_directory
from flask_cors import CORS

# --- INITIAL SETUP ---
# Load environment variables from .env file (especially for development)
load_dotenv()

# Disable warnings for self-signed SSL certificates
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Determine run environment
IS_DEVELOPMENT = os.getenv("APP_ENVIRONMENT") == "development"

# Global store for connection details and session object
CTRLX_CONFIG = {}
HTTP_SESSION = requests.Session()
HTTP_SESSION.verify = False
HTTP_SESSION.trust_env = False  # Always bypass system-level proxies

# Thread lock for safe credential updates
CONFIG_LOCK = Lock()

# Initialize Flask App
# In production, Angular files are in 'static'. In dev, this is not used.
app = Flask(__name__, static_folder="static", static_url_path="")

# --- ENVIRONMENT-SPECIFIC CONFIGURATION ---

if IS_DEVELOPMENT:
    # Allow requests from the local Angular dev server (typically on port 4200)
    CORS(app, resources={r"/api/*": {"origins": "http://localhost:4200"}})
    print("--- RUNNING IN DEVELOPMENT MODE ---")
else:
    print("--- RUNNING IN PRODUCTION MODE ---")

# --- DATA LAYER & AUTHENTICATION ---

METRIC_PATHS = {
    "state": "scheduler/admin/state",
    "cpu": "framework/metrics/system/cpu-utilisation-percent",
    "ram_used_percent": "framework/metrics/system/memused-percent",
    "storage_used_percent": "framework/metrics/system/storage-used-percent",
}

def authenticate_to_core() -> bool:
    """
    Authenticates against the ctrlX CORE. The method depends on the environment.
    - Production: Uses local token from snap environment (not implemented here).
    - Development: Performs a remote login with user credentials.
    """
    if not IS_DEVELOPMENT:
        # In production on ctrlX, auth is handled by the system context
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

# --- API & SERVING ROUTES ---

@app.route("/api/metrics", methods=["GET"])
def get_metrics() -> tuple:
    """API endpoint to fetch all system metrics."""
    with CONFIG_LOCK:
        # In production, the IP is always localhost. In dev, it's the configured IP.
        ip = "127.0.0.1" if not IS_DEVELOPMENT else CTRLX_CONFIG.get("ip", "localhost")

    base_url = f"https://{ip}/automation/api/v2/nodes"
    metrics_data = {}

    for key, path in METRIC_PATHS.items():
        try:
            response = HTTP_SESSION.get(f"{base_url}/{path}", timeout=2)

            if response.status_code == 401:  # Token expired
                print("[Info] Token expired or invalid. Re-authenticating...")
                if not authenticate_to_core(): # Re-login
                    metrics_data[key] = "Auth Error"
                    continue
                response = HTTP_SESSION.get(f"{base_url}/{path}", timeout=2) # Retry

            if response.ok:
                raw_val = response.json().get("value")
                if key == "state" and isinstance(raw_val, dict):
                    metrics_data[key] = raw_val.get("state", "UNKNOWN")
                else:
                    metrics_data[key] = raw_val
            else:
                metrics_data[key] = f"HTTP {response.status_code}"
        except requests.exceptions.RequestException:
            metrics_data[key] = "Request Error"

    return jsonify(metrics_data), 200

@app.route("/", defaults={"path": ""})
@app.route("/<path:path>")
def serve_frontend(path: str):
    """
    Serves the compiled Angular frontend.
    This route is only active in 'production' mode.
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
        
        # Perform initial remote authentication
        authenticate_to_core()

    # Start the Flask web server
    # Port 5001 is used to avoid conflicts with other common services
    app.run(host="0.0.0.0", port=5001)
