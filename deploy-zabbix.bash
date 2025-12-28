#!/bin/bash
# DESCRIPTION: Deploys Zabbix 7.2 using variables from vars.env
# Includes automated Firewall and Permission configuration.

# Load variables
if [ -f "vars.env" ]; then
    source vars.env
else
    echo "[ERROR] vars.env not found! Please create it from the template."
    exit 1
fi

echo "[*] Starting Zabbix v7.2 Deployment for Pod: $POD_NAME"

# --- 1. FIREWALL CONFIGURATION ---
if systemctl is-active --quiet firewalld; then
    echo "[*] Firewall detected. Opening ports 162/udp (SNMP) and 80/tcp (Web)..."
    sudo firewall-cmd --add-port=162/udp --permanent >/dev/null 2>&1
    sudo firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1
    sudo firewall-cmd --reload >/dev/null 2>&1
    echo "[OK] Firewall updated."
else
    echo "[!] firewalld is not running. Ensure your network path is open."
fi

# --- 2. PREP: Directories & Permissions ---
mkdir -p $INSTALL_DIR/{postgres,snmptraps,mibs,export,enc,extra_cfg}
chown -R 1001:1001 $INSTALL_DIR/snmptraps
chmod -R 777 $INSTALL_DIR/snmptraps
[ -x "$(command -v chcon)" ] && chcon -R -t container_file_t $INSTALL_DIR/snmptraps

# --- 3. PREP: SNMP Config ---
cat <<EOF > $INSTALL_DIR/extra_cfg/zabbix_server_snmp_traps.conf
StartSNMPTrapper=1
SNMPTrapperFile=/var/lib/zabbix/snmptraps/snmptraps.log
EOF

# --- 4. POD & CONTAINERS ---
podman pod rm -f $POD_NAME 2>/dev/null
podman pod create --name $POD_NAME --restart always -p 80:8080 -p 443:8443 -p 10051:10051 -p 162:1162/udp

# Database
podman run -d --name postgres-server --pod $POD_NAME \
    -e POSTGRES_USER=zabbix -e POSTGRES_PASSWORD=$DB_PASSWORD -e POSTGRES_DB=zabbix \
    -v $INSTALL_DIR/postgres:/var/lib/postgresql/data:Z postgres:16-alpine

echo "[*] Waiting for DB..." && sleep 15

# Traps
podman run -d --name zabbix-snmptraps --pod $POD_NAME \
    -e ZBX_SNMP_COMMUNITY=$SNMP_COMMUNITY \
    -v $INSTALL_DIR/snmptraps:/var/lib/zabbix/snmptraps:z,U zabbix/zabbix-snmptraps:alpine-7.2-latest

# Server
podman run -d --name zabbix-server-pgsql --pod $POD_NAME \
    -e DB_SERVER_HOST=127.0.0.1 -e POSTGRES_USER=zabbix -e POSTGRES_PASSWORD=$DB_PASSWORD -e POSTGRES_DB=zabbix \
    -v $INSTALL_DIR/snmptraps:/var/lib/zabbix/snmptraps:z,U \
    -v $INSTALL_DIR/extra_cfg/zabbix_server_snmp_traps.conf:/etc/zabbix/zabbix_server_snmp_traps.conf:Z \
    zabbix/zabbix-server-pgsql:alpine-7.2-latest

# Web
podman run -d --name zabbix-web-nginx-pgsql --pod $POD_NAME \
    -e ZBX_SERVER_HOST=127.0.0.1 -e DB_SERVER_HOST=127.0.0.1 \
    -e POSTGRES_USER=zabbix -e POSTGRES_PASSWORD=$DB_PASSWORD -e POSTGRES_DB=zabbix \
    zabbix/zabbix-web-nginx-pgsql:alpine-7.2-latest

echo "[OK] Deployment Complete."
