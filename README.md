# bachelor-thesis-silas-kuschke
Implementation of x86 and arm64 build snaps for industrial ctrlX controllers from Bosch Rexroth.

The currently working code is located on the `main` branch. The `sdk-vm-automation` directory contains the `install_sdk.bat` batch file. It creates and starts Ubuntu-based ctrlX SDK build environments in QEMU on a Windows development computer. The virtual machines are provisioned automatically with Cloud-Init and include the software required for ctrlX app development and snap builds.

### SDK VM Automation

Place `install_sdk.bat` in a new, otherwise empty directory and start it by double-clicking the file. During the first run, the script checks the required tools and requests administrator rights when components are missing. It can install Visual Studio Code, the required VS Code extensions and local QEMU. QEMU must be installed in the project directory created for the script so that the workflow remains self-contained.

After the prerequisites are available, the main menu provides two workflows:

1. **Start an existing VM**

    Select an already downloaded Ubuntu Core 22 or Ubuntu Core 24 image. The script starts the corresponding virtual machine with QEMU and forwards SSH through port `11022`. The VM can be opened in VS Code using the SSH alias `ctrlx-sdk-vm`.

2. **Download and configure a new VM**

    Select the ctrlX OS version. The script maps ctrlX OS 1.x, 2.x and 3.x to the appropriate Ubuntu Core 22 environment and ctrlX OS 4.x to Ubuntu Core 24. It then selects the required download, configures the network and proxy settings, downloads the official Bosch Rexroth build environment and creates the Cloud-Init files in `instances/cidata`.

    The generated Cloud-Init configuration creates the build user, installs the required packages, configures SSH and runs the SDK setup inside the VM. It also creates a NoCloud ISO used during the first boot. After validation, the VM can be started directly from the setup script. Multiple VM versions can be kept in the same project directory and selected from the main menu, so separate host installations are not required.

Once the VM is running, VS Code can connect to it through Remote-SSH. The script waits for the VM and its VS Code Server to become available, then installs the configured extensions in the remote environment. This provides a ready-to-use ctrlX SDK build environment without installing the different SDK versions directly on the Windows host.

## Proxy Configuration

The user can choose between three proxy options:

- Bosch proxy
- User-configured proxy
- No proxy

Status as of 2026-08-20: The Bosch proxy and no-proxy options have been tested successfully. The user-configured proxy has not yet been tested.

Before running the script, the RB Local Proxy Manager must be enabled (only for Bosch employees). During the first execution of the batch script, QEMU must also be installed in the newly created project directory.

After the settings have been entered in the terminal and a virtual machine has been selected, VS Code opens and connects to the virtual machine via SSH. The required VS Code extensions are also installed on the virtual machine, allowing snap development to start immediately.

## Cross-Compilation for the ARM-Based ctrlX CORE X3

### Cross-Compilation in general for ctrlX OS Snaps

1. Add the prebuilt wheel files to `snapcraft.yaml`.

2. If wheel files are not available for the required libraries, use one of the following options:

    a. Run the LXD-based emulator, which is pre-installed on the virtual machines, to emulate the ARM processor and build the wheel files.
        - Advantage: No additional hardware is required.
        - Disadvantage: Snap builds take considerably longer.

    b. Enable SSH access for a ctrlX CORE X3 and build natively on ARM. See the [Bosch Rexroth guide](https://community.boschrexroth.com/ctrlx-automation-how-tos-qmglrz33/post/how-to-activate-ssh-communication-in-a-ctrlx-core-XQrXXMm5aZXTI7f).
        - Advantage: Shorter build times because no emulation is required.
        - Disadvantage: For security reasons, the CORE should no longer be used in production.

    c. Use the `raspi-preparation/prepare_raspberry_pi.bat` workflow described above to flash and provision a Raspberry Pi automatically.
        - Advantage: Shorter build times because no emulation is required.
        - Disadvantage: Additional hardware is required.
        - This is the recommended way to build snaps using cross-compilation.

### Raspberry Pi Preparation

The `raspi-preparation` directory contains `prepare_raspberry_pi.bat`. The script prepares a Raspberry Pi 5 with Ubuntu Server ARM64 so it can be used as a native ARM64 build system. It can also connect to a Raspberry Pi that has already been prepared.

Before starting, install Raspberry Pi Imager and connect the SD card to the Windows development computer. The script checks for Visual Studio Code, the Remote-SSH extension and the required development extensions. Missing components can be installed automatically with administrator rights. An SSH key is generated once and reused for later connections.

Start the script by double-clicking `raspi-preparation/prepare_raspberry_pi.bat`. The main menu provides two options:

1. **Connect to an existing Raspberry Pi**

    Enter the Pi hostname or IP address and the SSH username. The default values are `sdk-pi`, `192.168.1.100` and the SSH alias `ctrlx-pi`. The script configures VS Code Remote-SSH, tests the connection and opens the remote home directory in VS Code. It then waits for the VS Code Server and installs the configured remote extensions.

2. **Download Ubuntu and prepare an SD card**

    Select the Ubuntu version that matches the target ctrlX OS version:

    - Ubuntu Server 22.04.5 ARM64 for ctrlX OS 1.x, 2.x and 3.x
    - Ubuntu Server 24.04.3 ARM64 for ctrlX OS 4.x

    Next, select the Internet connection type for the Windows computer: Bosch proxy, company proxy or direct Internet access. The script downloads the official Ubuntu image, verifies its SHA256 checksum and extracts it for Raspberry Pi Imager. It asks for the SD card drive letter, resolves the corresponding physical device and requires confirmation before erasing it.

    The script then asks for the Wi-Fi credentials and optional Raspberry Pi proxy settings. The default configuration uses country code `DE`, keyboard layout `de`, locale `de_DE.UTF-8`, time zone `Europe/Berlin`, static Ethernet address `192.168.1.100/24` and DHCP on `wlan0`. The Windows development computer receives an address in the same `192.168.1.x/24` network.

    After flashing, enter the drive letter of the Ubuntu boot partition. The script writes the Cloud-Init files `meta-data`, `user-data` and `network-config`, configures the NoCloud data source and safely ejects the SD card. On first boot, Ubuntu automatically creates the `sdk-pi` user, enables SSH, configures Ethernet and Wi-Fi, installs the ctrlX SDK and Snapcraft, and prepares USB logging through the `CTRLXLOG` volume mounted at `/mnt/ctrlx-logs`.

Insert the prepared SD card into the Raspberry Pi and power it on. After the first boot has completed, use option 1 or connect with the configured SSH alias `ctrlx-pi`. The Pi can then be used to build ARM64 snaps natively without emulation.


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

The `docs` directory contains documentation for individual python utility scripts. To open the generated documentation, change to `docs/_build/html` and run:

    start index.html

The workflow diagrams are available as Mermaid source files:

- [SDK VM installation workflow](sdk-vm-automation/docs/flowchart.mmd)
- [Raspberry Pi preparation workflow](raspi-preparation/docs/prepare_raspberry_pi_flowchart.mmd)

## AI-Related Work

GitHub Copilot Chat has been configured in VS Code with skills from this repository. Skills for the Python scripts still need to be created.

Additional how-to documentation for the scripts and batch file is planned after completion of the bachelor's thesis.
