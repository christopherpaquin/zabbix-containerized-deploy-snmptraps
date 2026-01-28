#!/bin/bash
# DESCRIPTION: Force-cleans "stuck" containers, ensures the Pod exists, and redeploys.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/vars.env" ]; then
    source "$SCRIPT_DIR/vars.env"
else
    echo "[ERROR] vars.env not found. Please ensure it exists in $SCRIPT_DIR"
    exit 1
fi

echo "[*] Force-Cleaning and Restoring Pod: ${POD_NAME} (Zabbix v${ZABBIX_VERSION})"

# 1. Force remove stuck containers
CONTAINERS=("${CONTAINER_WEB}" "${CONTAINER_AGENT}" "${CONTAINER_SERVER}" "${CONTAINER_SNMPTRAPS}" "${CONTAINER_POSTGRES}")
for container in "${CONTAINERS[@]}"; do
    echo "[*] Cleaning $container..."
    podman rm -f "$container" 2>/dev/null
done

# 2. Ensure the Pod exists
if ! podman pod exists "${POD_NAME}"; then
    echo "[*] Pod ${POD_NAME} is missing. Recreating..."
    podman pod create --name "${POD_NAME}" --restart always \
        -p ${PORT_WEB_HTTP}:${PORT_WEB_INTERNAL} -p ${PORT_WEB_HTTPS}:${PORT_HTTPS_INTERNAL} -p ${PORT_ZABBIX_SERVER}:${PORT_ZABBIX_SERVER} -p ${PORT_SNMP_TRAP}:${PORT_TRAP_INTERNAL}/udp
else
    echo "[OK] Pod ${POD_NAME} exists."
fi

# 3. Clean up stale sockets on the host
echo "[*] Cleaning stale sockets..."
find "$INSTALL_DIR" -name "*.sock" -delete 2>/dev/null

# 4. Redeploy containers into the pod
echo "[*] Redeploying containers..."

# Postgres
podman run -d --name ${CONTAINER_POSTGRES} --pod "$POD_NAME" --restart always \
    -e POSTGRES_USER="$POSTGRES_USER" -e POSTGRES_PASSWORD="$DB_PASSWORD" -e POSTGRES_DB="$POSTGRES_DB" \
    -v "$INSTALL_DIR/postgres:/var/lib/postgresql/data:Z,U" \
    postgres:$POSTGRES_VERSION

# SNMP Traps
podman run -d --name ${CONTAINER_SNMPTRAPS} --pod "$POD_NAME" --restart always \
    -e ZBX_SNMP_COMMUNITY="$SNMP_COMMUNITY" \
    -v "$INSTALL_DIR/snmptraps:/var/lib/zabbix/snmptraps:z,U" \
    -v "$INSTALL_DIR/mibs:/var/lib/zabbix/mibs:z,U" \
    zabbix/zabbix-snmptraps:alpine-${ZABBIX_VERSION}

# Zabbix Server
podman run -d --name ${CONTAINER_SERVER} --pod "$POD_NAME" --restart always \
    -e DB_SERVER_HOST=127.0.0.1 -e POSTGRES_USER="$POSTGRES_USER" -e POSTGRES_PASSWORD="$DB_PASSWORD" -e POSTGRES_DB="$POSTGRES_DB" \
    -v "$INSTALL_DIR/snmptraps:/var/lib/zabbix/snmptraps:z,U" \
    -v "$INSTALL_DIR/mibs:/var/lib/zabbix/mibs:z,U" \
    -v "$INSTALL_DIR/extra_cfg/zabbix_server_snmp_traps.conf:/etc/zabbix/zabbix_server_snmp_traps.conf:Z" \
    zabbix/zabbix-server-pgsql:alpine-${ZABBIX_VERSION}

# Zabbix Agent
podman run -d --name ${CONTAINER_AGENT} --pod "$POD_NAME" --restart always \
    -e ZBX_SERVER_HOST=127.0.0.1 -e ZBX_HOSTNAME="$ZBX_AGENT_HOSTNAME" \
    -e ZBX_AGENT2_PLUGINS_SOCKET=/tmp/zabbix-agent2-reboot.sock \
    zabbix/zabbix-agent2:alpine-${ZABBIX_VERSION}

# Web
podman run -d --name ${CONTAINER_WEB} --pod "$POD_NAME" --restart always \
    -e ZBX_SERVER_HOST=127.0.0.1 -e DB_SERVER_HOST=127.0.0.1 -e POSTGRES_USER="$POSTGRES_USER" \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" -e POSTGRES_DB="$POSTGRES_DB" \
    zabbix/zabbix-web-nginx-pgsql:alpine-${ZABBIX_VERSION}

# 5. Regenerate and enable systemd service for boot persistence
echo "[*] Regenerating systemd service file for pod..."
SERVICE_NAME="pod-${POD_NAME}.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

# Generate systemd service file for the pod (without --new to use existing containers)
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

if podman generate systemd --name "${POD_NAME}" --files 2>/dev/null; then
    # Move ALL generated service files to systemd directory
    if [ -f "${TEMP_DIR}/${SERVICE_NAME}" ]; then
        sudo mv "${TEMP_DIR}"/*.service /etc/systemd/system/
        # Fix SELinux contexts
        sudo restorecon -R /etc/systemd/system/*.service 2>/dev/null || true
        cd - > /dev/null || exit 1
        rm -rf "$TEMP_DIR"
        echo "[OK] Generated systemd service files from podman"
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
        # Fix SELinux context for manually created file
        sudo restorecon "${SERVICE_FILE}" 2>/dev/null || true
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
    # Fix SELinux context for manually created file
    sudo restorecon "${SERVICE_FILE}" 2>/dev/null || true
fi

# Reload systemd and enable all services
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" 2>/dev/null || true
sudo systemctl enable container-${CONTAINER_POSTGRES}.service container-${CONTAINER_SNMPTRAPS}.service \
    container-${CONTAINER_SERVER}.service container-${CONTAINER_AGENT}.service \
    container-${CONTAINER_WEB}.service 2>/dev/null || true
sudo systemctl restart "${SERVICE_NAME}" 2>/dev/null || true

echo "------------------------------------------------------------"
podman ps -a --pod --filter "pod=${POD_NAME}"
echo "------------------------------------------------------------"
echo "[OK] Fix complete. Pod service enabled for boot persistence."
