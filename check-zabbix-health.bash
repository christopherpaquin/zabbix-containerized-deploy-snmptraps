#!/bin/bash
# DESCRIPTION: Validates Zabbix container status and SNMP Trapper process.

printf "\n%-30s | %-10s\n" "COMPONENT" "STATUS"
printf -- "--------------------------------------------\n"

# Check Containers
for c in postgres-server zabbix-snmptraps zabbix-server-pgsql zabbix-web-nginx-pgsql; do
    if [ "$(podman inspect -f '{{.State.Running}}' $c 2>/dev/null)" == "true" ]; then
        printf "%-30s | [OK]\n" "$c"
    else
        printf "%-30s | [FAIL]\n" "$c"
    fi
done

# Check SNMP Trapper Process
TRAP_PROC=$(podman exec zabbix-server-pgsql ps aux | grep -v grep | grep "snmp trapper" || true)
if [ ! -z "$TRAP_PROC" ]; then
    printf "%-30s | [OK]\n" "Internal SNMP Trapper"
else
    printf "%-30s | [FAIL]\n" "Internal SNMP Trapper"
fi
