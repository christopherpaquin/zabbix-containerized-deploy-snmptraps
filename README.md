# Zabbix Containerized SNMP Trap Deployment

> **Containerized Zabbix monitoring stack with SNMP trap support, deployed via Podman**

![Tested on RHEL 10.1](https://img.shields.io/badge/Tested%20on-RHEL%2010.1-red?style=flat-square) ![Zabbix 7.4.6](https://img.shields.io/badge/Zabbix-7.4.6-blue?style=flat-square) ![Podman](https://img.shields.io/badge/Podman-Container-orange?style=flat-square)

---

## 📋 Overview

This repository provides a complete containerized deployment solution for **Zabbix** (default version **7.4.6**) using **Podman**, specifically architected to handle **SNMP Traps** through a shared-volume "trapper" pattern. This design ensures trap data is received by a lightweight listener and processed by the core Zabbix engine without complex internal networking.

The Zabbix version is fully configurable via the `ZABBIX_VERSION` variable in `vars.env`, allowing you to deploy any available Zabbix version.

### Architecture

The deployment uses a shared-volume pattern where:
- **SNMP Trap Receiver** writes traps to a shared volume
- **Zabbix Server** reads from the same volume
- No complex networking required between containers

### Stack Components

| Component | Image | Purpose |
|-----------|-------|---------|
| **Database** | `postgres:16-alpine` | PostgreSQL 16 database |
| **Trap Receiver** | `zabbix/zabbix-snmptraps:alpine-${ZABBIX_VERSION}-latest` | Receives and logs SNMP traps |
| **Core Engine** | `zabbix/zabbix-server-pgsql:alpine-${ZABBIX_VERSION}-latest` | Zabbix server processing engine |
| **Web Interface** | `zabbix/zabbix-web-nginx-pgsql:alpine-${ZABBIX_VERSION}-latest` | Web UI for monitoring |
| **Agent** | `zabbix/zabbix-agent2:alpine-${ZABBIX_VERSION}-latest` | Local agent for server monitoring |

---

## 🔧 Prerequisites

Before deploying, ensure you have:

- ✅ **Podman** installed and running
- ✅ **net-snmp-utils** installed on the host (for testing)
- ✅ **SELinux** configured (if using RHEL/CentOS)
- ✅ **Firewall** access to ports 80/tcp and 162/udp

**Tested Environment:** RHEL 10.1

---

## ⚙️ Configuration

### Environment Variables (`vars.env`)

> ⚠️ **CRITICAL:** The `vars.env` file is ignored by Git. Ensure your `.gitignore` includes `vars.env` to prevent committing secrets to your repository.

Create `vars.env` from the provided template:

```bash
cp vars.env.template vars.env
vim vars.env
```

**Required Configuration:**

```bash
# --- ZABBIX VERSION ---
# Zabbix version to deploy (e.g., 7.4.6, 7.2, 7.0, etc.)
ZABBIX_VERSION="7.4.6"

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

> **Note:** You can change the `ZABBIX_VERSION` variable to deploy any version of Zabbix. For example:
> - `ZABBIX_VERSION="7.4.6"` (default, latest stable)
> - `ZABBIX_VERSION="7.2"` (previous stable)
> - `ZABBIX_VERSION="7.0"` (older stable)
>
> Ensure the version you specify has available Docker images at [Zabbix Docker Hub](https://hub.docker.com/u/zabbix).

---

## 🚀 Quick Start

### Step 1: Cleanup (Optional)

> **Note:** Skip this step for initial deployment. Run before subsequent deployments to ensure a clean state.

The cleanup script supports two modes:

#### Standard Cleanup
Removes containers/pods but preserves your Zabbix configuration and database.

```bash
./cleanup-zabbix.bash
```

#### Factory Reset
⚠️ **WARNING:** Removes containers and deletes all data (database, hosts, and logs). Use this to start from a completely blank Zabbix install.

```bash
./cleanup-zabbix.bash --factory-reset
```

### Step 2: Deploy

This script handles:
- Directory creation
- Security labeling (SELinux)
- Container orchestration
- Firewall configuration

```bash
./deploy-zabbix.bash
```

### Step 3: Health Check

Verify that all containers are running and the internal "SNMP Trapper" process is active.

```bash
./check-zabbix-health.bash
```

**Expected Output:**
```
COMPONENT                  | STATUS          | HEALTH
------------------------------------------------------------
postgres-server            | running         | [OK]
zabbix-snmptraps           | running         | [OK]
zabbix-server-pgsql        | running         | [OK]
zabbix-agent               | running         | [OK]
zabbix-web-nginx-pgsql     | running         | [OK]
```

---

## 🌐 Zabbix Web UI Configuration

### Initial Setup

1. **Login:** Access `http://<ZABBIX_SERVER_IP>` 
   - Default credentials: `Admin` / `zabbix`

2. **Create Host:** 
   - Navigate to **Data Collection > Hosts**
   - Click **Create host**

3. **SNMP Interface:** 
   - Add a Host with an SNMP interface
   - Use the `TEST_SENDER_IP` from your `vars.env` as the IP address

4. **Macros:** 
   - Add the macro `{$SNMP_COMMUNITY}` 
   - Set it to your community string from `vars.env`

5. **Force Config Cache Reload:**
   ```bash
   podman exec zabbix-server-pgsql zabbix_server -R config_cache_reload
   ```
   > This forces Zabbix to recognize changes immediately instead of waiting 60 seconds

---

## 🔍 Troubleshooting & Verification

### Automated Troubleshooting Tool

The `troubleshoot-zabbix.bash` script provides comprehensive diagnostic capabilities for your Zabbix deployment. It automatically checks all components and provides actionable recommendations.

#### Quick Start

**Run all diagnostic checks:**
```bash
./troubleshoot-zabbix.bash --all
```

**Interactive menu mode:**
```bash
./troubleshoot-zabbix.bash
```

**Run specific diagnostic checks:**
```bash
./troubleshoot-zabbix.bash --snmptraps    # SNMP traps troubleshooting
./troubleshoot-zabbix.bash --containers  # Container status check
./troubleshoot-zabbix.bash --database     # Database connectivity
./troubleshoot-zabbix.bash --web         # Web interface check
./troubleshoot-zabbix.bash --systemd     # Systemd service status
./troubleshoot-zabbix.bash --volumes     # Volume mounts and permissions
./troubleshoot-zabbix.bash --network     # Network connectivity
./troubleshoot-zabbix.bash --logs        # Log analysis
./troubleshoot-zabbix.bash --config      # Configuration validation
./troubleshoot-zabbix.bash --resources   # Resource usage
```

#### What It Checks

The troubleshooting script performs comprehensive checks across 10 diagnostic categories:

1. **Container Status Check**
   - Pod existence and status
   - Individual container status, health, and restart counts
   - Recent container logs

2. **SNMP Traps Troubleshooting**
   - Container listening status on UDP port 1162
   - Host port mapping (162/udp)
   - Traps log file existence and content
   - SNMP community string validation
   - Volume mount verification
   - Firewall rules
   - **Automatic test trap sending and verification**

3. **Database Connectivity Check**
   - PostgreSQL container status
   - Database readiness and existence
   - Connection error detection
   - Volume mount verification

4. **Web Interface Check**
   - Container status
   - Port mapping (80/tcp)
   - HTTP connectivity test
   - Firewall rules

5. **Systemd Service Check**
   - Service file existence
   - Service enabled/active status
   - Boot persistence verification

6. **Volume Mounts and Permissions**
   - Directory structure validation
   - File permissions
   - SELinux context verification
   - Configuration file validation

7. **Network Connectivity**
   - Pod network information
   - Port mappings
   - Container-to-container communication

8. **Log Analysis**
   - Error and warning detection across all containers
   - Recent log review

9. **Configuration Validation**
   - vars.env file validation
   - Required variables check
   - Container environment variables

10. **Resource Usage**
    - Container CPU and memory usage
    - Disk usage analysis

#### Example Output

The script provides color-coded output for easy identification:
- 🟢 **Green [OK]**: Component is healthy
- 🔴 **Red [ERROR]**: Critical issue detected
- 🟡 **Yellow [WARN]**: Warning or potential issue
- 🔵 **Cyan [INFO]**: Informational message

#### Common Issues and Solutions

The script automatically detects and provides solutions for common issues:

- **Containers not starting after reboot**: Checks systemd service configuration
- **SNMP traps not being received**: Validates port mappings, firewall, and container status
- **Database connection errors**: Verifies PostgreSQL status and connectivity
- **Web interface inaccessible**: Checks container status, port mappings, and firewall
- **Permission issues**: Validates SELinux contexts and file permissions

### Manual Troubleshooting Chain

If traps do not appear in **Monitoring > Latest Data**, follow this diagnostic flow:

| Level | Check | Command |
|-------|-------|---------|
| **Network** | Does the packet reach the host? | `sudo tcpdump -ni any udp port 162` |
| **Receiver** | Is the container receiving data? | `podman logs zabbix-snmptraps` |
| **Storage** | Is the trap written to the log? | `cat /var/lib/zabbix/snmptraps/snmptraps.log` |
| **Server** | Is there an IP mismatch? | `podman logs zabbix-server-pgsql \| grep unmatched` |

> **Note:** If "unmatched" appears in the logs, the Source IP of the trap does not match the IP configured in the Web UI.

### Manual Trap Testing

#### Using the Test Script

Use the included test script to verify the pipeline. **Important:** Run this script from the host that matches your `TEST_SENDER_IP` configuration.

```bash
./test-network-trap.bash "MY_VALIDATION_MESSAGE"
```

#### Example Scenarios

**Simulating a Cisco Link Down Event:**
```bash
./test-network-trap.bash "Interface GigabitEthernet0/1, changed state to down"
```

**Simulating a Cisco Link Up Event:**
```bash
./test-network-trap.bash "Interface GigabitEthernet0/1, changed state to up"
```

**Simulating a Configuration Change:**
```bash
./test-network-trap.bash "Configured from console by vty0 (10.1.10.50)"
```

#### Manual SNMP Trap Command

If you prefer not to use the test script, send traps manually:

```bash
snmptrap -v 2c -c <YOUR_SNMP_COMMUNITY> <IP_OF_ZABBIX_HOST>:162 "" \
  1.3.6.1.4.1.9.9.41.1.2.3.1.2.1 \
  1.3.6.1.4.1.9.9.41.1.2.3.1.2.1 \
  s "Interface GigabitEthernet0/1, changed state to down"
```

**Example:**
```bash
snmptrap -v 2c -c public 10.1.10.50:162 "" \
  1.3.6.1.4.1.9.9.41.1.2.3.1.2.1 \
  1.3.6.1.4.1.9.9.41.1.2.3.1.2.1 \
  s "Interface GigabitEthernet0/1, changed state to down"
```

#### Remote Testing Rationale

When testing from the Zabbix host itself, the trap source IP will be a Podman network IP (e.g., `10.88.0.1`), not the physical host IP. 

**Key Points:**
- Testing from an external host validates firewall configurations
- The IP of the host sending the alert **must match** the IP of the monitored interface in Zabbix
- If testing locally, configure the monitored device interface to use the Podman IP

**Example Log Output:**
```bash
tail -f /var/lib/zabbix/snmptraps/snmptraps.log
```

```
2025-12-28T17:52:33+0000 ZBXTRAP 10.88.0.1
UDP: [10.88.0.1]:43161->[10.88.0.19]:1162
DISMAN-EVENT-MIB::sysUpTimeInstance = 14085669
SNMPv2-MIB::snmpTrapOID.0 = SNMPv2-SMI::enterprises.9.9.41.1.2.3.1.2.1
SNMPv2-SMI::enterprises.9.9.41.1.2.3.1.2.1 = "Interface GigabitEthernet0/1, changed state to down"
```

#### Verification Steps

1. **Check the Shared Log:**
   ```bash
   tail -f /var/lib/zabbix/snmptraps/snmptraps.log
   ```
   You should see the trap enter the file instantly.

2. **Check the Web UI:**
   - Navigate to **Monitoring > Latest Data**
   - Filter by your host
   - Look for the **SNMP traps (fallback)** item

---

## 🔒 Security and Permissions

This deployment implements the following security measures:

- **UID Mapping:** Host directories are owned by UID `1001` (Zabbix container user)
- **SELinux:** Volumes are mounted with the `:z` and `:U` flags to automatically manage security contexts
- **Global Write:** The `snmptraps/` directory uses `777` permissions to ensure the receiver can write while the server reads

### Manual Permission Reset

If you need to manually reset permissions:

```bash
chown -R 1001:1001 /var/lib/zabbix/snmptraps
chmod -R 777 /var/lib/zabbix/snmptraps
chcon -R -t container_file_t /var/lib/zabbix/snmptraps
```

---

## 📚 MIBs Management

The MIB Management system ensures SNMP traps from various vendors (Cisco, Juniper, Dell, APC) are translated from numeric OIDs into human-readable text.

### Components

- **`mibs.conf`** - Configuration file defining vendor MIB sources
- **`manage-mibs.bash`** - Strategic extraction engine script

### Configuration File (`mibs.conf`)

The `mibs.conf` file is the central source of truth for all external MIB dependencies. It follows a **pipe-delimited (`|`)** format:

```
Vendor_Name | Download_URL
```

**Fields:**
- **Vendor_Name:** A unique label for the hardware vendor (case-sensitive)
- **Download_URL:** Link to either a direct file (e.g., `IF-MIB.txt`) or a repository ZIP archive

**Example:**
```
Standard_Core|https://github.com/net-snmp/net-snmp/archive/refs/heads/master.zip
Cisco_Mibs|https://github.com/librenms/librenms/archive/refs/heads/master.zip
```

### Adding New Vendors

1. Open `mibs.conf` in a text editor
2. Add a new line following the pipe-delimited format
3. **Note:** If adding a vendor from the LibreNMS repository, use the master ZIP URL and ensure the `Vendor_Name` matches one of the handled cases in the script

### ZIP Extraction Logic

The `manage-mibs.bash` script performs "Selective Extraction" to keep the monitoring environment lean. It handles vendor-specific extraction paths:

| Vendor Name | ZIP Extraction Path | Purpose |
|-------------|---------------------|---------|
| `Standard_Core` | `*/mibs/*` | Base networking OIDs (IF-MIB, etc.) |
| `Cisco_Mibs` | `*-master/mibs/cisco/*` | Cisco switches and routers |
| `Juniper_Mibs` | `*-master/mibs/juniper/*` | Juniper Junos devices |
| `Dell_iDRAC` | `*-master/mibs/dell/*` | Dell PowerEdge Servers |
| `APC_PDU` | `*-master/mibs/apc/*` | APC UPS and PDU units |

### Automation Process

When executed, `manage-mibs.bash` performs:

1. **Prerequisite Check:** Automatically checks for and installs `curl` and `unzip`
2. **URL Validation:** Uses `curl -L --head` to verify the URL exists before attempting download
3. **Selective Extraction:** Extracts only vendor-specific MIBs from ZIP archives
4. **Normalization:** Converts all `.txt` and `.my` files to `.mib` (required by Net-SNMP)
5. **Security:** Applies `chmod 755` and SELinux `container_file_t` contexts
6. **Service Reload:** Restarts `zabbix-snmptraps` and `zabbix-server-pgsql` containers to re-index the library

### Usage

**Synchronize MIB library:**
```bash
chmod +x manage-mibs.bash
./manage-mibs.bash
```

**Verify MIB Translation:**

Test that a specific vendor's MIB has been correctly indexed:

```bash
podman exec zabbix-snmptraps snmptranslate -On CISCO-CONFIG-MAN-MIB::ciscoConfigManEvent
```

*Expected Result:* `.1.3.6.1.4.1.9.9.43.2.0.1`

### Directory Structure

The system maintains a flat directory structure for optimal indexing:

- **Host Path:** `/var/lib/zabbix/mibs/`
- **Container Path:** `/usr/share/snmp/mibs/` (mapped via volume)

> ⚠️ **Warning:** Do not manually place files in the MIB directory without running the script afterward, as the containers must be restarted to recognize new files.

---

## 🛠️ Additional Scripts

| Script | Purpose |
|--------|---------|
| `deploy-zabbix.bash` | Main deployment script |
| `check-zabbix-health.bash` | Health check for all containers |
| `troubleshoot-zabbix.bash` | Comprehensive diagnostic and troubleshooting tool |
| `cleanup-zabbix.bash` | Cleanup and factory reset |
| `fix-zabbix.bash` | Force-clean and redeploy stuck containers |
| `manage-mibs.bash` | MIB library management |
| `test-network-trap.bash` | Send test SNMP traps |
| `helpers/test-agent-connectivity.bash` | Test agent connectivity from Zabbix server |
| `helpers/check-agent-config.bash` | Check agent configuration on monitored host |

### Helper Scripts

The `helpers/` directory contains troubleshooting scripts for diagnosing agent connectivity issues:

**Test Agent Connectivity** (run from Zabbix server):
```bash
./helpers/test-agent-connectivity.bash <hostname_or_ip>
```

**Check Agent Configuration** (run on monitored host):
```bash
scp helpers/check-agent-config.bash root@<hostname>:/tmp/
ssh root@<hostname> '/tmp/check-agent-config.bash'
```

See `helpers/README.md` for detailed documentation and troubleshooting workflows.

---

## 📝 License

See [LICENSE](LICENSE) file for details.

---

## 🤝 Contributing

Contributions are welcome! Please ensure:
- Code follows bash best practices
- Variables are properly quoted
- Scripts include error handling
- Documentation is updated

---

## 📖 Additional Resources

- [Zabbix Documentation](https://www.zabbix.com/documentation)
- [Podman Documentation](https://docs.podman.io/)
- [SNMP Trap Configuration Guide](TRAP-TRIGGER.MD)

---

