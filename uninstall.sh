#!/bin/bash

# Rootkit Uninstallation Script
# This script removes the rootkit and cleans up persistence mechanisms

set -e

# Get rootkit name from user input or use default
if [ -z "$1" ]; then
    echo "Usage: $0 <rootkit_name>"
    echo "Example: $0 project"
    exit 1
fi

ROOTKIT_NAME="$1"
KERNEL_VERSION=$(uname -r)
INSTALL_DIR="/lib/modules/${KERNEL_VERSION}/kernel/drivers"
MODULE_DIR="${INSTALL_DIR}/linux-space"
MODULE_CONF="/etc/modules-load.d/${ROOTKIT_NAME}.conf"

echo "[+] Uninstalling rootkit '${ROOTKIT_NAME}'..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run as root (use sudo)"
    exit 1
fi

# Unload module if loaded
if lsmod | grep -q "${ROOTKIT_NAME}"; then
    echo "[+] Unloading rootkit module..."
    rmmod "${ROOTKIT_NAME}" || modprobe -r "${ROOTKIT_NAME}"
else
    echo "[!] Module ${ROOTKIT_NAME} not currently loaded"
fi

# Remove auto-load configuration
if [ -f "${MODULE_CONF}" ]; then
    echo "[+] Removing auto-load configuration: ${MODULE_CONF}"
    rm -f "${MODULE_CONF}"
else
    echo "[!] Auto-load configuration not found"
fi

# Remove module file
if [ -f "${MODULE_DIR}/${ROOTKIT_NAME}.ko" ]; then
    echo "[+] Removing module file: ${MODULE_DIR}/${ROOTKIT_NAME}.ko"
    rm -f "${MODULE_DIR}/${ROOTKIT_NAME}.ko"
else
    echo "[!] Module file not found in system location"
fi

# Remove module directory if empty
if [ -d "${MODULE_DIR}" ] && [ -z "$(ls -A ${MODULE_DIR})" ]; then
    echo "[+] Removing empty module directory: ${MODULE_DIR}"
    rmdir "${MODULE_DIR}"
fi

# Update module dependencies
echo "[+] Updating module dependencies..."
depmod -a

# Verify removal
if ! lsmod | grep -q "${ROOTKIT_NAME}"; then
    echo "[+] Rootkit successfully uninstalled!"
    echo "[+] Module will not load on next reboot"
else
    echo "[-] Warning: Module may still be loaded"
fi

echo "[+] Uninstallation complete!"
