"""
Fixtures for the ctrlX CORE installation tests.

The fixtures isolate the installation script from real ctrlX CORE devices and
provide temporary local files for snap and license upload tests.

Source: GitHub Copilot
Edited by: Silas Kuschke
"""

import importlib.util
from pathlib import Path
from unittest.mock import MagicMock, Mock

import pytest


# Locate the script relative to the repository-wide test directory.
SCRIPT_PATH = Path(__file__).parents[1] / "ctrlx-app-installation-automation" / "install_snap.py"
LICENSE_SCRIPT_PATH = Path(__file__).parents[1] / "ctrlx-licensing-installation" / "install_license.py"


@pytest.fixture
def install_module(monkeypatch):
    """Load the script with isolated configuration and HTTP session state."""
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
    """Return the mocked HTTP session used by the loaded script."""
    return install_module.HTTP_SESSION


@pytest.fixture
def snap_file(tmp_path):
    """Create a temporary snap file with a valid package filename."""
    path = tmp_path / "example-app_1.2.3_amd64.snap"
    path.write_bytes(b"fake snap content")
    return path


@pytest.fixture
def license_module(monkeypatch, tmp_path):
    """Load the licensing script with isolated storage and REST state."""
    spec = importlib.util.spec_from_file_location(
        "install_license", LICENSE_SCRIPT_PATH
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    monkeypatch.setattr(module, "HTTP_SESSION", MagicMock())
    monkeypatch.setattr(module, "CORE_CONFIG_FILE", tmp_path / "ctrlx_cores.json")
    monkeypatch.setattr(module, "LICENSE_FOLDER", tmp_path / "licenses")
    monkeypatch.setattr(module.keyring, "get_password", Mock(return_value=None))
    monkeypatch.setattr(module.keyring, "set_password", Mock())
    return module


@pytest.fixture
def license_file(tmp_path):
    """Create a temporary license file named after a valid device serial."""
    license_folder = tmp_path / "licenses"
    license_folder.mkdir()
    path = license_folder / "1234567890123.bin"
    path.write_bytes(b"fake license content")
    return path