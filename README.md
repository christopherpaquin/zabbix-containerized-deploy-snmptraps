1\. Zabbix 7.2 Containerized SNMP Trap Laboratory

Overview
This repository contains a professional-grade, containerized Zabbix 7.2 monitoring stack deployed via **Podman**.

The architecture is specifically designed to handle **SNMP Traps** through a shared-volume "trapper" pattern. This ensures that trap data is received by a lightweight listener and processed by the core Zabbix engine without the need for complex internal networking.

### The Stack:
* **Database:** PostgreSQL 16 (Alpine)
* **Trap Receiver:** Zabbix-SNMP-Traps 7.2
* **Core Engine:** Zabbix-Server-PgSQL 7.2
* **Web Interface:** Zabbix-Web-Nginx-PgSQL 7.2



2\.  Prerequisites
* **Podman** installed and running.
* **net-snmp-utils** installed on the host (for testing).
* **Firewall Permissions:** Port `162/UDP` must be open to allow external traps.

```bash
sudo firewall-cmd --add-port=162/udp --permanent
sudo firewall-cmd --reload

```

* * * * *

3\. Configuration (`vars.env`)
------------------------------

To protect sensitive credentials and local network settings, all configuration is stored in `vars.env`. This file is ignored by Git.

### Setup Instructions

1.  Create the file: `vim vars.env`

2.  Populate it with your local environment details:

Bash

```
# --- DATABASE CONFIG ---
DB_PASSWORD="your_secure_password"

# --- SNMP CONFIG ---
# This community string must match your network devices
SNMP_COMMUNITY="your_secret_string"

# --- NETWORK CONFIG ---
# The IP of the machine you use for remote testing
TEST_SENDER_IP="10.x.x.x"

# The physical IP of this Zabbix Server
ZABBIX_SERVER_IP="10.x.x.x"

# --- PATHS ---
INSTALL_DIR="/var/lib/zabbix"
POD_NAME="zabbix-pod"

```

* * * * *

4\. Deployment Workflow
-----------------------

### Step 1: Cleanup

Ensure no stale containers or volume locks exist from previous runs.

Bash

```
chmod +x *.bash
./cleanup-zabbix.bash

```

### Step 2: Deploy

This script handles directory creation, security labeling (SELinux), and container orchestration.

Bash

```
./deploy-zabbix.bash

```

### Step 3: Health Check

Verify that the internal "SNMP Trapper" process is active within the server container.

Bash

```
./check-zabbix-health.bash

```

* * * * *

5\. Zabbix Web UI Configuration
-------------------------------

1.  **Login:** Access `http://<ZABBIX_SERVER_IP>` (Default: `Admin`/`zabbix`).

2.  **Create Host:** Go to **Data Collection > Hosts**.

3.  **SNMP Interface:** Add an interface using the `TEST_SENDER_IP` from your `vars.env`.

4.  **Macros:** Add the macro `{$SNMP_COMMUNITY}` and set it to your community string.

5.  **Config Cache:** Force Zabbix to recognize changes immediately:

Bash

```
podman exec zabbix-server-pgsql zabbix_server -R config_cache_reload

```

* * * * *

6\. Troubleshooting & Verification
----------------------------------

### The Troubleshooting Chain

If traps do not appear in **Monitoring > Latest Data**, follow this flow:

| **Level** | **Check** | **Command** |
| --- | --- | --- |
| **Network** | Does the packet reach the host? | `sudo tcpdump -ni any udp port 162` |
| **Receiver** | Is the container receiving data? | `podman logs zabbix-snmptraps` |
| **Storage** | Is the trap written to the log? | `cat /var/lib/zabbix/snmptraps/snmptraps.log` |
| **Server** | Is there an IP mismatch? | `podman logs zabbix-server-pgsql | grep unmatched` |

### Manual Injection Test

Use the included test script to verify the pipeline from the local host:

Bash

```
./test-network-trap.bash "MY_VALIDATION_MESSAGE"

```

* * * * *

7\. Security and Permissions
----------------------------

This deployment uses the following security measures:

-   **UID Mapping:** Host directories are owned by UID `1001` (Zabbix container user).

-   **SELinux:** Volumes are mounted with the `:z` and `:U` flags to automatically manage security contexts.

-   **Global Write:** The `snmptraps/` directory uses `777` permissions to ensure the receiver can write while the server reads.

Bash

```
# Manual permission reset if needed:
chown -R 1001:1001 /var/lib/zabbix/snmptraps
chmod -R 777 /var/lib/zabbix/snmptraps
chcon -R -t container_file_t /var/lib/zabbix/snmptraps
```
