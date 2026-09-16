import importlib.util
from pathlib import Path
from unittest.mock import MagicMock

import pytest


SCRIPT_PATH = Path(__file__).parents[1] / "ctrlx-app-installation-automation" / "install_snap.py"


@pytest.fixture
def install_module(monkeypatch):
    """Load the script and replace its process-wide connection state."""
    spec = importlib.util.spec_from_file_location("install_snap", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    monkeypatch.setattr(module, "CTRLX_CONFIG", {
        "ip": "192.0.2.10",
        "username": "tester",
        "password": "secret",
    })
    monkeypatch.setattr(module, "HTTP_SESSION", MagicMock())
    monkeypatch.setattr(module, "WORKING_PAYLOAD_FORMAT", None)
    return module


@pytest.fixture
def http_session(install_module):
    return install_module.HTTP_SESSION


@pytest.fixture
def snap_file(tmp_path):
    path = tmp_path / "example-app_1.2.3_amd64.snap"
    path.write_bytes(b"fake snap content")
    return path