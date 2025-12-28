#!/bin/bash
# DESCRIPTION: Force-cleans "stuck" containers, ensures the Pod exists, and redeploys.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/vars.env" ]; then
    source "$SCRIPT_DIR/vars.env"
else
    echo "[ERROR] vars.env not found. Please ensure it exists in $SCRIPT_DIR"
    exit 1
fi

POD_NAME=${POD_NAME:-zabbix-pod}
echo "[*] Force-Cleaning and Restoring Pod: $POD_NAME"

# 1. Force remove stuck containers
CONTAINERS=("zabbix-web-nginx-pgsql" "zabbix-agent" "zabbix-server-pgsql" "zabbix-snmptraps" "postgres-server")
for container in "${CONTAINERS[@]}"; do
    echo "[*] Cleaning $container..."
    podman rm -f "$container" 2>/dev/null
done

# 2. Ensure the Pod exists
if ! podman pod exists "$POD_NAME"; then
    echo "[*] Pod $POD_NAME is missing. Recreating..."
    podman pod create --name "$POD_NAME" --restart always \
        -p 80:8080 -p 443:8443 -p 10051:10051 -p 162:1162/udp
else
    echo "[OK] Pod $POD_NAME exists."
fi

# 3. Clean up stale sockets on the host
echo "[*] Cleaning stale sockets..."
find "$INSTALL_DIR" -name "*.sock" -delete 2>/dev/null

# 4. Redeploy containers into the pod
echo "[*] Redeploying containers..."

# Postgres
podman run -d --name postgres-server --pod "$POD_NAME" --restart always \
    -e POSTGRES_USER=zabbix -e POSTGRES_PASSWORD="$DB_PASSWORD" -e POSTGRES_DB=zabbix \
    -v "$INSTALL_DIR/postgres:/var/lib/postgresql/data:Z,U" \
    postgres:16-alpine

# SNMP Traps
podman run -d --name zabbix-snmptraps --pod "$POD_NAME" --restart always \
    -e ZBX_SNMP_COMMUNITY="$SNMP_COMMUNITY" \
    -v "$INSTALL_DIR/snmptraps:/var/lib/zabbix/snmptraps:z,U" \
    -v "$INSTALL_DIR/mibs:/var/lib/zabbix/mibs:z,U" \
    zabbix/zabbix-snmptraps:alpine-7.2-latest

# Zabbix Server
podman run -d --name zabbix-server-pgsql --pod "$POD_NAME" --restart always \
    -e DB_SERVER_HOST=127.0.0.1 -e POSTGRES_USER=zabbix -e POSTGRES_PASSWORD="$DB_PASSWORD" -e POSTGRES_DB=zabbix \
    -v "$INSTALL_DIR/snmptraps:/var/lib/zabbix/snmptraps:z,U" \
    -v "$INSTALL_DIR/mibs:/var/lib/zabbix/mibs:z,U" \
    -v "$INSTALL_DIR/extra_cfg/zabbix_server_snmp_traps.conf:/etc/zabbix/zabbix_server_snmp_traps.conf:Z" \
    zabbix/zabbix-server-pgsql:alpine-7.2-latest

# Zabbix Agent
podman run -d --name zabbix-agent --pod "$POD_NAME" --restart always \
    -e ZBX_SERVER_HOST=127.0.0.1 -e ZBX_HOSTNAME="Zabbix server" \
    -e ZBX_AGENT2_PLUGINS_SOCKET=/tmp/zabbix-agent2-reboot.sock \
    zabbix/zabbix-agent2:alpine-7.2-latest

# Web
podman run -d --name zabbix-web-nginx-pgsql --pod "$POD_NAME" --restart always \
    -e ZBX_SERVER_HOST=127.0.0.1 -e DB_SERVER_HOST=127.0.0.1 -e POSTGRES_USER=zabbix \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" -e POSTGRES_DB=zabbix \
    zabbix/zabbix-web-nginx-pgsql:alpine-7.2-latest

echo "------------------------------------------------------------"
podman ps -a --pod --filter "pod=$POD_NAME"
echo "------------------------------------------------------------"
