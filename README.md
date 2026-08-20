# bachelor-thesis-silas-kuschke
Implementation of x86 and arm64 build snaps for industrial ctrlX controllers from Bosch Rexroth.

The currently working code is located on the `main` branch. The `sdk-vm-automation` directory contains the `install_sdk.bat` batch file. Place this file in a new, otherwise empty directory and run it by double-clicking it. The setup script creates a virtual machine with the ctrlX SDK and automatically installs the required software packages.

The script supports selecting different ctrlX OS versions and creating multiple virtual machines, similar to ctrlX Works. Since multiple ctrlX OS versions are handled by the script, it is not necessary to install multiple software versions on the host computer, as would be required with ctrlX Works.

## Proxy Configuration

The user can choose between three proxy options:

- Bosch proxy
- User-configured proxy
- No proxy

Status as of 2026-08-20: The Bosch proxy and no-proxy options have been tested successfully. The user-configured proxy has not yet been tested.

Before running the script, the RB Local Proxy Manager must be enabled (only for Bosch employees). During the first execution of the batch script, QEMU must also be installed in the newly created project directory.

After the settings have been entered in the terminal and a virtual machine has been selected, VS Code opens and connects to the virtual machine via SSH. The required VS Code extensions are also installed on the virtual machine, allowing snap development to start immediately.

## Cross-Compilation for the ARM-Based ctrlX CORE X3

1. Add the prebuilt wheel files to `snapcraft.yaml`.

2. If wheel files are not available for the required libraries, use one of the following options:

    a. Run the LXD-based emulator, which is pre-installed on the virtual machines, to emulate the ARM processor and build the wheel files.
        - Advantage: No additional hardware is required.
        - Disadvantage: Snap builds take considerably longer.

    b. Enable SSH access for a ctrlX CORE X3 and build natively on ARM. See the [Bosch Rexroth guide](https://community.boschrexroth.com/ctrlx-automation-how-tos-qmglrz33/post/how-to-activate-ssh-communication-in-a-ctrlx-core-XQrXXMm5aZXTI7f).
        - Advantage: Shorter build times because no emulation is required.
        - Disadvantage: For security reasons, the CORE should no longer be used in production.

    c. Use the additional script from the `raspi-automation` branch to flash a Raspberry Pi automatically and access it via SSH. This script is not finished yet.
        - Advantage: Shorter build times because no emulation is required.
        - Disadvantage: Additional hardware is required.
        - This is the recommended way to build snaps using cross-compilation.

## Additional Utility Scripts

The `ctrlx-app-installation-automation` directory contains `install_snap.py`, which installs a snap on a CORE. The script has been tested successfully several times. In addition, it uses the ctrlX OS REST API.

### Installing a Snap

Open a VS Code terminal, change to the `ctrlx-app-installation-automation` directory, and run:

    python -m venv .venv
    .\.venv\Scripts\Activate.ps1
    python -m pip install --upgrade pip
    pip install -r requirements.txt
    python .\install_snap.py

The script then prompts for the CORE IP address and the absolute path to the snap file. The `ctrlx-app-installation-automation` directory includes a C++ Hello World snap that writes a Hello World message to the CORE logs and can be used for testing.

### Installing Licenses

The `ctrlx-licensing-installation` directory can install multiple license files on multiple COREs. Create a `licenses` subdirectory there and place the license files in it. In a VS Code terminal, change to the `ctrlx-licensing-installation` directory and run:

    .\.venv\Scripts\Activate.ps1
    python .\install_license.py

The script supports selecting one or more COREs. CORE IP addresses can also be stored automatically in a list to avoid entering them manually each time. Based on the serial numbers, the script identifies the corresponding license file and uploads it to the matching CORE. The script has been tested successfully several times, although testing was limited to one CORE.

### ctrlX CORE Operating Mode Test

The `ctrlx-flask-app-test` directory contains a test script for changing the operating mode of a single CORE through the REST API. It was created for testing purposes but is functional. In a VS Code terminal, change to the `ctrlx-flask-app-test` directory and run:

    .\.venv\Scripts\Activate.ps1
    python .\app.py

The `ctrlx-test-app-for-deployment` directory contains a web server packaged as a snap. It is intended to change the operating mode of the CORE locally and query memory and CPU usage. The snap is currently not functional and was created for testing purposes only.

## Documentation

The `docs` directory contains documentation for individual functions. To open the generated documentation, change to `docs/_build/html` and run:

    start index.html

## AI-Related Work

GitHub Copilot Chat has been configured in VS Code with skills from this repository. Skills for the Python scripts still need to be created.

Additional how-to documentation for the scripts and batch file is planned after completion of the bachelor's thesis.
