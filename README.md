# Zabbix 7.2 Containerized SNMP Trap Laboratory

## 1. Overview
This repository contains a fully containerized Zabbix 7.2 stack deployed via **Podman**. It uses a shared-volume architecture to handle SNMP Traps. The setup consists of four main containers running in a single Pod:
* **Database:** Postgres 16
* **SNMP Trap Receiver:** zabbix-snmptraps
* **Zabbix Server:** zabbix-server-pgsql
* **Zabbix Web UI:** zabbix-web-nginx-pgsql

This environment was validated using Cisco IOS hardware, though it is adaptable for any SNMP-capable device.

---

## 2. Configuration (`vars.env`)
This project uses an environment file to separate sensitive credentials from the deployment logic. **The `vars.env` file is ignored by Git to prevent security leaks.**

### Setup Instructions
1. Create a file named `vars.env`.
2. Copy the following template into the file and update the values:

```bash
# Database Password
DB_PASSWORD="your_secure_password"

# SNMP Community String (Must match your network devices)
SNMP_COMMUNITY="your_community_string"

# The IP of the machine sending test traps (e.g., your laptop)
TEST_SENDER_IP="10.x.x.x"

# The IP of this Zabbix Server
ZABBIX_SERVER_IP="10.x.x.x"

# Host Paths
INSTALL_DIR="/var/lib/zabbix"
POD_NAME="zabbix-pod"
