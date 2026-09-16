"""
Unit tests for the ctrlX CORE Snap installation script.

The tests verify local parsing, authentication, scheduler state handling,
package polling, and snap upload behavior without contacting a real device.

Source: GitHub Copilot
Edited by: Silas Kuschke
"""

# --- Test dependencies ---
import builtins
from unittest.mock import Mock

import pytest
import requests


class Response:
    """Minimal HTTP response double used by the mocked REST session."""

    def __init__(self, status_code=200, json_data=None, headers=None, text=""):
        self.status_code = status_code
        self._json_data = json_data
        self.headers = headers or {}
        self.text = text

    def json(self):
        return self._json_data

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.exceptions.HTTPError(self.text)


@pytest.mark.parametrize(
    ("filename", "expected"),
    [
        ("hello-world_1.0.0_amd64.snap", ("hello-world", "1.0.0")),
        ("my_app_2.4.1_arm64.snap", ("my_app", "2.4.1")),
        ("not-a-snap-file", None),
        ("app_1.0.0.snap", None),
    ],
)
def test_get_snap_metadata(install_module, filename, expected):
    """Extract package name and version only from valid snap filenames."""
    assert install_module.get_snap_metadata(filename) == expected


def test_configure_connection_uses_defaults(install_module, monkeypatch):
    """Use the documented defaults when connection prompts are empty."""
    monkeypatch.setattr(builtins, "input", Mock(side_effect=["", ""]))
    monkeypatch.setattr(install_module.getpass, "getpass", Mock(return_value=""))

    install_module.configure_connection()

    assert install_module.CTRLX_CONFIG == {
        "ip": "192.168.1.1",
        "username": "boschrexroth",
        "password": "boschrexroth",
    }


def test_fetch_bearer_token_updates_session(install_module, http_session):
    """Store the bearer token in the shared HTTP session after authentication."""
    http_session.post.return_value = Response(
        json_data={"access_token": "token-123"}
    )

    assert install_module.fetch_bearer_token() is True

    http_session.post.assert_called_once_with(
        "https://192.0.2.10/identity-manager/api/v2/auth/token",
        json={"name": "tester", "password": "secret"},
        timeout=10,
    )
    http_session.headers.update.assert_called_once_with(
        {"Authorization": "Bearer token-123"}
    )


def test_fetch_bearer_token_returns_false_without_token(install_module, http_session):
    """Reject successful HTTP responses that do not contain an access token."""
    http_session.post.return_value = Response(json_data={})

    assert install_module.fetch_bearer_token() is False
    http_session.headers.update.assert_not_called()


def test_get_datalayer_node_value_unwraps_nested_value(install_module, http_session):
    """Unwrap the nested Data Layer value format returned by ctrlX CORE."""
    http_session.get.return_value = Response(
        json_data={"value": {"value": True}}
    )

    assert install_module.get_datalayer_node_value("system/admin/busy") is True


def test_change_scheduler_state_retries_payload_formats(install_module, http_session):
    """Try the supported scheduler payload formats until one is accepted."""
    http_session.put.side_effect = [Response(status_code=400), Response(status_code=204)]

    assert install_module.change_scheduler_state("SERVICE") is True
    assert http_session.put.call_count == 2
    assert http_session.put.call_args_list[0].kwargs["json"] == {
        "type": "string",
        "value": "SERVICE",
    }
    assert install_module.WORKING_PAYLOAD_FORMAT == {
        "value": "SERVICE",
    }


def test_get_installed_package_version_returns_matching_version(
    install_module, http_session
):
    """Return the version belonging to the requested package name."""
    http_session.get.return_value = Response(
        json_data=[
            {"name": "other-app", "release": {"version": "9.0.0"}},
            {"name": "example-app", "release": {"version": "1.2.3"}},
        ]
    )

    assert install_module.get_installed_package_version("example-app") == "1.2.3"


def test_wait_for_package_version_succeeds_without_sleep(install_module, monkeypatch):
    """Finish polling immediately when the target version is available."""
    monkeypatch.setattr(
        install_module, "get_installed_package_version", Mock(return_value="1.2.3")
    )
    monkeypatch.setattr(install_module.time, "time", Mock(side_effect=[0, 1]))

    assert install_module.wait_for_package_version(
        "example-app", "1.2.3", timeout_seconds=10
    ) is True


def test_install_snap_uploads_file_and_waits_for_version(
    install_module, http_session, monkeypatch, snap_file
):
    """Upload a snap, extract its task ID, and verify the installed version."""
    http_session.post.return_value = Response(
        status_code=202,
        headers={"Location": "/package-manager/api/v1/tasks/task-42"},
    )
    wait_for_version = Mock(return_value=True)
    monkeypatch.setattr(install_module, "wait_for_package_version", wait_for_version)

    assert install_module.install_snap(
        str(snap_file), "example-app", "1.2.3"
    ) is True

    request = http_session.post.call_args
    assert request.args[0] == (
        "https://192.0.2.10/package-manager/api/v1/packages?force=true"
    )
    assert request.kwargs["headers"] == {"Accept": "application/json"}
    uploaded_filename, uploaded_file, content_type = request.kwargs["files"]["file"]
    assert uploaded_filename == snap_file.name
    assert uploaded_file.closed is True
    assert content_type == "application/octet-stream"
    wait_for_version.assert_called_once_with("example-app", "1.2.3", "task-42")


def test_install_snap_returns_false_for_rejected_upload(
    install_module, http_session, snap_file
):
    """Return failure when the package manager rejects the upload."""
    http_session.post.return_value = Response(status_code=400, text="bad snap")

    assert install_module.install_snap(
        str(snap_file), "example-app", "1.2.3"
    ) is False


def test_install_snap_returns_false_for_network_error(
    install_module, http_session, snap_file
):
    """Return failure when the upload cannot reach the device."""
    http_session.post.side_effect = requests.exceptions.ConnectionError("offline")

    assert install_module.install_snap(
        str(snap_file), "example-app", "1.2.3"
    ) is False