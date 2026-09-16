"""
Unit tests for the ctrlX CORE licensing script.

The tests cover credential storage, serial number handling, license upload,
verification, and session cleanup without contacting a real ctrlX CORE.

Source: GitHub Copilot
Edited by: Silas Kuschke
"""

# --- Test dependencies ---
from unittest.mock import Mock

import requests


class Response:
    """Minimal HTTP response double used by the licensing tests."""

    def __init__(self, status_code=200, json_data=None, text=""):
        self.status_code = status_code
        self._json_data = json_data
        self.text = text

    def json(self):
        return self._json_data

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.exceptions.HTTPError(self.text)


def test_save_and_load_core_uses_keyring(license_module, monkeypatch):
    """Store the password in keyring and only metadata in the JSON file."""
    password_store = {}

    def set_password(service, username, password):
        password_store[(service, username)] = password

    def get_password(service, username):
        return password_store.get((service, username))

    monkeypatch.setattr(license_module.keyring, "set_password", set_password)
    monkeypatch.setattr(license_module.keyring, "get_password", get_password)

    license_module.save_core("192.0.2.10", "tester", "secret")
    saved_text = license_module.CORE_CONFIG_FILE.read_text(encoding="utf-8")

    assert "secret" not in saved_text
    assert license_module.load_cores() == {
        "192.0.2.10": {"username": "tester", "password": "secret"}
    }


def test_fetch_serial_number_accepts_valid_nested_value(license_module):
    """Extract a valid 13-digit serial number from a nested Data Layer value."""
    license_module.HTTP_SESSION.get.return_value = Response(
        json_data={"value": {"value": "1234567890123"}}
    )

    assert license_module.fetch_serial_number("192.0.2.10") == "1234567890123"


def test_fetch_serial_number_rejects_invalid_value(license_module):
    """Reject device IDs that do not contain exactly 13 digits."""
    license_module.HTTP_SESSION.get.return_value = Response(
        json_data={"value": "not-a-serial"}
    )

    assert license_module.fetch_serial_number("192.0.2.10") is None


def test_upload_license_accepts_already_processed_response(
    license_module, license_file
):
    """Treat the documented already-processed response as success."""
    license_module.HTTP_SESSION.put.return_value = Response(
        status_code=400,
        json_data={"detailedDiagnosisCode": "0C7A0202"},
    )

    assert license_module.upload_license(
        "192.0.2.10", str(license_file)
    ) is True


def test_upload_license_rejects_server_error(license_module, license_file):
    """Return failure when the license manager rejects the upload."""
    license_module.HTTP_SESSION.put.return_value = Response(
        status_code=400,
        json_data={"dynamicDescription": "invalid license"},
    )

    assert license_module.upload_license(
        "192.0.2.10", str(license_file)
    ) is False


def test_verify_license_installation_finds_capability(license_module):
    """Find a matching license identifier in a capability response."""
    license_module.HTTP_SESSION.get.return_value = Response(
        json_data=[{"id": "license-123"}],
        text='[{"id": "license-123"}]',
    )

    assert license_module.verify_license_installation(
        "192.0.2.10", "license-123"
    ) is True


def test_process_device_cleans_up_session(
    license_module, monkeypatch, license_file
):
    """Run a successful device flow and always close the REST session."""
    monkeypatch.setattr(
        license_module,
        "fetch_bearer_token",
        Mock(return_value=True),
    )
    monkeypatch.setattr(
        license_module,
        "fetch_serial_number",
        Mock(return_value="1234567890123"),
    )
    monkeypatch.setattr(license_module, "upload_license", Mock(return_value=True))
    monkeypatch.setattr(
        license_module,
        "verify_license_installation",
        Mock(return_value=True),
    )

    assert license_module.process_device(
        "192.0.2.10", {"username": "tester", "password": "secret"}
    ) is True
    license_module.HTTP_SESSION.delete.assert_called_once_with(
        "https://192.0.2.10/identity-manager/api/v2/auth/token",
        timeout=10,
    )