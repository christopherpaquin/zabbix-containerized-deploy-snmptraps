#!/bin/bash
# DESCRIPTION: Stops Zabbix and optionally WIPES all data for a factory reset.
# Includes automated Firewall cleanup.

if [ -f "vars.env" ]; then
    source vars.env
else
    INSTALL_DIR="/var/lib/zabbix"
    POD_NAME="zabbix-pod"
fi

echo "[*] Tearing down Zabbix containers and pod..."
podman pod rm -f $POD_NAME 2>/dev/null

# --- FIREWALL CLEANUP ---
if systemctl is-active --quiet firewalld; then
    echo "[*] Closing firewall ports 162/udp and 80/tcp..."
    sudo firewall-cmd --remove-port=162/udp --permanent >/dev/null 2>&1
    sudo firewall-cmd --remove-port=80/tcp --permanent >/dev/null 2>&1
    sudo firewall-cmd --reload >/dev/null 2>&1
    echo "[OK] Firewall ports closed."
fi

# --- DATA CLEANUP ---
if [[ "$1" == "--factory-reset" ]]; then
    echo "[!] WARNING: Performing Factory Reset..."
    # Deleting the directory contents including hidden files
    sudo find $INSTALL_DIR/postgres -mindepth 1 -delete
    sudo find $INSTALL_DIR/snmptraps -mindepth 1 -delete
    # Optional: Clear MIBs if you want a true 100% reset
    # sudo find $INSTALL_DIR/mibs -mindepth 1 -delete 
    echo "[OK] All persistent data has been deleted."
else
    echo "[*] Persistence Kept. (Use --factory-reset to wipe data next time)."
    # Clean the trap log so it doesn't grow indefinitely between restarts
    if [ -f "$INSTALL_DIR/snmptraps/snmptraps.log" ]; then
        sudo truncate -s 0 "$INSTALL_DIR/snmptraps/snmptraps.log"
    fi
fi

echo "[OK] Cleanup complete."
