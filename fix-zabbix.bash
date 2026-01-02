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
echo "[*] Force-Cleaning and Restoring Pod: ${POD_NAME}"

# 1. Force remove stuck containers
CONTAINERS=("zabbix-web-nginx-pgsql" "zabbix-agent" "zabbix-server-pgsql" "zabbix-snmptraps" "postgres-server")
for container in "${CONTAINERS[@]}"; do
    echo "[*] Cleaning $container..."
    podman rm -f "$container" 2>/dev/null
done

# 2. Ensure the Pod exists
if ! podman pod exists "${POD_NAME}"; then
    echo "[*] Pod ${POD_NAME} is missing. Recreating..."
    podman pod create --name "${POD_NAME}" --restart always \
        -p 80:8080 -p 443:8443 -p 10051:10051 -p 162:1162/udp
else
    echo "[OK] Pod ${POD_NAME} exists."
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

# 5. Regenerate and enable systemd service for boot persistence
echo "[*] Regenerating systemd service file for pod..."
SERVICE_NAME="pod-${POD_NAME}.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

# Generate systemd service file for the pod (without --new to use existing containers)
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

if podman generate systemd --name "${POD_NAME}" --files 2>/dev/null; then
    # Move the generated service file to systemd directory
    if [ -f "${TEMP_DIR}/${SERVICE_NAME}" ]; then
        sudo mv "${TEMP_DIR}/${SERVICE_NAME}" "${SERVICE_FILE}"
        cd - > /dev/null || exit 1
        rm -rf "$TEMP_DIR"
        echo "[OK] Generated systemd service file from podman"
    else
        cd - > /dev/null || exit 1
        rm -rf "$TEMP_DIR"
        echo "[WARNING] Service file not found after generation, creating manually..."
        # Fallback: create service file manually
        sudo tee "${SERVICE_FILE}" > /dev/null <<EOF
[Unit]
Description=Podman pod ${POD_NAME}
Documentation=man:podman-generate-systemd(1)
Wants=network-online.target
After=network-online.target
RequiresMountsFor=%t/containers

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStart=/usr/bin/podman start ${POD_NAME}
ExecStop=/usr/bin/podman stop -t 10 ${POD_NAME}
ExecStopPost=/usr/bin/podman stop -t 10 ${POD_NAME}
Type=forking
PIDFile=%t/%n-pid
FileDescriptorStoreMax=0

[Install]
WantedBy=default.target
EOF
    fi
else
    echo "[WARNING] Service file generation failed, creating manually..."
    cd - > /dev/null || exit 1
    rm -rf "$TEMP_DIR"
    # Fallback: create service file manually
    sudo tee "${SERVICE_FILE}" > /dev/null <<EOF
[Unit]
Description=Podman pod ${POD_NAME}
Documentation=man:podman-generate-systemd(1)
Wants=network-online.target
After=network-online.target
RequiresMountsFor=%t/containers

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStart=/usr/bin/podman start ${POD_NAME}
ExecStop=/usr/bin/podman stop -t 10 ${POD_NAME}
ExecStopPost=/usr/bin/podman stop -t 10 ${POD_NAME}
Type=forking
PIDFile=%t/%n-pid
FileDescriptorStoreMax=0

[Install]
WantedBy=default.target
EOF
fi

# Reload systemd and enable the service
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" 2>/dev/null || true
sudo systemctl restart "${SERVICE_NAME}" 2>/dev/null || true

echo "------------------------------------------------------------"
podman ps -a --pod --filter "pod=${POD_NAME}"
echo "------------------------------------------------------------"
echo "[OK] Fix complete. Pod service enabled for boot persistence."
