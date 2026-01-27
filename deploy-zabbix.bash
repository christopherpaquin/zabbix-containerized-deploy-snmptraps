#!/bin/bash
# DESCRIPTION: Deploys Zabbix with reboot-persistence and optimized health checks.

if [ -f "vars.env" ]; then
    source vars.env
else
    echo "[ERROR] vars.env not found!"
    exit 1
fi

# Set default version if not specified
ZABBIX_VERSION=${ZABBIX_VERSION}

echo "[*] Starting Zabbix v${ZABBIX_VERSION} Deployment for Pod: ${POD_NAME}"

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
    zabbix/zabbix-snmptraps:alpine-${ZABBIX_VERSION}

# Server
podman run -d --name zabbix-server-pgsql --pod "${POD_NAME}" --restart always \
    -e DB_SERVER_HOST=127.0.0.1 -e POSTGRES_USER=zabbix -e POSTGRES_PASSWORD="${DB_PASSWORD}" -e POSTGRES_DB=zabbix \
    -v "${INSTALL_DIR}/snmptraps:/var/lib/zabbix/snmptraps:z,U" \
    -v "${INSTALL_DIR}/mibs:/var/lib/zabbix/mibs:z,U" \
    -v "${INSTALL_DIR}/extra_cfg/zabbix_server_snmp_traps.conf:/etc/zabbix/zabbix_server_snmp_traps.conf:Z" \
    --health-cmd="zabbix_get -s 127.0.0.1 -k agent.ping || exit 1" \
    --health-interval=10s --health-start-period=60s \
    zabbix/zabbix-server-pgsql:alpine-${ZABBIX_VERSION}

# Agent (Fix: Unique socket path to prevent Exit 1 crash)
podman run -d --name zabbix-agent --pod "${POD_NAME}" --restart always \
    -e ZBX_SERVER_HOST=127.0.0.1 -e ZBX_HOSTNAME="Zabbix server" \
    -e ZBX_AGENT2_PLUGINS_SOCKET=/tmp/zabbix-agent2-reboot.sock \
    --health-cmd="zabbix_agent2 -t agent.ping || exit 1" \
    --health-interval=10s --health-start-period=30s \
    zabbix/zabbix-agent2:alpine-${ZABBIX_VERSION}

# Web Interface
podman run -d --name zabbix-web-nginx-pgsql --pod "${POD_NAME}" --restart always \
    -e ZBX_SERVER_HOST=127.0.0.1 -e DB_SERVER_HOST=127.0.0.1 -e POSTGRES_USER=zabbix \
    -e POSTGRES_PASSWORD="${DB_PASSWORD}" -e POSTGRES_DB=zabbix \
    --health-cmd="wget --no-verbose --tries=1 --spider http://127.0.0.1:8080/ || exit 1" \
    --health-interval=10s --health-start-period=30s \
    zabbix/zabbix-web-nginx-pgsql:alpine-${ZABBIX_VERSION}

# --- 5. SYSTEMD SERVICE FOR BOOT PERSISTENCE ---
echo "[*] Generating systemd service file for pod..."
SERVICE_NAME="pod-${POD_NAME}.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

# Generate systemd service file for the pod (without --new to use existing containers)
# The --files flag creates the file in current directory
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
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl enable container-postgres-server.service container-zabbix-snmptraps.service \
    container-zabbix-server-pgsql.service container-zabbix-agent.service \
    container-zabbix-web-nginx-pgsql.service 2>/dev/null || true
# Start the service to ensure it's running (it should already be running, but this ensures systemd knows about it)
sudo systemctl start "${SERVICE_NAME}" 2>/dev/null || true

# Also enable podman-restart service as a fallback
sudo systemctl enable --now podman-restart 2>/dev/null || true

echo "[OK] Deployment Complete. Pod will start automatically on boot."
