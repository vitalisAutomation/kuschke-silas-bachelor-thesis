Project API Reference
=====================

This page is generated from the current Python modules. The sections below add
the operational context that is not visible in individual function signatures.

Core Dashboard Backend
----------------------

.. automodule:: app
   :members:
   :undoc-members:
   :show-inheritance:
   :no-index:

Snap Installation Automation
----------------------------

``install_snap.py`` installs a local ``.snap`` package through the ctrlX CORE
Package Manager REST API.

Workflow:

1. Enter the CORE address, username, password, and local snap path.
2. Validate the snap filename as
   ``<name>_<version>_<architecture>.snap``.
3. Authenticate through
   ``POST /identity-manager/api/v2/auth/token``.
4. Read the current Scheduler state and package version.
5. Switch to ``SERVICE`` mode when required, waiting for the system and
   scheduler to become ready.
6. Upload the snap through
   ``POST /package-manager/api/v1/packages?force=true``.
7. Poll the Package Manager until the requested version is installed.
8. Restore the original Scheduler state and delete the REST token.

The script tries several payload formats when changing the Scheduler state to
support different ctrlX OS versions. A successful format is cached for the
remainder of the process.

Security note: the session currently sets ``verify = False`` and disables
certificate warnings. This protects neither the CORE identity nor the
credentials and bearer token against a man-in-the-middle attack. A trusted
CORE certificate or CA bundle should be configured instead.

.. automodule:: install_snap
   :members:
   :undoc-members:
   :show-inheritance:
   :no-index:

License Installation Automation
-------------------------------

``install_license.py`` installs offline license capability response files for
one or more saved CORE devices.

Preparation:

* Place files named ``<13-digit-serial>.bin`` in the local ``licenses``
   directory.
* The JSON configuration stores only CORE addresses and usernames.
* Passwords are stored through the operating-system credential manager using
   ``keyring``.

Single-device workflow:

1. Enter the CORE address, username, and password.
2. Authenticate through
    ``POST /identity-manager/api/v2/auth/token``.
3. Read the 13-digit device identifier from the Data Layer typeplate node.
4. Select the matching ``licenses/<serial>.bin`` file.
5. Upload it as multipart form data through
    ``PUT /license-manager/api/v1/capabilities?withChangeReport=true``.
6. Delete the REST token in a ``finally`` block.

Multi-device mode loads the saved devices and processes them sequentially.
The upload treats the documented/observed diagnosis code ``0C7A0202`` and an
``already processed`` message as an idempotent success.

The module also provides ``verify_license_installation`` for checking active
capabilities, but the current ``process_device`` workflow does not call it
after upload. Therefore a successful upload message is not by itself a
verified license activation.

Security note: TLS certificate verification is currently disabled globally by
``HTTP_SESSION.verify = False``. For secure operation, configure
``requests`` with a trusted CA or CORE certificate, for example
``HTTP_SESSION.verify = "certs/core-ca.pem"``. Never export or distribute the
CORE's private key. The configuration and license directories are excluded
from version control by the repository's ``.gitignore``.

.. automodule:: install_license
   :members:
   :undoc-members:
   :show-inheritance:
   :no-index:
