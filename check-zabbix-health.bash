#!/bin/bash
# DESCRIPTION: Comprehensive health check for Zabbix Podman deployment.
# This script queries the internal health status of each container.

# Load variables to get the POD_NAME
if [ -f "vars.env" ]; then
    source vars.env
else
    POD_NAME="zabbix-pod" # Fallback default
fi

# Define the containers to check
CONTAINERS=(
    "postgres-server"
    "zabbix-snmptraps"
    "zabbix-server-pgsql"
    "zabbix-agent"
    "zabbix-web-nginx-pgsql"
)

echo "Checking Zabbix Stack Health for Pod: $POD_NAME"
echo "------------------------------------------------------------"
printf "%-25s | %-15s | %-10s\n" "COMPONENT" "STATUS" "HEALTH"
echo "------------------------------------------------------------"

for CONTAINER in "${CONTAINERS[@]}"; do
    # 1. Check if container exists and is running
    STATE=$(podman inspect --format '{{.State.Status}}' "$CONTAINER" 2>/dev/null)
    
    if [ "$?" -ne 0 ]; then
        HEALTH_RESULT="[MISSING]"
        HEALTH_COLOR="\e[31m" # Red
    else
        # 2. Check the internal Health Status
        HEALTH=$(podman inspect --format '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null)
        
        # Format the output based on health
        case "$HEALTH" in
            "healthy")
                HEALTH_RESULT="[OK]"
                HEALTH_COLOR="\e[32m" # Green
                ;;
            "starting")
                HEALTH_RESULT="[STARTING]"
                HEALTH_COLOR="\e[33m" # Yellow
                ;;
            "unhealthy")
                HEALTH_RESULT="[FAIL]"
                HEALTH_COLOR="\e[31m" # Red
                ;;
            *)
                # If no health check is defined or it's null
                if [ "$STATE" == "running" ]; then
                    HEALTH_RESULT="[RUNNING]"
                    HEALTH_COLOR="\e[36m" # Cyan
                else
                    HEALTH_RESULT="[DOWN]"
                    HEALTH_COLOR="\e[31m" # Red
                fi
                ;;
        esac
    fi

    printf "%-25s | %-15s | ${HEALTH_COLOR}%-10s\e[0m\n" "$CONTAINER" "$STATE" "$HEALTH_RESULT"
done
echo "------------------------------------------------------------"

# Final summary check for the Zabbix Server logs to catch any late database issues
echo "[*] Checking Zabbix Server log for critical errors..."
ERRORS=$(podman logs zabbix-server-pgsql --tail 50 2>&1 | grep -Ei "database is down|connection lost|access denied")

if [ -n "$ERRORS" ]; then
    echo -e "\e[31m[ALERT] Critical messages found in logs:\e[0m"
    echo "$ERRORS"
else
    echo -e "\e[32m[OK] No critical database errors in recent logs.\e[0m"
fi
