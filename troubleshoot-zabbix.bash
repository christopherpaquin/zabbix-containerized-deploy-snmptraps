#!/bin/bash
# DESCRIPTION: Comprehensive troubleshooting script for Zabbix containerized deployment
# This script helps diagnose common issues with containers, networking, SNMP traps, and systemd services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Load configuration
if [ -f "vars.env" ]; then
    source vars.env
else
    echo "[ERROR] vars.env not found in $SCRIPT_DIR"
    echo "[INFO] Using default values..."
    INSTALL_DIR="/var/lib/zabbix"
    POD_NAME="zabbix-pod"
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Output formatting
print_header() {
    echo -e "\n${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}\n"
}

print_section() {
    echo -e "\n${CYAN}--- $1 ---${NC}"
}

print_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# Check if running as root for certain operations
check_sudo() {
    if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        print_warn "Some checks may require sudo privileges"
    fi
}

# 1. Container Status Check
check_containers() {
    print_header "Container Status Check"
    
    CONTAINERS=("postgres-server" "zabbix-snmptraps" "zabbix-server-pgsql" "zabbix-agent" "zabbix-web-nginx-pgsql")
    
    print_section "Pod Status"
    if podman pod exists "${POD_NAME}" 2>/dev/null; then
        print_ok "Pod '${POD_NAME}' exists"
        podman pod ps --filter "name=${POD_NAME}" --format "table {{.Name}}\t{{.Status}}\t{{.InfraId}}"
    else
        print_error "Pod '${POD_NAME}' does not exist"
        return 1
    fi
    
    print_section "Container Status"
    printf "%-30s | %-15s | %-15s | %-10s\n" "CONTAINER" "STATUS" "HEALTH" "RESTARTS"
    echo "----------------------------------------------------------------------------------------"
    
    for container in "${CONTAINERS[@]}"; do
        if podman ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
            STATUS=$(podman inspect --format '{{.State.Status}}' "$container" 2>/dev/null)
            HEALTH=$(podman inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null)
            RESTARTS=$(podman inspect --format '{{.RestartCount}}' "$container" 2>/dev/null)
            
            if [ "$HEALTH" == "null" ] || [ -z "$HEALTH" ]; then
                HEALTH="N/A"
            fi
            
            if [ "$STATUS" == "running" ]; then
                printf "%-30s | ${GREEN}%-15s${NC} | %-15s | %-10s\n" "$container" "$STATUS" "$HEALTH" "$RESTARTS"
            else
                printf "%-30s | ${RED}%-15s${NC} | %-15s | %-10s\n" "$container" "$STATUS" "$HEALTH" "$RESTARTS"
            fi
        else
            printf "%-30s | ${RED}%-15s${NC} | %-15s | %-10s\n" "$container" "NOT FOUND" "N/A" "N/A"
        fi
    done
    
    print_section "Container Logs (Last 5 lines per container)"
    for container in "${CONTAINERS[@]}"; do
        if podman ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
            echo -e "\n${CYAN}--- $container ---${NC}"
            podman logs --tail 5 "$container" 2>&1 | sed 's/^/  /'
        fi
    done
}

# 2. SNMP Traps Troubleshooting
check_snmptraps() {
    print_header "SNMP Traps Troubleshooting"
    
    print_section "SNMP Traps Container Status"
    if podman ps --format "{{.Names}}" | grep -q "^zabbix-snmptraps$"; then
        print_ok "SNMP traps container is running"
        
        # Check if container is listening on port 1162
        print_section "Port Listening Check"
        if podman exec zabbix-snmptraps cat /proc/net/udp 2>/dev/null | grep -q "048A"; then
            print_ok "Container is listening on UDP port 1162 (0x048A)"
        else
            print_error "Container is NOT listening on UDP port 1162"
        fi
        
        # Check host port mapping
        print_section "Host Port Mapping"
        if ss -ulnp 2>/dev/null | grep -q ":162 "; then
            print_ok "Host port 162/udp is listening"
            ss -ulnp 2>/dev/null | grep ":162 " | sed 's/^/  /'
        else
            print_error "Host port 162/udp is NOT listening"
        fi
        
        # Check traps log file
        print_section "Traps Log File"
        TRAP_LOG="${INSTALL_DIR}/snmptraps/snmptraps.log"
        if [ -f "$TRAP_LOG" ]; then
            print_ok "Traps log file exists: $TRAP_LOG"
            LOG_SIZE=$(stat -f%z "$TRAP_LOG" 2>/dev/null || stat -c%s "$TRAP_LOG" 2>/dev/null)
            print_info "Log file size: $(numfmt --to=iec-i --suffix=B $LOG_SIZE 2>/dev/null || echo "${LOG_SIZE} bytes")"
            
            # Show last few trap entries
            if [ "$LOG_SIZE" -gt 0 ]; then
                echo -e "\n${CYAN}Last 10 lines of traps log:${NC}"
                tail -10 "$TRAP_LOG" 2>/dev/null | sed 's/^/  /'
            else
                print_warn "Traps log file is empty (no traps received yet)"
            fi
        else
            print_error "Traps log file does not exist: $TRAP_LOG"
        fi
        
        # Check SNMP community string
        print_section "SNMP Community Configuration"
        COMMUNITY=$(podman inspect zabbix-snmptraps --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep ZBX_SNMP_COMMUNITY | cut -d= -f2)
        if [ -n "$COMMUNITY" ]; then
            print_ok "SNMP community is configured: ${COMMUNITY:0:3}***"
            if [ -n "$SNMP_COMMUNITY" ] && [ "$COMMUNITY" == "$SNMP_COMMUNITY" ]; then
                print_ok "Community matches vars.env"
            else
                print_warn "Community may not match vars.env"
            fi
        else
            print_error "SNMP community not found in container environment"
        fi
        
        # Check volume mounts
        print_section "Volume Mounts"
        if podman inspect zabbix-snmptraps --format '{{range .Mounts}}{{println .Source " -> " .Destination}}{{end}}' 2>/dev/null | grep -q snmptraps; then
            print_ok "SNMP traps volume is mounted"
            podman inspect zabbix-snmptraps --format '{{range .Mounts}}{{println "  " .Source " -> " .Destination}}{{end}}' 2>/dev/null | grep snmptraps
        else
            print_error "SNMP traps volume is NOT mounted"
        fi
        
    else
        print_error "SNMP traps container is NOT running"
    fi
    
    # Check firewall
    print_section "Firewall Rules"
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        print_info "Firewalld is active"
        if sudo firewall-cmd --list-ports 2>/dev/null | grep -q "162/udp"; then
            print_ok "Port 162/udp is open in firewall"
        else
            print_error "Port 162/udp is NOT open in firewall"
            print_info "Run: sudo firewall-cmd --add-port=162/udp --permanent && sudo firewall-cmd --reload"
        fi
    else
        print_info "Firewalld is not active (or not installed)"
    fi
    
    # Test trap reception
    print_section "Test Trap Reception"
    if command -v snmptrap >/dev/null 2>&1; then
        print_info "Testing trap reception (sending test trap to localhost:162)..."
        if [ -n "$SNMP_COMMUNITY" ]; then
            if snmptrap -v 2c -c "$SNMP_COMMUNITY" 127.0.0.1:162 "" "1.3.6.1.4.1.9.9.41.1.2.3.1.2.1" "1.3.6.1.4.1.9.9.41.1.2.3.1.2.1" s "TROUBLESHOOT_TEST" >/dev/null 2>&1; then
                print_ok "Test trap sent successfully"
                sleep 2
                if tail -1 "$TRAP_LOG" 2>/dev/null | grep -q "TROUBLESHOOT_TEST"; then
                    print_ok "Test trap received and logged"
                else
                    print_warn "Test trap sent but not found in log (may take a moment)"
                fi
            else
                print_error "Failed to send test trap"
            fi
        else
            print_warn "SNMP_COMMUNITY not set in vars.env, skipping test"
        fi
    else
        print_warn "snmptrap command not found (install net-snmp-utils to test)"
    fi
}

# 3. Database Connectivity Check
check_database() {
    print_header "Database Connectivity Check"
    
    print_section "PostgreSQL Container"
    if podman ps --format "{{.Names}}" | grep -q "^postgres-server$"; then
        print_ok "PostgreSQL container is running"
        
        # Test database connection
        print_section "Database Connection Test"
        if podman exec postgres-server pg_isready -U zabbix >/dev/null 2>&1; then
            print_ok "PostgreSQL is ready and accepting connections"
        else
            print_error "PostgreSQL is NOT ready"
        fi
        
        # Check database exists
        print_section "Database Verification"
        if podman exec postgres-server psql -U zabbix -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw zabbix; then
            print_ok "Database 'zabbix' exists"
        else
            print_error "Database 'zabbix' does NOT exist"
        fi
        
        # Check Zabbix server connection
        print_section "Zabbix Server Database Connection"
        if podman ps --format "{{.Names}}" | grep -q "^zabbix-server-pgsql$"; then
            DB_ERRORS=$(podman logs zabbix-server-pgsql --tail 50 2>&1 | grep -iE "database.*down|connection.*lost|access.*denied|authentication.*failed" | head -5)
            if [ -z "$DB_ERRORS" ]; then
                print_ok "No database connection errors in server logs"
            else
                print_error "Database connection errors found:"
                echo "$DB_ERRORS" | sed 's/^/  /'
            fi
        fi
        
        # Check volume mount
        print_section "Database Volume Mount"
        if [ -d "${INSTALL_DIR}/postgres" ]; then
            print_ok "Database volume directory exists: ${INSTALL_DIR}/postgres"
            DB_SIZE=$(du -sh "${INSTALL_DIR}/postgres" 2>/dev/null | cut -f1)
            print_info "Database size: $DB_SIZE"
        else
            print_error "Database volume directory does NOT exist: ${INSTALL_DIR}/postgres"
        fi
    else
        print_error "PostgreSQL container is NOT running"
    fi
}

# 4. Web Interface Check
check_web_interface() {
    print_header "Web Interface Check"
    
    print_section "Web Container Status"
    if podman ps --format "{{.Names}}" | grep -q "^zabbix-web-nginx-pgsql$"; then
        print_ok "Web container is running"
        
        # Check port mapping
        print_section "Port Mapping"
        if ss -tlnp 2>/dev/null | grep -q ":80 "; then
            print_ok "Host port 80/tcp is listening"
            ss -tlnp 2>/dev/null | grep ":80 " | sed 's/^/  /'
        else
            print_error "Host port 80/tcp is NOT listening"
        fi
        
        # Test HTTP connectivity
        print_section "HTTP Connectivity Test"
        if curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://127.0.0.1/ | grep -qE "^[23]"; then
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://127.0.0.1/)
            print_ok "Web interface is accessible (HTTP $HTTP_CODE)"
        else
            print_error "Web interface is NOT accessible"
            print_info "Checking container logs..."
            podman logs zabbix-web-nginx-pgsql --tail 10 2>&1 | sed 's/^/  /'
        fi
        
        # Check firewall
        if systemctl is-active --quiet firewalld 2>/dev/null; then
            if sudo firewall-cmd --list-ports 2>/dev/null | grep -q "80/tcp"; then
                print_ok "Port 80/tcp is open in firewall"
            else
                print_error "Port 80/tcp is NOT open in firewall"
            fi
        fi
    else
        print_error "Web container is NOT running"
    fi
}

# 5. Systemd Service Check
check_systemd() {
    print_header "Systemd Service Check"
    
    SERVICE_NAME="pod-${POD_NAME}.service"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
    
    print_section "Service File"
    if [ -f "$SERVICE_FILE" ]; then
        print_ok "Service file exists: $SERVICE_FILE"
    else
        print_error "Service file does NOT exist: $SERVICE_FILE"
        print_info "Run deploy-zabbix.bash to generate the service file"
    fi
    
    print_section "Service Status"
    if systemctl list-unit-files | grep -q "${SERVICE_NAME}"; then
        if systemctl is-enabled "${SERVICE_NAME}" >/dev/null 2>&1; then
            print_ok "Service is enabled (will start on boot)"
        else
            print_error "Service is NOT enabled (will NOT start on boot)"
            print_info "Run: sudo systemctl enable ${SERVICE_NAME}"
        fi
        
        if systemctl is-active "${SERVICE_NAME}" >/dev/null 2>&1; then
            print_ok "Service is active"
            systemctl status "${SERVICE_NAME}" --no-pager -l | head -10 | sed 's/^/  /'
        else
            print_warn "Service is not active"
            systemctl status "${SERVICE_NAME}" --no-pager -l 2>&1 | head -10 | sed 's/^/  /'
        fi
    else
        print_error "Service is not registered with systemd"
    fi
    
    # Check podman-restart service
    print_section "Podman Restart Service"
    if systemctl is-enabled podman-restart >/dev/null 2>&1; then
        print_ok "podman-restart service is enabled"
    else
        print_warn "podman-restart service is not enabled (optional fallback)"
    fi
}

# 6. Volume Mounts and Permissions
check_volumes() {
    print_header "Volume Mounts and Permissions"
    
    print_section "Directory Structure"
    DIRS=("${INSTALL_DIR}/postgres" "${INSTALL_DIR}/snmptraps" "${INSTALL_DIR}/mibs" "${INSTALL_DIR}/extra_cfg")
    for dir in "${DIRS[@]}"; do
        if [ -d "$dir" ]; then
            print_ok "Directory exists: $dir"
            PERMS=$(stat -c "%a %U:%G" "$dir" 2>/dev/null || stat -f "%OLp %Su:%Sg" "$dir" 2>/dev/null)
            print_info "  Permissions: $PERMS"
        else
            print_error "Directory does NOT exist: $dir"
        fi
    done
    
    print_section "SELinux Context"
    if command -v getenforce >/dev/null 2>&1; then
        if [ "$(getenforce)" != "Disabled" ]; then
            print_info "SELinux is enabled: $(getenforce)"
            for dir in "${DIRS[@]}"; do
                if [ -d "$dir" ]; then
                    CONTEXT=$(stat -c "%C" "$dir" 2>/dev/null || ls -dZ "$dir" 2>/dev/null | awk '{print $1}')
                    if echo "$CONTEXT" | grep -q "container_file_t"; then
                        print_ok "SELinux context correct for $dir: $CONTEXT"
                    else
                        print_warn "SELinux context may be incorrect for $dir: $CONTEXT"
                        print_info "Run: sudo semanage fcontext -a -t container_file_t \"${dir}(/.*)?\" && sudo restorecon -R $dir"
                    fi
                fi
            done
        else
            print_info "SELinux is disabled"
        fi
    fi
    
    print_section "Configuration Files"
    CONFIG_FILE="${INSTALL_DIR}/extra_cfg/zabbix_server_snmp_traps.conf"
    if [ -f "$CONFIG_FILE" ]; then
        print_ok "SNMP traps config file exists: $CONFIG_FILE"
        echo "  Contents:"
        cat "$CONFIG_FILE" | sed 's/^/    /'
    else
        print_error "SNMP traps config file does NOT exist: $CONFIG_FILE"
    fi
}

# 7. Network Connectivity
check_network() {
    print_header "Network Connectivity"
    
    print_section "Pod Network"
    if podman pod exists "${POD_NAME}" 2>/dev/null; then
        POD_IP=$(podman pod inspect "${POD_NAME}" --format '{{.InfraContainerID}}' 2>/dev/null | xargs podman inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
        if [ -n "$POD_IP" ]; then
            print_ok "Pod has network IP: $POD_IP"
        else
            print_info "Pod network information available"
        fi
    fi
    
    print_section "Port Mappings"
    echo "Expected port mappings:"
    echo "  80:8080 (Web interface)"
    echo "  443:8443 (Web interface HTTPS)"
    echo "  10051:10051 (Zabbix server)"
    echo "  162:1162/udp (SNMP traps)"
    echo ""
    echo "Active port mappings:"
    podman pod inspect "${POD_NAME}" --format '{{range .InfraConfig.PortBindings}}{{.}}{{println}}{{end}}' 2>/dev/null | sed 's/^/  /' || print_warn "Could not retrieve port mappings"
    
    print_section "Container-to-Container Communication"
    if podman exec zabbix-server-pgsql ping -c 1 postgres-server >/dev/null 2>&1; then
        print_ok "Zabbix server can reach PostgreSQL container"
    else
        print_error "Zabbix server cannot reach PostgreSQL container"
    fi
}

# 8. Log Analysis
check_logs() {
    print_header "Log Analysis"
    
    CONTAINERS=("postgres-server" "zabbix-snmptraps" "zabbix-server-pgsql" "zabbix-agent" "zabbix-web-nginx-pgsql")
    
    for container in "${CONTAINERS[@]}"; do
        if podman ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
            print_section "$container Logs (Errors/Warnings)"
            ERRORS=$(podman logs "$container" --tail 100 2>&1 | grep -iE "error|warning|fail|fatal|exception" | head -10)
            if [ -n "$ERRORS" ]; then
                echo "$ERRORS" | sed 's/^/  /'
            else
                print_ok "No recent errors or warnings"
            fi
        fi
    done
}

# 9. Configuration Validation
check_config() {
    print_header "Configuration Validation"
    
    print_section "vars.env File"
    if [ -f "vars.env" ]; then
        print_ok "vars.env file exists"
        
        # Check required variables
        REQUIRED_VARS=("DB_PASSWORD" "SNMP_COMMUNITY" "INSTALL_DIR" "POD_NAME")
        for var in "${REQUIRED_VARS[@]}"; do
            if [ -n "${!var}" ]; then
                if [ "$var" == "DB_PASSWORD" ] || [ "$var" == "SNMP_COMMUNITY" ]; then
                    print_ok "$var is set (value hidden)"
                else
                    print_ok "$var is set: ${!var}"
                fi
            else
                print_error "$var is NOT set"
            fi
        done
    else
        print_error "vars.env file does NOT exist"
    fi
    
    print_section "Container Environment Variables"
    if podman ps --format "{{.Names}}" | grep -q "^zabbix-server-pgsql$"; then
        echo "Zabbix Server environment:"
        podman inspect zabbix-server-pgsql --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E "DB_|POSTGRES_" | sed 's/^/  /'
    fi
}

# 10. Resource Usage
check_resources() {
    print_header "Resource Usage"
    
    print_section "Container Resource Usage"
    podman stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null | head -6
    
    print_section "Disk Usage"
    if [ -d "$INSTALL_DIR" ]; then
        du -sh "${INSTALL_DIR}"/* 2>/dev/null | sort -h | sed 's/^/  /'
    fi
}

# Main menu
show_menu() {
    echo -e "\n${BLUE}Zabbix Troubleshooting Menu${NC}"
    echo "1.  Container Status Check"
    echo "2.  SNMP Traps Troubleshooting"
    echo "3.  Database Connectivity Check"
    echo "4.  Web Interface Check"
    echo "5.  Systemd Service Check"
    echo "6.  Volume Mounts and Permissions"
    echo "7.  Network Connectivity"
    echo "8.  Log Analysis"
    echo "9.  Configuration Validation"
    echo "10. Resource Usage"
    echo "11. Run All Checks"
    echo "0.  Exit"
    echo -n -e "\n${CYAN}Select an option: ${NC}"
}

# Main execution
main() {
    clear
    print_header "Zabbix Deployment Troubleshooting Tool"
    print_info "Pod: ${POD_NAME}"
    print_info "Install Directory: ${INSTALL_DIR}"
    
    if [ "$1" == "--all" ] || [ "$1" == "-a" ]; then
        check_containers
        check_snmptraps
        check_database
        check_web_interface
        check_systemd
        check_volumes
        check_network
        check_logs
        check_config
        check_resources
        
        print_header "Troubleshooting Complete"
        echo -e "${GREEN}Review the output above for any errors or warnings.${NC}\n"
    elif [ "$1" == "--containers" ] || [ "$1" == "-c" ]; then
        check_containers
    elif [ "$1" == "--snmptraps" ] || [ "$1" == "-s" ]; then
        check_snmptraps
    elif [ "$1" == "--database" ] || [ "$1" == "-d" ]; then
        check_database
    elif [ "$1" == "--web" ] || [ "$1" == "-w" ]; then
        check_web_interface
    elif [ "$1" == "--systemd" ]; then
        check_systemd
    elif [ "$1" == "--volumes" ] || [ "$1" == "-v" ]; then
        check_volumes
    elif [ "$1" == "--network" ] || [ "$1" == "-n" ]; then
        check_network
    elif [ "$1" == "--logs" ] || [ "$1" == "-l" ]; then
        check_logs
    elif [ "$1" == "--config" ]; then
        check_config
    elif [ "$1" == "--resources" ] || [ "$1" == "-r" ]; then
        check_resources
    else
        # Interactive mode
        while true; do
            show_menu
            read -r choice
            case $choice in
                1) check_containers ;;
                2) check_snmptraps ;;
                3) check_database ;;
                4) check_web_interface ;;
                5) check_systemd ;;
                6) check_volumes ;;
                7) check_network ;;
                8) check_logs ;;
                9) check_config ;;
                10) check_resources ;;
                11) 
                    check_containers
                    check_snmptraps
                    check_database
                    check_web_interface
                    check_systemd
                    check_volumes
                    check_network
                    check_logs
                    check_config
                    check_resources
                    print_header "Troubleshooting Complete"
                    ;;
                0) 
                    echo "Exiting..."
                    exit 0
                    ;;
                *) 
                    print_error "Invalid option. Please try again."
                    sleep 1
                    ;;
            esac
            echo -e "\n${CYAN}Press Enter to continue...${NC}"
            read -r
            clear
        done
    fi
}

# Run main function
main "$@"

