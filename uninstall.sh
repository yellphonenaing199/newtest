#!/bin/bash

# Rootkit Uninstall Script

set -e

# Ensure root privileges
if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run as root"
    exit 1
fi

# Prompt for rootkit/module name
read -p "Enter the rootkit (module) name to uninstall: " ROOTKIT_NAME
if [ -z "$ROOTKIT_NAME" ]; then
    echo "[-] Module name is required"
    exit 1
fi

KERNEL_VERSION=$(uname -r)
MODULE_PATH="/lib/modules/${KERNEL_VERSION}/kernel/drivers/misc/${ROOTKIT_NAME}.ko"
MODULE_CONF="/etc/modules-load.d/${ROOTKIT_NAME}.conf"

echo "[*] Uninstalling rootkit: $ROOTKIT_NAME"

# Unload the module if loaded
if lsmod | grep -q "^$ROOTKIT_NAME"; then
    echo "[+] Unloading kernel module..."
    rmmod "$ROOTKIT_NAME" || {
        echo "[!] Failed to unload module. Try rebooting into safe mode."
        exit 1
    }
else
    echo "[*] Module is not currently loaded"
fi

# Remove kernel module file
if [ -f "$MODULE_PATH" ]; then
    echo "[+] Deleting module file: $MODULE_PATH"
    rm -f "$MODULE_PATH"
else
    echo "[*] Module file not found at $MODULE_PATH"
fi

# Remove auto-load config
if [ -f "$MODULE_CONF" ]; then
    echo "[+] Removing auto-load config: $MODULE_CONF"
    rm -f "$MODULE_CONF"
fi

# Rebuild module dependencies
echo "[+] Updating module dependencies..."
depmod -a

echo "[✓] Uninstallation complete. Reboot recommended to ensure full removal."
