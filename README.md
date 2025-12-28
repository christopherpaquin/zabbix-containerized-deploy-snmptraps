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

Use the included test script to verify the pipeline from the local host. You will want to move this script to the host that you are using to send the alert. The IP of that host should match the *TEST_SENDER_IP="10.x.x.x"*



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

#### Sending a test alert manually from a remote host

If you do not want to copy the *./test-network-trap.bash* script to the remote test host then you can run tests manually using the format below


```

snmptrap -v 2c -c <YOUR_SNMP_COMMUNITY> <IP_OF_ZABBIX_HOST>:162 "" 1.3.6.1.4.1.9.9.41.1.2.3.1.2.1 1.3.6.1.4.1.9.9.41.1.2.3.1.2.1 s "Interface GigabitEthernet0/1, changed state to down"

```

#### Example

```

snmptrap -v 2c -c public 10.1.10.50:162 "" 1.3.6.1.4.1.9.9.41.1.2.3.1.2.1 1.3.6.1.4.1.9.9.41.1.2.3.1.2.1 s "Interface GigabitEthernet0/1, changed state to down"

```

##### Remote Test Rationale

In the log output below you can see that when run from on the zabbix host, the snmptrap is associated with the IP address 10.88.0.1, which is a *podman* ip. 

Additionally, testing from an external host validates firewall configs

You can set the IP on the Zabbix monitored device's interface to the podman IP if you want to test sending alerts locally. 

Bottom line, the IP of the host sending the alert, must match the IP of the monitored interface in Zabbix otherwise there is not a match between alert source and monitored device

```

#  tail -f /var/lib/zabbix/snmptraps/snmptraps.log
2025-12-28T17:52:33+0000 ZBXTRAP 10.88.0.1
UDP: [10.88.0.1]:43161->[10.88.0.19]:1162
DISMAN-EVENT-MIB::sysUpTimeInstance = 14085669
SNMPv2-MIB::snmpTrapOID.0 = SNMPv2-SMI::enterprises.9.9.41.1.2.3.1.2.1
SNMPv2-SMI::enterprises.9.9.41.1.2.3.1.2.1 = "Interface GigabitEthernet0/1, changed state to down"

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


Zabbix MIB Management Documentation
===================================

This document describes the architecture, configuration, and usage of the MIB Management system developed for the Zabbix Podman deployment. This system ensures that SNMP traps from various vendors (Cisco, Juniper, Dell, APC) are translated from numeric OIDs into human-readable text.

* * * * *

1\. The Configuration File: `mibs.conf`
---------------------------------------

The `mibs.conf` file is the central source of truth for all external MIB dependencies. It follows a **pipe-delimited (`|`)** format.

### File Structure

Plaintext

```
Vendor_Name | Download_URL

```

-   **Vendor_Name:** A unique label for the hardware vendor. This string is case-sensitive and is used by the script to trigger specific extraction logic.

-   **Download_URL:** The link to either a direct file (e.g., `IF-MIB.txt`) or a repository ZIP archive (e.g., `master.zip`).

### How to Add New Vendors

1.  Open `mibs.conf` in a text editor.

2.  Add a new line following the pipe-delimited format.

3.  **Note:** If you are adding a vendor that is part of the LibreNMS repository, use the master ZIP URL and ensure the `Vendor_Name` matches one of the handled cases in the script.

* * * * *

2\. The Logic Engine: `manage-mibs.bash`
----------------------------------------

The `manage-mibs.bash` script is a **Strategic Extraction Engine**. Instead of simply downloading a file, it performs "Selective Extraction" to keep the monitoring environment lean.

### How ZIP Parsing Works

Many vendors (like Cisco and Juniper) provide hundreds of MIBs in massive repositories. The script handles these via a `case` statement based on the `Vendor_Name` provided in `mibs.conf`:

| **Vendor Name** | **ZIP Extraction Path** | **Purpose** |
| --- | --- | --- |
| `Standard_Core` | `*/mibs/*` | Base networking OIDs (IF-MIB, etc.) |
| `Cisco_Mibs` | `*-master/mibs/cisco/*` | Cisco switches and routers |
| `Juniper_Mibs` | `*-master/mibs/juniper/*` | Juniper Junos devices |
| `Dell_iDRAC` | `*-master/mibs/dell/*` | Dell PowerEdge Servers |
| `APC_PDU` | `*-master/mibs/apc/*` | APC UPS and PDU units |

### Automation Steps

When the script is executed, it performs the following sequence:

1.  **Prerequisite Install:** Automatically checks for and installs `curl` and `unzip`.

2.  **Validation:** Uses `curl -L --head` to verify the URL exists before attempting download.

3.  **Normalization:** Converts all `.txt` and `.my` files to `.mib` (required by Net-SNMP).

4.  **Security:** Applies `chmod 755` and SELinux `container_file_t` contexts so the Zabbix container can read the host volumes.

5.  **Service Reload:** Restarts the `zabbix-snmptraps` and `zabbix-server-pgsql` containers to re-index the library.

* * * * *

3\. Usage & Verification
------------------------

### Running the Manager

To synchronize your MIB library with the configuration file:

Bash

```
chmod +x manage-mibs.bash
./manage-mibs.bash

```

### Verifying MIB Translation

To confirm that a specific vendor's MIB has been correctly indexed and is readable by the Zabbix engine, run the following command from the host:

**Example for Cisco:**

Bash

```
podman exec zabbix-snmptraps snmptranslate -On CISCO-CONFIG-MAN-MIB::ciscoConfigManEvent

```

*Expected Result: `.1.3.6.1.4.1.9.9.43.2.0.1`*

* * * * *

4\. Directory Structure
-----------------------

The system maintains a flat directory structure on the host to ensure the fastest possible indexing by the Zabbix Trapper process:

-   **Host Path:** `/var/lib/zabbix/mibs/`

-   **Container Path:** `/usr/share/snmp/mibs/` (Mapped via Volume)

> **Warning:** Do not manually place files in the MIB directory without running the script afterward, as the containers must be restarted to recognize new files.
