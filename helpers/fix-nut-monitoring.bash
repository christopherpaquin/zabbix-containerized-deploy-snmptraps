#!/bin/bash
# DESCRIPTION: Diagnose and fix NUT monitoring for Zabbix agent
# RUN THIS ON: The monitored host (e.g., columbia.lab)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}NUT Monitoring Diagnostic & Fix${NC}"
echo -e "${BLUE}Host: $(hostname)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

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

# 1. Check if NUT is installed
echo -e "${BLUE}[1/6] NUT Installation Check${NC}"
if command -v upsc &> /dev/null; then
    print_status "OK" "NUT tools are installed"
    upsc -V 2>&1 | head -1
else
    print_status "FAIL" "NUT is not installed"
    echo "    Install: dnf install nut"
    exit 1
fi
echo ""

# 2. Check NUT services
echo -e "${BLUE}[2/6] NUT Services Status${NC}"
for service in nut-server nut-monitor; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        print_status "OK" "$service is running"
    else
        print_status "FAIL" "$service is NOT running"
        echo "    Start: systemctl start $service"
        echo "    Enable: systemctl enable $service"
    fi
done
echo ""

# 3. Check NUT configuration
echo -e "${BLUE}[3/6] NUT Configuration${NC}"
if [ -f /etc/ups/nut.conf ]; then
    MODE=$(grep -v '^#' /etc/ups/nut.conf | grep MODE | cut -d= -f2 | tr -d ' ')
    if [ -n "$MODE" ]; then
        print_status "OK" "NUT mode is set to: $MODE"
    else
        print_status "WARN" "NUT mode not set in /etc/ups/nut.conf"
        echo "    Add: MODE=standalone"
    fi
else
    print_status "FAIL" "/etc/ups/nut.conf not found"
fi

if [ -f /etc/ups/ups.conf ]; then
    print_status "OK" "/etc/ups/ups.conf exists"
    echo "    Configured UPS devices:"
    grep -E '^\[.*\]' /etc/ups/ups.conf 2>/dev/null | sed 's/^/      /' || echo "      None found"
else
    print_status "WARN" "/etc/ups/ups.conf not found"
fi
echo ""

# 4. Check UPS devices
echo -e "${BLUE}[4/6] UPS Device Discovery${NC}"
UPS_LIST=$(upsc -l 2>/dev/null || echo "")
if [ -n "$UPS_LIST" ]; then
    print_status "OK" "Found UPS devices:"
    echo "$UPS_LIST" | while read ups; do
        echo "      - $ups"
        echo "        Testing connection..."
        if upsc "$ups" ups.status 2>/dev/null | grep -q .; then
            STATUS=$(upsc "$ups" ups.status 2>/dev/null)
            print_status "OK" "Status: $STATUS"
        else
            print_status "FAIL" "Cannot query $ups"
        fi
    done
else
    print_status "FAIL" "No UPS devices found"
    echo "    Check /etc/ups/ups.conf configuration"
    echo "    Run: upsdrvctl start"
fi
echo ""

# 5. Check Zabbix agent NUT plugin
echo -e "${BLUE}[5/6] Zabbix Agent NUT Plugin${NC}"

# Determine which agent is installed
if [ -f "/etc/zabbix/zabbix_agent2.conf" ]; then
    AGENT_CONF="/etc/zabbix/zabbix_agent2.conf"
    AGENT_CMD="zabbix_agent2"
    print_status "OK" "Using Zabbix Agent 2"
else
    print_status "FAIL" "Zabbix Agent 2 not found"
    echo "    NUT monitoring requires Zabbix Agent 2"
    exit 1
fi

# Test if agent can query NUT
echo ""
echo "Testing NUT item keys..."
if [ -n "$UPS_LIST" ]; then
    FIRST_UPS=$(echo "$UPS_LIST" | head -1)
    
    # Test without UPS name (default)
    echo -n "  nut.ups.status: "
    RESULT=$($AGENT_CMD -t nut.ups.status 2>&1 || true)
    if echo "$RESULT" | grep -qE "OL|OB|DISCHRG|CHRG"; then
        echo -e "${GREEN}✓ Working${NC}"
    elif echo "$RESULT" | grep -q "ZBX_NOTSUPPORTED"; then
        echo -e "${RED}✗ Not Supported${NC}"
        echo "      $RESULT"
    else
        echo -e "${YELLOW}⚠ Unknown: $RESULT${NC}"
    fi
    
    # Test with UPS name
    echo -n "  nut.ups.status[$FIRST_UPS]: "
    RESULT=$($AGENT_CMD -t "nut.ups.status[$FIRST_UPS]" 2>&1 || true)
    if echo "$RESULT" | grep -qE "OL|OB|DISCHRG|CHRG"; then
        echo -e "${GREEN}✓ Working${NC}"
    elif echo "$RESULT" | grep -q "ZBX_NOTSUPPORTED"; then
        echo -e "${RED}✗ Not Supported${NC}"
        echo "      $RESULT"
    else
        echo -e "${YELLOW}⚠ Unknown: $RESULT${NC}"
    fi
fi
echo ""

# 6. Check plugin configuration
echo -e "${BLUE}[6/6] NUT Plugin Configuration${NC}"

PLUGIN_CONF="/etc/zabbix/zabbix_agent2.d/plugins.d/nut.conf"
if [ -f "$PLUGIN_CONF" ]; then
    print_status "OK" "NUT plugin config exists: $PLUGIN_CONF"
    echo "    Current settings:"
    cat "$PLUGIN_CONF" | grep -v '^#' | grep -v '^$' | sed 's/^/      /'
else
    print_status "WARN" "No NUT plugin configuration found"
    echo "    Creating default configuration..."
    
    mkdir -p /etc/zabbix/zabbix_agent2.d/plugins.d/
    
    if [ -n "$UPS_LIST" ]; then
        FIRST_UPS=$(echo "$UPS_LIST" | head -1)
        cat > "$PLUGIN_CONF" << PLUGINEOF
# NUT plugin configuration
Plugins.Nut.UPSName=$FIRST_UPS
Plugins.Nut.Timeout=3
PLUGINEOF
        print_status "OK" "Created $PLUGIN_CONF"
        cat "$PLUGIN_CONF" | sed 's/^/      /'
    fi
fi
echo ""

# Summary and recommendations
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Summary & Fix Actions${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if everything is working
NEEDS_FIX=0

if ! systemctl is-active --quiet nut-server 2>/dev/null; then
    echo -e "${YELLOW}Action Required:${NC} Start NUT services"
    echo "  systemctl start nut-server nut-monitor"
    echo "  systemctl enable nut-server nut-monitor"
    NEEDS_FIX=1
fi

if [ -z "$UPS_LIST" ]; then
    echo -e "${YELLOW}Action Required:${NC} Configure UPS devices"
    echo "  1. Edit /etc/ups/ups.conf"
    echo "  2. Add your UPS configuration"
    echo "  3. Run: upsdrvctl start"
    NEEDS_FIX=1
fi

if $AGENT_CMD -t nut.ups.status 2>&1 | grep -q "ZBX_NOTSUPPORTED"; then
    echo -e "${YELLOW}Action Required:${NC} Configure Zabbix NUT plugin"
    echo "  1. Ensure NUT plugin config exists: $PLUGIN_CONF"
    if [ -n "$UPS_LIST" ]; then
        FIRST_UPS=$(echo "$UPS_LIST" | head -1)
        echo "  2. Set UPS name: Plugins.Nut.UPSName=$FIRST_UPS"
    fi
    echo "  3. Restart agent: systemctl restart zabbix-agent2"
    NEEDS_FIX=1
fi

if [ $NEEDS_FIX -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}After fixing, restart the Zabbix agent:${NC}"
    echo "  systemctl restart zabbix-agent2"
    echo ""
    echo -e "${YELLOW}Then test from Zabbix server:${NC}"
    echo "  ./helpers/test-agent-connectivity.bash $(hostname)"
else
    echo -e "${GREEN}✓ All checks passed! NUT monitoring should be working.${NC}"
fi

echo ""
echo -e "${GREEN}Diagnostic complete!${NC}"
