#!/bin/bash
# DESCRIPTION: Stops Zabbix and optionally WIPES all data for a factory reset.

if [ -f "vars.env" ]; then
    source vars.env
else
    INSTALL_DIR="/var/lib/zabbix"
    POD_NAME="zabbix-pod"
fi

echo "[*] Tearing down Zabbix containers and pod..."
podman pod rm -f $POD_NAME 2>/dev/null

# Check for "wipe" argument
if [[ "$1" == "--factory-reset" ]]; then
    echo "[!] WARNING: Performing Factory Reset (Deleting all Database and Trap data)..."
    sudo rm -rf $INSTALL_DIR/postgres/*
    sudo rm -rf $INSTALL_DIR/snmptraps/*
    echo "[OK] All persistent data has been deleted."
else
    echo "[*] Persistence Kept. (Use --factory-reset to wipe the database next time)."
    # Just clear the log file so it's fresh for the next run
    sudo truncate -s 0 $INSTALL_DIR/snmptraps/snmptraps.log 2>/dev/null
fi

echo "[OK] Cleanup complete."
