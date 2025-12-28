# Zabbix 7.2 Containerized SNMP Trap Deploy




## Overview

This repository contains a code to deploy a containerized Zabbix 7.2 monitoring stack deployed via **Podman**. 

This code has been tested only on RHEL 10.1


The architecture is specifically designed to handle **SNMP Traps** through a shared-volume "trapper" pattern. This ensures that trap data is received by a lightweight listener and processed by the core Zabbix engine without the need for complex internal networking.


### The Stack:
* **Database:** PostgreSQL 16 (Alpine)
* **Trap Receiver:** Zabbix-SNMP-Traps 7.2
* **Core Engine:** Zabbix-Server-PgSQL 7.2
* **Web Interface:** Zabbix-Web-Nginx-PgSQL 7.2



### Prerequisites
* **Podman** installed and running.
* **net-snmp-utils** installed on the host (for testing).






### Configuration (`vars.env`)



To protect sensitive credentials and local network settings, all configuration is stored in `vars.env`. This file is ignored by Git.

CRITICAL: Ensure your .gitignore includes vars.env to prevent committing secrets to your repository.






### Setup Instructions

1.  Create the file: `vim vars.env` - a template file has been provided

2.  Populate it with your local environment details:



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




## Deployment Workflow





### Step 1: Cleanup

Cleanup & Reset Options
This step can be skipped for the initial deployment, but should be run on and subsequent deployments



The cleanup script supports two modes:



Standard Cleanup: Removes containers/pods but preserves your Zabbix configuration and database.



```

./cleanup-zabbix.bash

```




Factory Reset: Removes containers and deletes all data (database, hosts, and logs). Use this to start from a completely blank Zabbix install.




```

./cleanup-zabbix.bash --factory-reset

```





### Step 2: Deploy

This script handles directory creation, security labeling (SELinux), and container orchestration.




```

./deploy-zabbix.bash

```


### Step 3: Health Check
Verify that all containers are running and verify that the internal "SNMP Trapper" process is active within the server container.



```

./check-zabbix-health.bash

```



## Zabbix Web UI Configuration


1.  **Login:** Access `http://<ZABBIX_SERVER_IP>` (Default: `Admin`/`zabbix`).

2.  **Create Host:** Go to **Data Collection > Hosts**.

3.  **SNMP Interface:** Add a Host with an SNMP interface using the `TEST_SENDER_IP` from your `vars.env`.

4.  **Macros:** Add the macro `{$SNMP_COMMUNITY}` and set it to your community string.

5.  **Config Cache:** Force Zabbix to recognize changes immediately:





```

# Update Now" button for the Zabbix Server's internal brain - forces Zabbix to recognize changes immediately instead of waiting 60 seconds
podman exec zabbix-server-pgsql zabbix_server -R config_cache_reload

```



## Troubleshooting & Verification


### The Troubleshooting Chain

If traps do not appear in **Monitoring > Latest Data**, follow this flow:

| **Level** | **Check** | **Command** |
| --- | --- | --- |
| **Network** | Does the packet reach the host? | `sudo tcpdump -ni any udp port 162` |
| **Receiver** | Is the container receiving data? | `podman logs zabbix-snmptraps` |
| **Storage** | Is the trap written to the log? | `cat /var/lib/zabbix/snmptraps/snmptraps.log` |
| **Server** | Is there an IP mismatch? | `podman logs zabbix-server-pgsql | grep unmatched` |

Note: If "unmatched" appears, the Source IP of the trap does not match the IP configured in the Web UI.



### Manual Injection Test

Use the included test script to verify the pipeline from the local host:




```

./test-network-trap.bash "MY_VALIDATION_MESSAGE"

```

#### Simulating a Cisco Link Down Event:


```

./test-network-trap.bash "Interface GigabitEthernet0/1, changed state to down"

```

#### Simulating a Cisco Link Up Event:


```

./test-network-trap.bash "Interface GigabitEthernet0/1, changed state to up"
```

#### Simulating a Configuration Change:


```

./test-network-trap.bash "Configured from console by vty0 (10.1.10.50)"
```



#### How to verify the results in Zabbix:

- Check the Shared Log: Run tail -f /var/lib/zabbix/snmptraps/snmptraps.log. You will see the trap enter the file instantly.

- Check the Web UI: Go to Monitoring > Latest Data, filter by your host, and look at the SNMP traps (fallback) item.





## Security and Permissions


This deployment uses the following security measures:

-   **UID Mapping:** Host directories are owned by UID `1001` (Zabbix container user).

-   **SELinux:** Volumes are mounted with the `:z` and `:U` flags to automatically manage security contexts.

-   **Global Write:** The `snmptraps/` directory uses `777` permissions to ensure the receiver can write while the server reads.




```
# Manual permission reset if needed:
chown -R 1001:1001 /var/lib/zabbix/snmptraps
chmod -R 777 /var/lib/zabbix/snmptraps
chcon -R -t container_file_t /var/lib/zabbix/snmptraps
```



