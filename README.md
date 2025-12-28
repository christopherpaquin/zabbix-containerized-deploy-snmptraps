ZABBIX 7.2 CONTAINERIZED SNMP TRAP LABORATORY
1. OVERVIEW
This repository contains a fully containerized Zabbix 7.2 stack deployed via Podman. It uses a shared-volume architecture to handle SNMP Traps. The setup consists of four main containers running in a single Pod:

Database (Postgres 16)

SNMP Trap Receiver (zabbix-snmptraps)

Zabbix Server (zabbix-server-pgsql)

Zabbix Web UI (zabbix-web-nginx-pgsql)

This environment was specifically tested and validated using Cisco IOS switches, though it can be adapted for any SNMP-capable network hardware.

2. FILE STRUCTURE AND USAGE
All scripts should be kept in the same directory. Ensure they are executable: chmod +x *.bash

SCRIPT EXECUTION ORDER:
cleanup-zabbix.bash: Run this first to ensure a clean slate. It removes old containers, the pod, and clears stuck volume locks.

deploy-zabbix.bash: The main deployment script. It creates host directories, sets required permissions (chmod 777 + SELinux), and launches the containers.

check-zabbix-health.bash: Run this ~30 seconds after deployment to verify that all processes (specifically the snmp-trapper engine) are running.

TEST UTILITIES:
test-network-trap.bash: Sends a simulated SNMP trap from the local host.

send_test.py: A Python script for "precision" testing if standard system utilities fail to route packets correctly.

3. WEB INTERFACE CONFIGURATION STEPS
After the scripts complete, log in to the Web UI (Default: Admin/zabbix) and perform these steps:

CREATE HOST:

Go to Data Collection -> Hosts -> Create Host.

Name: Enter your device hostname.

Templates: Select the template appropriate for your hardware (e.g., "Cisco IOS by SNMP").

Groups: Select or create a relevant group.

CONFIGURE INTERFACE (CRITICAL):

Click Add -> SNMP.

IP Address: Enter the IP of the device sending the traps.

NOTE: Zabbix matches traps based on the SOURCE IP of the packet. If testing from a management workstation, you must temporarily set this interface to that workstation's IP.

CONFIGURE COMMUNITY STRING:

Go to the Macros tab for the host.

Click "Inherited and host macros."

Find {$SNMP_COMMUNITY} and change the value to your specific community string.

RELOAD CACHE:

Force Zabbix to recognize configuration changes immediately by running: podman exec zabbix-server-pgsql zabbix_server -R config_cache_reload

4. TROUBLESHOOTING CHECKLIST
If traps do not appear in "Latest Data," check the following:

STEP A: Check the Physical Interface

Run: sudo tcpdump -ni any udp port 162

If you see no output when sending a trap, the host firewall is likely blocking the port.

STEP B: Check the Container Receiver

Run: podman logs zabbix-snmptraps

Look for: "Permission denied." This indicates the container cannot write to the shared log file.

STEP C: Check the Shared Log File

Run: cat /var/lib/zabbix/snmptraps/snmptraps.log

This file acts as the bridge between the receiver and the server.

STEP D: Check the Zabbix Engine

Run: podman logs zabbix-server-pgsql | grep "unmatched"

If you see "unmatched trap received from [IP]", the Source IP in the trap packet does not match any IP configured in your Zabbix Host Interfaces.

5. RECOVERY COMMANDS
Manual Permission Reset: mkdir -p /var/lib/zabbix/snmptraps chown -R 1001:1001 /var/lib/zabbix/snmptraps chmod -R 777 /var/lib/zabbix/snmptraps chcon -R -t container_file_t /var/lib/zabbix/snmptraps
