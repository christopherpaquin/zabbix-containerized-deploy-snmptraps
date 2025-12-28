#!/bin/bash
# DESCRIPTION: Stops and removes Zabbix containers/pods and clears trap logs.

POD_NAME="zabbix-pod"
INSTALL_DIR="/var/lib/zabbix"

echo "[*] Tearing down Zabbix environment..."

# Remove containers and pod
podman pod rm -f $POD_NAME 2>/dev/null

# Clear the shared trap log to prevent stale data on redeploy
if [ -f "$INSTALL_DIR/snmptraps/snmptraps.log" ]; then
    echo "[*] Clearing old trap logs..."
    cat /dev/null > "$INSTALL_DIR/snmptraps/snmptraps.log"
fi

echo "[OK] Cleanup complete."
