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

# IMPROVED SNMP Trapper Check
# This looks for the process itself, ignoring the dynamic status text in brackets
TRAP_PROC=$(podman exec zabbix-server-pgsql ps aux | grep "snmp trapper" | grep -v "grep" || true)

if [[ $TRAP_PROC == *"snmp trapper"* ]]; then
    printf "%-30s | [OK]\n" "Internal SNMP Trapper"
else
    printf "%-30s | [FAIL]\n" "Internal SNMP Trapper"
fi
