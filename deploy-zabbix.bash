#!/bin/bash
# DESCRIPTION: Deploys Zabbix 7.2 with reboot-persistence and optimized health checks.

if [ -f "vars.env" ]; then
    source vars.env
else
    echo "[ERROR] vars.env not found!"
    exit 1
fi

echo "[*] Starting Zabbix v7.2 Deployment for Pod: ${POD_NAME}"

# --- 1. FIREWALL ---
if systemctl is-active --quiet firewalld; then
    echo "[*] Opening ports 162/udp and 80/tcp..."
    sudo firewall-cmd --add-port=162/udp --permanent >/dev/null 2>&1
    sudo firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1
    sudo firewall-cmd --reload >/dev/null 2>&1
fi

# --- 2. PREP & SELINUX ---
mkdir -p "${INSTALL_DIR}"/{postgres,snmptraps,mibs,export,enc,extra_cfg}
if command -v semanage &> /dev/null; then
    sudo semanage fcontext -a -t container_file_t "${INSTALL_DIR}(/.*)?" 2>/dev/null
    sudo restorecon -R "$INSTALL_DIR" >/dev/null
fi

# --- 3. CONFIG ---
cat <<EOF > "${INSTALL_DIR}/extra_cfg/zabbix_server_snmp_traps.conf"
StartSNMPTrapper=1
SNMPTrapperFile=/var/lib/zabbix/snmptraps/snmptraps.log
EOF

# --- 4. POD & CONTAINERS ---
podman pod rm -f "${POD_NAME}" 2>/dev/null
podman pod create --name "${POD_NAME}" --restart always \
    -p 80:8080 -p 443:8443 -p 10051:10051 -p 162:1162/udp

# Database
podman run -d --name postgres-server --pod "${POD_NAME}" --restart always \
    -e POSTGRES_USER=zabbix -e POSTGRES_PASSWORD="${DB_PASSWORD}" -e POSTGRES_DB=zabbix \
    -v "${INSTALL_DIR}/postgres:/var/lib/postgresql/data:Z,U" \
    --health-cmd="pg_isready -U zabbix" --health-interval=10s --health-start-period=30s \
    postgres:16-alpine

sleep 10

# Traps Receiver
podman run -d --name zabbix-snmptraps --pod "${POD_NAME}" --restart always \
    -e ZBX_SNMP_COMMUNITY="${SNMP_COMMUNITY}" \
    -v "${INSTALL_DIR}/snmptraps:/var/lib/zabbix/snmptraps:z,U" \
    -v "${INSTALL_DIR}/mibs:/var/lib/zabbix/mibs:z,U" \
    --health-cmd="cat /proc/net/udp | grep 048A" --health-interval=10s \
    zabbix/zabbix-snmptraps:alpine-7.2-latest

# Server
podman run -d --name zabbix-server-pgsql --pod "${POD_NAME}" --restart always \
    -e DB_SERVER_HOST=127.0.0.1 -e POSTGRES_USER=zabbix -e POSTGRES_PASSWORD="${DB_PASSWORD}" -e POSTGRES_DB=zabbix \
    -v "${INSTALL_DIR}/snmptraps:/var/lib/zabbix/snmptraps:z,U" \
    -v "${INSTALL_DIR}/mibs:/var/lib/zabbix/mibs:z,U" \
    -v "${INSTALL_DIR}/extra_cfg/zabbix_server_snmp_traps.conf:/etc/zabbix/zabbix_server_snmp_traps.conf:Z" \
    --health-cmd="zabbix_get -s 127.0.0.1 -k agent.ping || exit 1" \
    --health-interval=10s --health-start-period=60s \
    zabbix/zabbix-server-pgsql:alpine-7.2-latest

# Agent (Fix: Unique socket path to prevent Exit 1 crash)
podman run -d --name zabbix-agent --pod "${POD_NAME}" --restart always \
    -e ZBX_SERVER_HOST=127.0.0.1 -e ZBX_HOSTNAME="Zabbix server" \
    -e ZBX_AGENT2_PLUGINS_SOCKET=/tmp/zabbix-agent2-reboot.sock \
    --health-cmd="zabbix_agent2 -t agent.ping || exit 1" \
    --health-interval=10s --health-start-period=30s \
    zabbix/zabbix-agent2:alpine-7.2-latest

# Web Interface
podman run -d --name zabbix-web-nginx-pgsql --pod "${POD_NAME}" --restart always \
    -e ZBX_SERVER_HOST=127.0.0.1 -e DB_SERVER_HOST=127.0.0.1 -e POSTGRES_USER=zabbix \
    -e POSTGRES_PASSWORD="${DB_PASSWORD}" -e POSTGRES_DB=zabbix \
    --health-cmd="wget --no-verbose --tries=1 --spider http://127.0.0.1:8080/ || exit 1" \
    --health-interval=10s --health-start-period=30s \
    zabbix/zabbix-web-nginx-pgsql:alpine-7.2-latest

# Enable the Host's Podman Restart service
sudo systemctl enable --now podman-restart
echo "[OK] Deployment Complete."
