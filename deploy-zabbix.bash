#!/bin/bash
# DESCRIPTION: Deploys Zabbix 7.2 using variables from vars.env
# Optimized for RHEL 10 / Podman with permanent SELinux, MIB support, and Health Checks.

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
echo "[*] Creating persistent directories..."
mkdir -p $INSTALL_DIR/{postgres,snmptraps,mibs,export,enc,extra_cfg}
chmod -R 755 $INSTALL_DIR

# --- 3. SELINUX: Permanent Policy Configuration ---
if command -v semanage &> /dev/null; then
    echo "[*] Applying permanent SELinux context (container_file_t) to $INSTALL_DIR..."
    sudo semanage fcontext -a -t container_file_t "${INSTALL_DIR}(/.*)?" 2>/dev/null
    sudo restorecon -R -v "$INSTALL_DIR" >/dev/null
    echo "[OK] SELinux policy applied."
else
    echo "[!] semanage not found. Falling back to temporary chcon..."
    [ -x "$(command -v chcon)" ] && chcon -R -t container_file_t $INSTALL_DIR
fi

# --- 4. PREP: Zabbix Server SNMP Trap Configuration ---
cat <<EOF > $INSTALL_DIR/extra_cfg/zabbix_server_snmp_traps.conf
StartSNMPTrapper=1
SNMPTrapperFile=/var/lib/zabbix/snmptraps/snmptraps.log
EOF

# --- 5. POD & CONTAINERS ---
echo "[*] Cleaning up old pod if exists..."
podman pod rm -f $POD_NAME 2>/dev/null

echo "[*] Creating Pod: $POD_NAME"
podman pod create --name $POD_NAME --restart always \
    -p 80:8080 -p 443:8443 -p 10051:10051 -p 162:1162/udp

# Container 1: Database
echo "[*] Starting Postgres..."
podman run -d --name postgres-server --pod $POD_NAME \
    -e POSTGRES_USER=zabbix -e POSTGRES_PASSWORD=$DB_PASSWORD -e POSTGRES_DB=zabbix \
    -v $INSTALL_DIR/postgres:/var/lib/postgresql/data:Z,U \
    --health-cmd="pg_isready -U zabbix" --health-interval=10s --health-timeout=5s \
    postgres:16-alpine

echo "[*] Waiting for DB to initialize..." && sleep 15

# Container 2: Traps Receiver
echo "[*] Starting Zabbix SNMP Traps Receiver..."
podman run -d --name zabbix-snmptraps --pod $POD_NAME \
    -e ZBX_SNMP_COMMUNITY=$SNMP_COMMUNITY \
    -v $INSTALL_DIR/snmptraps:/var/lib/zabbix/snmptraps:z,U \
    -v $INSTALL_DIR/mibs:/var/lib/zabbix/mibs:z,U \
    --health-cmd="cat /proc/net/udp | grep 048A" --health-interval=10s \
    zabbix/zabbix-snmptraps:alpine-7.2-latest

# Container 3: Server (The Engine)
echo "[*] Starting Zabbix Server..."
podman run -d --name zabbix-server-pgsql --pod $POD_NAME \
    -e DB_SERVER_HOST=127.0.0.1 \
    -e POSTGRES_USER=zabbix \
    -e POSTGRES_PASSWORD=$DB_PASSWORD \
    -e POSTGRES_DB=zabbix \
    -v $INSTALL_DIR/snmptraps:/var/lib/zabbix/snmptraps:z,U \
    -v $INSTALL_DIR/mibs:/var/lib/zabbix/mibs:z,U \
    -v $INSTALL_DIR/extra_cfg/zabbix_server_snmp_traps.conf:/etc/zabbix/zabbix_server_snmp_traps.conf:Z \
    --health-cmd="zabbix_get -s 127.0.0.1 -k agent.ping || exit 1" \
    --health-interval=10s --health-start-period=30s \
    zabbix/zabbix-server-pgsql:alpine-7.2-latest

# Container 4: Agent (Self-Monitoring)
echo "[*] Starting Zabbix Agent 2..."
podman run -d --name zabbix-agent --pod $POD_NAME \
    -e ZBX_SERVER_HOST=127.0.0.1 \
    -e ZBX_HOSTNAME="Zabbix server" \
    --health-cmd="zabbix_agent2 -t agent.ping || exit 1" \
    --health-interval=10s \
    zabbix/zabbix-agent2:alpine-7.2-latest

# Container 5: Web (The UI)
echo "[*] Starting Zabbix Web Interface..."
podman run -d --name zabbix-web-nginx-pgsql --pod $POD_NAME \
    -e ZBX_SERVER_HOST=127.0.0.1 \
    -e DB_SERVER_HOST=127.0.0.1 \
    -e POSTGRES_USER=zabbix \
    -e POSTGRES_PASSWORD=$DB_PASSWORD \
    -e POSTGRES_DB=zabbix \
    --health-cmd="wget --no-verbose --tries=1 --spider http://127.0.0.1:8080/ || exit 1" \
    --health-interval=10s \
    zabbix/zabbix-web-nginx-pgsql:alpine-7.2-latest

echo "-------------------------------------------------------"
echo "[OK] Deployment Complete."
echo "Access Zabbix at http://$(hostname -I | awk '{print $1}')"
echo "Default Credentials: Admin / zabbix"
echo "Place MIB files in: $INSTALL_DIR/mibs"
echo "-------------------------------------------------------"
