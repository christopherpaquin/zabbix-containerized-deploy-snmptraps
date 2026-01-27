#!/bin/bash
# DESCRIPTION: Tests Zabbix agent connectivity and ability to pull data from a remote host
# USAGE: ./test-agent-connectivity.bash <IP_OR_HOSTNAME>

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if IP/hostname provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <IP_OR_HOSTNAME>"
    echo "Example: $0 columbia.lab"
    echo "Example: $0 10.1.10.21"
    exit 1
fi

TARGET_HOST="$1"
ZABBIX_SERVER_CONTAINER="zabbix-server-pgsql"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Zabbix Agent Connectivity Test${NC}"
echo -e "${BLUE}Target: ${TARGET_HOST}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "OK" ]; then
        echo -e "[${GREEN}✓${NC}] $message"
    elif [ "$status" = "WARN" ]; then
        echo -e "[${YELLOW}⚠${NC}] $message"
    else
        echo -e "[${RED}✗${NC}] $message"
    fi
}

# Function to run test
run_test() {
    local test_name=$1
    local command=$2
    echo -e "\n${YELLOW}[TEST]${NC} ${test_name}"
    echo "Command: ${command}"
    echo "---"
    eval "$command"
    echo ""
}

# 1. Test basic network connectivity
echo -e "${BLUE}[1/7] Network Connectivity Test${NC}"
if ping -c 2 -W 2 "$TARGET_HOST" &> /dev/null; then
    IP=$(ping -c 1 "$TARGET_HOST" 2>/dev/null | grep -oP '(?<=\().*(?=\))' | head -1)
    print_status "OK" "Host is reachable (IP: $IP)"
else
    print_status "FAIL" "Cannot ping $TARGET_HOST"
    echo "    Check: Network connectivity, firewall, or hostname resolution"
    exit 1
fi

# 2. Test DNS resolution
echo -e "\n${BLUE}[2/7] DNS Resolution Test${NC}"
if getent hosts "$TARGET_HOST" &> /dev/null; then
    RESOLVED=$(getent hosts "$TARGET_HOST")
    print_status "OK" "DNS resolution successful: $RESOLVED"
else
    print_status "WARN" "DNS resolution failed for $TARGET_HOST"
    echo "    Using IP address for remaining tests..."
fi

# 3. Test Zabbix agent port (10050)
echo -e "\n${BLUE}[3/7] Zabbix Agent Port Test (10050/tcp)${NC}"
if timeout 3 bash -c "echo > /dev/tcp/$TARGET_HOST/10050" 2>/dev/null; then
    print_status "OK" "Port 10050 is open and accepting connections"
else
    print_status "FAIL" "Cannot connect to port 10050"
    echo "    Possible causes:"
    echo "    - Zabbix agent not running on $TARGET_HOST"
    echo "    - Firewall blocking port 10050"
    echo "    - Agent listening on different port/interface"
    echo ""
    echo "    On $TARGET_HOST, run:"
    echo "      systemctl status zabbix-agent2"
    echo "      firewall-cmd --add-port=10050/tcp --permanent && firewall-cmd --reload"
    exit 1
fi

# 4. Test if Zabbix container is running
echo -e "\n${BLUE}[4/7] Zabbix Server Container Status${NC}"
if podman ps --format "{{.Names}}" | grep -q "^${ZABBIX_SERVER_CONTAINER}$"; then
    print_status "OK" "Zabbix server container is running"
else
    print_status "FAIL" "Zabbix server container is not running"
    echo "    Run: podman ps -a --filter name=zabbix-server"
    exit 1
fi

# 5. Test basic agent ping
echo -e "\n${BLUE}[5/7] Agent Ping Test${NC}"
run_test "Testing agent.ping" "podman exec $ZABBIX_SERVER_CONTAINER zabbix_get -s '$TARGET_HOST' -k agent.ping 2>&1"
if podman exec "$ZABBIX_SERVER_CONTAINER" zabbix_get -s "$TARGET_HOST" -k agent.ping 2>&1 | grep -q "^1$"; then
    print_status "OK" "Agent responds to ping"
else
    print_status "FAIL" "Agent does not respond to ping"
    echo ""
    echo "    Common causes:"
    echo "    1. Agent's Server= parameter doesn't allow this Zabbix server"
    echo "       On $TARGET_HOST, check: grep '^Server=' /etc/zabbix/zabbix_agent2.conf"
    echo "       Should include: $(hostname -I | awk '{print $1}')"
    echo ""
    echo "    2. Hostname mismatch"
    echo "       On $TARGET_HOST, check: grep '^Hostname=' /etc/zabbix/zabbix_agent2.conf"
    echo ""
    echo "    3. Agent crashed or in error state"
    echo "       On $TARGET_HOST, run: systemctl status zabbix-agent2"
    echo "                            journalctl -u zabbix-agent2 -n 50"
    exit 1
fi

# 6. Test common agent items
echo -e "\n${BLUE}[6/7] Common Agent Items Test${NC}"

# Test system.uname
run_test "System information (system.uname)" "podman exec $ZABBIX_SERVER_CONTAINER zabbix_get -s '$TARGET_HOST' -k system.uname 2>&1"

# Test system.hostname
run_test "Hostname (system.hostname)" "podman exec $ZABBIX_SERVER_CONTAINER zabbix_get -s '$TARGET_HOST' -k system.hostname 2>&1"

# Test agent.version
run_test "Agent version (agent.version)" "podman exec $ZABBIX_SERVER_CONTAINER zabbix_get -s '$TARGET_HOST' -k agent.version 2>&1"

# Test system load
run_test "System load (system.cpu.load[percpu,avg1])" "podman exec $ZABBIX_SERVER_CONTAINER zabbix_get -s '$TARGET_HOST' -k 'system.cpu.load[percpu,avg1]' 2>&1"

# 7. Test NUT/UPS specific items (if applicable)
echo -e "\n${BLUE}[7/7] NUT/UPS Monitoring Test${NC}"
echo "Testing if NUT (Network UPS Tools) monitoring is available..."
echo ""

# Try to get UPS status
run_test "UPS status (nut.ups.status)" "podman exec $ZABBIX_SERVER_CONTAINER zabbix_get -s '$TARGET_HOST' -k 'nut.ups.status' 2>&1"

# Try to get UPS load
run_test "UPS load (nut.ups.load)" "podman exec $ZABBIX_SERVER_CONTAINER zabbix_get -s '$TARGET_HOST' -k 'nut.ups.load' 2>&1"

# Try to get battery charge
run_test "Battery charge (nut.ups.charge)" "podman exec $ZABBIX_SERVER_CONTAINER zabbix_get -s '$TARGET_HOST' -k 'nut.ups.charge' 2>&1"

# Check for NUT errors
if podman exec "$ZABBIX_SERVER_CONTAINER" zabbix_get -s "$TARGET_HOST" -k 'nut.ups.status' 2>&1 | grep -qE "Unsupported item key|not supported"; then
    print_status "WARN" "NUT monitoring items not available on this agent"
    echo ""
    echo "    To enable NUT monitoring on $TARGET_HOST:"
    echo "    1. Install NUT: dnf install nut"
    echo "    2. Configure NUT to monitor your UPS"
    echo "    3. Ensure Zabbix agent can access NUT data"
    echo "    4. Apply NUT template in Zabbix web interface"
    echo ""
    echo "    Test NUT locally on $TARGET_HOST:"
    echo "      upsc <ups_name>@localhost"
    echo "      zabbix_agent2 -t nut.ups.status"
elif podman exec "$ZABBIX_SERVER_CONTAINER" zabbix_get -s "$TARGET_HOST" -k 'nut.ups.status' 2>&1 | grep -q "OL\|OB"; then
    print_status "OK" "NUT monitoring is working!"
fi

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Target Host: ${GREEN}${TARGET_HOST}${NC}"
echo -e "Zabbix Server IP: ${GREEN}$(hostname -I | awk '{print $1}')${NC}"
echo ""
echo "If all tests passed but host still shows as unavailable in Zabbix:"
echo "1. Check host configuration in Zabbix web interface"
echo "2. Verify hostname in Zabbix matches agent's Hostname= parameter"
echo "3. Check Zabbix server logs: podman logs zabbix-server-pgsql | grep '$TARGET_HOST'"
echo "4. Ensure correct template is applied to the host"
echo ""
echo -e "${GREEN}Testing complete!${NC}"
