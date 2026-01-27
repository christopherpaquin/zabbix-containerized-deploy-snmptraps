#!/bin/bash
# DESCRIPTION: Checks local Zabbix agent configuration and NUT setup
# USAGE: Run this script ON the monitored host (e.g., columbia.lab)
# This script should be copied to the remote host and executed there

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Zabbix Agent Configuration Check${NC}"
echo -e "${BLUE}Host: $(hostname)${NC}"
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

AGENT_CONF=""
AGENT_SERVICE=""

# Determine which agent is installed
AGENT2_PRESENT=false
AGENT1_PRESENT=false

if [ -f "/etc/zabbix/zabbix_agent2.conf" ]; then
    AGENT_CONF="/etc/zabbix/zabbix_agent2.conf"
    AGENT_SERVICE="zabbix-agent2"
    AGENT2_PRESENT=true
fi

if [ -f "/etc/zabbix/zabbix_agentd.conf" ]; then
    AGENT1_PRESENT=true
fi

if [ "$AGENT2_PRESENT" = false ] && [ "$AGENT1_PRESENT" = false ]; then
    print_status "FAIL" "No Zabbix agent configuration found"
    echo "    Install Zabbix agent: dnf install zabbix-agent2"
    exit 1
fi

echo -e "${BLUE}[1/6] Agent Installation${NC}"
print_status "OK" "Found $AGENT_SERVICE configuration: $AGENT_CONF"

# Warn if both agents are present
if [ "$AGENT2_PRESENT" = true ] && [ "$AGENT1_PRESENT" = true ]; then
    print_status "WARN" "Both Agent 1 and Agent 2 are installed!"
    echo "    Old config: /etc/zabbix/zabbix_agentd.conf"
    echo "    New config: /etc/zabbix/zabbix_agent2.conf"
    echo ""
    echo "    If you upgraded from Agent 1 to Agent 2, you may need to:"
    echo "    - Copy custom scripts to new directories"
    echo "    - Migrate user parameters from zabbix_agentd.d/ to zabbix_agent2.d/"
    echo "    - Stop old agent: systemctl stop zabbix-agent && systemctl disable zabbix-agent"
fi
echo ""

# Check agent service status
echo -e "${BLUE}[2/6] Agent Service Status${NC}"
if systemctl is-active --quiet "$AGENT_SERVICE"; then
    print_status "OK" "$AGENT_SERVICE is running"
else
    print_status "FAIL" "$AGENT_SERVICE is NOT running"
    echo ""
    systemctl status "$AGENT_SERVICE" --no-pager -l
    echo ""
    echo "    Start agent: systemctl start $AGENT_SERVICE"
    echo "    Enable on boot: systemctl enable $AGENT_SERVICE"
    exit 1
fi

if systemctl is-enabled --quiet "$AGENT_SERVICE"; then
    print_status "OK" "$AGENT_SERVICE is enabled (will start on boot)"
else
    print_status "WARN" "$AGENT_SERVICE is not enabled"
    echo "    Enable on boot: systemctl enable $AGENT_SERVICE"
fi
echo ""

# Check agent configuration
echo -e "${BLUE}[3/6] Agent Configuration${NC}"

# Check Server parameter
SERVER_LINE=$(grep -E "^Server=" "$AGENT_CONF" 2>/dev/null || echo "")
if [ -n "$SERVER_LINE" ]; then
    print_status "OK" "Server parameter: $SERVER_LINE"
    echo "    Note: Zabbix server IP must be in this list!"
else
    print_status "FAIL" "No Server= parameter found in $AGENT_CONF"
fi

# Check ServerActive parameter
SERVERACTIVE_LINE=$(grep -E "^ServerActive=" "$AGENT_CONF" 2>/dev/null || echo "")
if [ -n "$SERVERACTIVE_LINE" ]; then
    print_status "OK" "ServerActive parameter: $SERVERACTIVE_LINE"
else
    print_status "WARN" "No ServerActive= parameter found"
fi

# Check Hostname parameter
HOSTNAME_LINE=$(grep -E "^Hostname=" "$AGENT_CONF" 2>/dev/null || echo "")
if [ -n "$HOSTNAME_LINE" ]; then
    print_status "OK" "Hostname parameter: $HOSTNAME_LINE"
    echo "    Note: This must match the host name in Zabbix web interface!"
else
    print_status "WARN" "No Hostname= parameter found (using system hostname)"
    echo "    System hostname: $(hostname)"
fi
echo ""

# Check firewall
echo -e "${BLUE}[4/6] Firewall Configuration${NC}"
if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
    if firewall-cmd --list-ports 2>/dev/null | grep -q "10050/tcp"; then
        print_status "OK" "Port 10050/tcp is open in firewall"
    else
        print_status "FAIL" "Port 10050/tcp is NOT open in firewall"
        echo "    Open port: firewall-cmd --add-port=10050/tcp --permanent && firewall-cmd --reload"
    fi
else
    print_status "WARN" "Firewalld not running (assuming no firewall or using iptables)"
fi
echo ""

# Check NUT configuration
echo -e "${BLUE}[5/6] NUT (Network UPS Tools) Configuration${NC}"

if command -v upsc &> /dev/null; then
    print_status "OK" "NUT tools are installed"
    
    # Check NUT services
    for service in nut-server nut-monitor; do
        if systemctl list-unit-files | grep -q "$service"; then
            if systemctl is-active --quiet "$service"; then
                print_status "OK" "$service is running"
            else
                print_status "WARN" "$service is NOT running"
                echo "    Start: systemctl start $service"
            fi
        fi
    done
    
    # Try to list UPS devices
    echo ""
    echo "Available UPS devices:"
    if upsc -l 2>/dev/null | grep -q "."; then
        upsc -l 2>/dev/null | while read ups; do
            echo "  - $ups"
            print_status "OK" "Found UPS: $ups"
            echo ""
            echo "  Testing data retrieval:"
            upsc "$ups" 2>/dev/null | head -10 | sed 's/^/    /'
        done
    else
        print_status "WARN" "No UPS devices found"
        echo "    Check NUT configuration in /etc/ups/"
    fi
else
    print_status "FAIL" "NUT tools not installed"
    echo "    Install NUT: dnf install nut"
fi
echo ""

# Test agent locally
echo -e "${BLUE}[6/6] Agent Local Test${NC}"
echo "Testing if agent responds to local queries..."
echo ""

if [ "$AGENT_SERVICE" = "zabbix-agent2" ]; then
    TEST_CMD="zabbix_agent2 -t"
else
    TEST_CMD="zabbix_agentd -t"
fi

# Test basic item
echo "Testing: agent.ping"
if sudo $TEST_CMD agent.ping 2>&1 | grep -q "agent.ping"; then
    print_status "OK" "Agent responds to agent.ping"
    sudo $TEST_CMD agent.ping 2>&1 | sed 's/^/  /'
else
    print_status "FAIL" "Agent does not respond"
fi
echo ""

# Test NUT items if NUT is installed
if command -v upsc &> /dev/null; then
    echo "Testing NUT items..."
    for key in "nut.ups.status" "nut.ups.load" "nut.ups.charge"; do
        echo "Testing: $key"
        OUTPUT=$(sudo $TEST_CMD "$key" 2>&1 || true)
        if echo "$OUTPUT" | grep -q "ZBX_NOTSUPPORTED"; then
            print_status "WARN" "$key not supported"
            echo "  $OUTPUT" | sed 's/^/    /'
        else
            print_status "OK" "$key working"
            echo "  $OUTPUT" | sed 's/^/    /'
        fi
        echo ""
    done
fi

# Summary and recommendations
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Summary & Recommendations${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Configuration file: $AGENT_CONF"
echo ""
echo "If Zabbix server cannot connect:"
echo "1. Add Zabbix server IP to Server= parameter in $AGENT_CONF"
echo "   Example: Server=127.0.0.1,10.1.10.50"
echo ""
echo "2. Restart agent: systemctl restart $AGENT_SERVICE"
echo ""
echo "3. Check agent logs: journalctl -u $AGENT_SERVICE -n 50"
echo ""

if ! command -v upsc &> /dev/null; then
    echo "To enable UPS monitoring:"
    echo "1. Install NUT: dnf install nut"
    echo "2. Configure UPS in /etc/ups/ups.conf"
    echo "3. Configure NUT mode in /etc/ups/nut.conf"
    echo "4. Start services: systemctl start nut-server nut-monitor"
    echo "5. Apply NUT template in Zabbix web interface"
    echo ""
fi

echo -e "${GREEN}Check complete!${NC}"
