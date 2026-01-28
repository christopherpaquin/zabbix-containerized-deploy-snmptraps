# Environment Variables Documentation

This document provides a comprehensive reference for all environment variables defined in `vars.env` and their usage across the project scripts.

---

## Overview

The `vars.env` file is the central configuration file for the Zabbix deployment. It must be created from `vars.env.template` before running any deployment scripts.

**Setup:**
```bash
cp vars.env.template vars.env
vim vars.env  # Edit with your values
```

---

## Variables Reference

### 1. `ZABBIX_VERSION`

**Description:** Specifies the Zabbix version to deploy.

**Type:** String (version number)

**Default:** `"7.4.6"`

**Examples:**
- `"7.4.6"` - Latest stable (default)
- `"7.2"` - Previous stable version
- `"7.0"` - Older stable version

**Used By:**
- ✅ `deploy-zabbix.bash` - Constructs Docker image tags for all Zabbix containers
- ✅ `fix-zabbix.bash` - Uses same version when redeploying containers

**Purpose:**
Controls which version of Zabbix container images are pulled from Docker Hub. All Zabbix components (server, web, agent, snmptraps) use this version.

**Docker Images Affected:**
- `zabbix/zabbix-snmptraps:alpine-${ZABBIX_VERSION}`
- `zabbix/zabbix-server-pgsql:alpine-${ZABBIX_VERSION}`
- `zabbix/zabbix-agent2:alpine-${ZABBIX_VERSION}`
- `zabbix/zabbix-web-nginx-pgsql:alpine-${ZABBIX_VERSION}`

---

### 2. `POSTGRES_VERSION`

**Description:** PostgreSQL container image version.

**Type:** String (image tag)

**Default:** `"16-alpine"`

**Examples:**
- `"16-alpine"` - PostgreSQL 16 Alpine Linux (default, lightweight)
- `"15-alpine"` - PostgreSQL 15 Alpine Linux
- `"16"` - PostgreSQL 16 Debian-based (larger image)

**Used By:**
- ✅ `deploy-zabbix.bash` - Specifies PostgreSQL container image
- ✅ `fix-zabbix.bash` - Uses same version when redeploying

**Purpose:**
Controls which PostgreSQL version is used for the Zabbix database. Alpine variants are recommended for smaller image size.

**Docker Image:**
- `postgres:${POSTGRES_VERSION}`

**Notes:**
- Alpine images are ~50% smaller than Debian-based images
- PostgreSQL 16 is recommended for Zabbix 7.x
- Changing this requires database migration or fresh deployment

---

### 3. `POSTGRES_USER`

**Description:** PostgreSQL database username for Zabbix.

**Type:** String

**Default:** `"zabbix"`

**Used By:**
- ✅ `deploy-zabbix.bash` - Creates database user and configures connections
- ✅ `fix-zabbix.bash` - Uses for database connections

**Purpose:**
Defines the PostgreSQL username that owns the Zabbix database and is used by Zabbix server and web interface to connect.

**Environment Variables Set:**
- `POSTGRES_USER=${POSTGRES_USER}` (postgres, server, web containers)

**Notes:**
- Must match across all containers
- Used in health check: `pg_isready -U ${POSTGRES_USER}`
- Changing this requires database recreation

---

### 4. `POSTGRES_DB`

**Description:** PostgreSQL database name for Zabbix.

**Type:** String

**Default:** `"zabbix"`

**Used By:**
- ✅ `deploy-zabbix.bash` - Creates database and configures connections
- ✅ `fix-zabbix.bash` - Uses for database connections

**Purpose:**
Defines the PostgreSQL database name where Zabbix stores all monitoring data, configuration, and historical information.

**Environment Variables Set:**
- `POSTGRES_DB=${POSTGRES_DB}` (postgres, server, web containers)

**Notes:**
- Must match across all containers
- Automatically created by PostgreSQL container on first run
- Contains all Zabbix tables and data
- Changing this requires database recreation

---

### 5. `DB_PASSWORD`

**Description:** PostgreSQL database password for the Zabbix database.

**Type:** String (password)

**Default:** `"change_me_to_something_secure"`

**Security:** 🔒 **CRITICAL - Change this before deployment!**

**Used By:**
- ✅ `deploy-zabbix.bash` - Sets password for PostgreSQL and Zabbix server connection
- ✅ `fix-zabbix.bash` - Uses password when redeploying containers

**Purpose:**
Configures the PostgreSQL database password and ensures Zabbix server and web interface can authenticate to the database.

**Environment Variables Set:**
- `POSTGRES_PASSWORD=${DB_PASSWORD}` (postgres container)
- `POSTGRES_PASSWORD=${DB_PASSWORD}` (zabbix-server container)
- `POSTGRES_PASSWORD=${DB_PASSWORD}` (zabbix-web container)

**Notes:**
- Used by 3 containers: postgres-server, zabbix-server-pgsql, zabbix-web-nginx-pgsql
- Must be strong and unique for production
- Works with `POSTGRES_USER` and `POSTGRES_DB` for complete database configuration

---

### 6. `SNMP_COMMUNITY`

**Description:** SNMP community string for receiving SNMP traps.

**Type:** String

**Default:** `"public"`

**Used By:**
- ✅ `deploy-zabbix.bash` - Configures SNMP trap receiver
- ✅ `fix-zabbix.bash` - Reconfigures SNMP trap receiver
- ✅ `troubleshoot-zabbix.bash` - Validates SNMP trap configuration
- ✅ `test-network-trap.bash` - Sends test SNMP traps with correct community string

**Purpose:**
Defines the SNMP community string that network devices must use when sending SNMP traps to Zabbix. Must match the community string configured on your network devices.

**Environment Variable Set:**
- `ZBX_SNMP_COMMUNITY=${SNMP_COMMUNITY}` (zabbix-snmptraps container)

**Notes:**
- Common values: `"public"`, `"private"`, or custom string
- Must match the community string on devices sending traps
- Used for SNMP v1/v2c (not v3)

---

### 7. `ZBX_AGENT_HOSTNAME`

**Description:** Hostname displayed for the local Zabbix agent running on the server.

**Type:** String

**Default:** `"Zabbix server"`

**Used By:**
- ✅ `deploy-zabbix.bash` - Configures local agent hostname
- ✅ `fix-zabbix.bash` - Reconfigures agent hostname

**Purpose:**
Sets the hostname that appears in the Zabbix web interface for the local monitoring agent. This is the agent that monitors the Zabbix server itself.

**Environment Variable Set:**
- `ZBX_HOSTNAME="${ZBX_AGENT_HOSTNAME}"` (zabbix-agent container)

**Notes:**
- Must match the host configuration in Zabbix web interface
- Default "Zabbix server" is standard convention
- Can be changed to match your naming scheme (e.g., "zabbix.lab")
- This is different from the system hostname

---

### 8. `TEST_SENDER_IP`

**Description:** IP address of the machine used for remote testing.

**Type:** String (IP address)

**Default:** `"10.0.0.x"` (placeholder)

**Used By:**
- ❌ **Currently not used by any scripts**

**Purpose:**
Reserved for future use. Intended to identify the IP address of a remote machine (e.g., your laptop or testing workstation) that will send test SNMP traps or perform remote validation.

**Status:** 📝 Documentation placeholder - no functional impact

---

### 9. `ZABBIX_SERVER_IP`

**Description:** Physical IP address of the Zabbix server host.

**Type:** String (IP address)

**Default:** `"10.0.0.x"` (placeholder)

**Used By:**
- ❌ **Currently not used by any scripts**

**Purpose:**
Reserved for future use. Intended for documentation or scripts that need to reference the Zabbix server's IP address (e.g., for configuring remote agents or firewall rules).

**Status:** 📝 Documentation placeholder - no functional impact

**Note:** The actual Zabbix server IP is automatically detected by scripts using `hostname -I` when needed.

---

### 10. `INSTALL_DIR`

**Description:** Base directory path for all persistent Zabbix data storage.

**Type:** String (absolute path)

**Default:** `"/var/lib/zabbix"`

**Used By:**
- ✅ `deploy-zabbix.bash` - Creates directory structure and mounts volumes
- ✅ `fix-zabbix.bash` - Uses for volume mounts when redeploying
- ✅ `troubleshoot-zabbix.bash` - Validates directory structure and permissions
- ✅ `manage-mibs.bash` - Manages MIB files in subdirectories
- ✅ `cleanup-zabbix.bash` - Removes data during cleanup operations

**Purpose:**
Central location for all persistent data that survives container restarts and system reboots.

**Directory Structure Created:**
```
${INSTALL_DIR}/
├── postgres/          # PostgreSQL database files
├── snmptraps/         # SNMP trap logs
├── mibs/              # Custom MIB files
├── export/            # Data export directory
├── enc/               # Encryption keys
└── extra_cfg/         # Additional configuration files
```

**Volume Mounts:**
- `${INSTALL_DIR}/postgres:/var/lib/postgresql/data` (postgres)
- `${INSTALL_DIR}/snmptraps:/var/lib/zabbix/snmptraps` (snmptraps + server)
- `${INSTALL_DIR}/mibs:/var/lib/zabbix/mibs` (snmptraps + server)
- `${INSTALL_DIR}/extra_cfg/` (server config files)

**Notes:**
- SELinux contexts are automatically configured for this directory
- Must be accessible by the containers
- Changing this requires redeployment

---

### 11. `POD_NAME`

**Description:** Name of the Podman pod that contains all Zabbix containers.

**Type:** String

**Default:** `"zabbix-pod"`

**Used By:**
- ✅ `deploy-zabbix.bash` - Creates the pod and systemd service
- ✅ `fix-zabbix.bash` - References pod for cleanup and recreation
- ✅ `troubleshoot-zabbix.bash` - Checks pod status and container health
- ✅ `check-zabbix-health.bash` - Validates pod and container states
- ✅ `cleanup-zabbix.bash` - Removes pod during cleanup

**Purpose:**
Identifies the Podman pod that groups all Zabbix-related containers together. The pod enables shared networking and coordinated lifecycle management.

**Systemd Service Name:**
- Service file: `/etc/systemd/system/pod-${POD_NAME}.service`
- Example: `pod-zabbix-pod.service`

**Containers in Pod:**
1. `${POD_NAME}-infra` (pod infrastructure)
2. `postgres-server` (database)
3. `zabbix-snmptraps` (trap receiver)
4. `zabbix-server-pgsql` (core engine)
5. `zabbix-agent` (local monitoring)
6. `zabbix-web-nginx-pgsql` (web interface)

**Notes:**
- All containers share the same network namespace via the pod
- Pod must be created before containers
- Changing this requires full redeployment

---

## Variable Dependencies

### Required Variables (Must be set)
- ✅ `ZABBIX_VERSION` - Required for image tags
- ✅ `POSTGRES_VERSION` - Required for PostgreSQL image
- ✅ `POSTGRES_USER` - Required for database user
- ✅ `POSTGRES_DB` - Required for database name
- ✅ `DB_PASSWORD` - Required for database authentication
- ✅ `SNMP_COMMUNITY` - Required for SNMP trap reception
- ✅ `ZBX_AGENT_HOSTNAME` - Required for local agent identification
- ✅ `INSTALL_DIR` - Required for data persistence
- ✅ `POD_NAME` - Required for pod/container naming

### Optional Variables (Reserved for future use)
- ⚠️ `TEST_SENDER_IP` - Not currently used
- ⚠️ `ZABBIX_SERVER_IP` - Not currently used

---

## Script Usage Matrix

| Variable | deploy | fix | troubleshoot | health | cleanup | manage-mibs | test-trap |
|----------|--------|-----|--------------|--------|---------|-------------|-----------|
| `ZABBIX_VERSION` | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `POSTGRES_VERSION` | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `POSTGRES_USER` | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `POSTGRES_DB` | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `DB_PASSWORD` | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `SNMP_COMMUNITY` | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| `ZBX_AGENT_HOSTNAME` | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `TEST_SENDER_IP` | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `ZABBIX_SERVER_IP` | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `INSTALL_DIR` | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ |
| `POD_NAME` | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |

**Legend:**
- ✅ = Variable is used by this script
- ❌ = Variable is not used by this script

---

## Scripts That Source vars.env

The following scripts source the `vars.env` file and require it to exist:

1. **`deploy-zabbix.bash`**
   - Exit on missing: ✅ Yes
   - Variables used: `ZABBIX_VERSION`, `POSTGRES_VERSION`, `POSTGRES_USER`, `POSTGRES_DB`, `DB_PASSWORD`, `SNMP_COMMUNITY`, `ZBX_AGENT_HOSTNAME`, `INSTALL_DIR`, `POD_NAME`

2. **`fix-zabbix.bash`**
   - Exit on missing: ✅ Yes
   - Variables used: `ZABBIX_VERSION`, `POSTGRES_VERSION`, `POSTGRES_USER`, `POSTGRES_DB`, `DB_PASSWORD`, `SNMP_COMMUNITY`, `ZBX_AGENT_HOSTNAME`, `INSTALL_DIR`, `POD_NAME`

3. **`troubleshoot-zabbix.bash`**
   - Exit on missing: ✅ Yes
   - Variables used: `SNMP_COMMUNITY`, `INSTALL_DIR`, `POD_NAME`

4. **`check-zabbix-health.bash`**
   - Exit on missing: ✅ Yes
   - Variables used: `POD_NAME`

5. **`cleanup-zabbix.bash`**
   - Exit on missing: ✅ Yes
   - Variables used: `INSTALL_DIR`, `POD_NAME`

6. **`manage-mibs.bash`**
   - Exit on missing: ✅ Yes
   - Variables used: `INSTALL_DIR`

7. **`test-network-trap.bash`**
   - Exit on missing: ✅ Yes
   - Variables used: `SNMP_COMMUNITY`

---

## Helper Scripts

The helper scripts in `helpers/` directory **do not** source `vars.env`:
- ❌ `test-agent-connectivity.bash` - Standalone, no vars.env needed
- ❌ `check-agent-config.bash` - Run on remote hosts, no vars.env needed
- ❌ `fix-nut-monitoring.bash` - Run on remote hosts, no vars.env needed

---

## Configuration Examples

### Minimal Production Configuration
```bash
ZABBIX_VERSION="7.4.6"
POSTGRES_VERSION="16-alpine"
POSTGRES_USER="zabbix"
POSTGRES_DB="zabbix"
DB_PASSWORD="MySecureP@ssw0rd123!"
SNMP_COMMUNITY="private"
ZBX_AGENT_HOSTNAME="Zabbix server"
INSTALL_DIR="/var/lib/zabbix"
POD_NAME="zabbix-pod"
```

### Development/Testing Configuration
```bash
ZABBIX_VERSION="7.4.6"
POSTGRES_VERSION="16-alpine"
POSTGRES_USER="zabbix"
POSTGRES_DB="zabbix"
DB_PASSWORD="dev_password_123"
SNMP_COMMUNITY="public"
ZBX_AGENT_HOSTNAME="Zabbix server"
INSTALL_DIR="/var/lib/zabbix"
POD_NAME="zabbix-pod"
```

### Multi-Version Setup (Advanced)
```bash
# For testing different versions, change POD_NAME and INSTALL_DIR
ZABBIX_VERSION="7.2"
POSTGRES_VERSION="15-alpine"
POSTGRES_USER="zabbix"
POSTGRES_DB="zabbix"
DB_PASSWORD="test_password"
SNMP_COMMUNITY="public"
ZBX_AGENT_HOSTNAME="Zabbix server 7.2"
INSTALL_DIR="/var/lib/zabbix-7.2"
POD_NAME="zabbix-pod-7.2"
```

### Custom Database Configuration
```bash
# Using custom database names and non-Alpine PostgreSQL
ZABBIX_VERSION="7.4.6"
POSTGRES_VERSION="16"  # Debian-based instead of Alpine
POSTGRES_USER="zbx_admin"
POSTGRES_DB="monitoring_db"
DB_PASSWORD="ComplexP@ssw0rd!2024"
SNMP_COMMUNITY="private_community_123"
ZBX_AGENT_HOSTNAME="prod-zabbix-01"
INSTALL_DIR="/var/lib/zabbix"
POD_NAME="zabbix-pod"
```

---

## Security Considerations

### Sensitive Variables
1. **`DB_PASSWORD`** 🔒
   - Change immediately after copying template
   - Use strong passwords (16+ characters, mixed case, numbers, symbols)
   - Never commit actual `vars.env` to version control
   - Only `vars.env.template` should be in git

2. **`POSTGRES_USER`** 🔐
   - While not a password, consider using non-default username
   - Default "zabbix" is well-known and predictable
   - Custom username adds extra security layer

3. **`SNMP_COMMUNITY`** 🔐
   - Default `"public"` is insecure for production
   - Use unique community string per deployment
   - Consider SNMP v3 for enhanced security

### File Permissions
```bash
# Secure the vars.env file
chmod 600 vars.env
chown root:root vars.env
```

### Version Control
The `.gitignore` file should contain:
```
vars.env
```

Only `vars.env.template` should be tracked in git.

---

## Troubleshooting

### Missing vars.env
```
[ERROR] vars.env not found!
```

**Solution:**
```bash
cp vars.env.template vars.env
vim vars.env  # Edit values
```

### Incorrect Variable Values

**Symptom:** Container fails to start or connects to wrong resources

**Check:**
```bash
# Validate vars.env is sourced correctly
source vars.env
echo $ZABBIX_VERSION
echo $DB_PASSWORD
echo $INSTALL_DIR
```

### Variables Not Taking Effect

**Solution:** Redeploy after changing vars.env
```bash
./cleanup-zabbix.bash
./deploy-zabbix.bash
```

---

## Future Variables (Planned)

These variables are defined but not yet implemented:

### `TEST_SENDER_IP`
**Potential uses:**
- Automatic firewall rule creation for test sender
- Validation of trap sender in troubleshooting scripts
- Network connectivity tests from specific source

### `ZABBIX_SERVER_IP`
**Potential uses:**
- Automatic agent configuration for remote hosts
- Firewall rule suggestions
- Documentation generation with actual IPs

---

## Related Documentation

- **Main README**: [README.md](README.md) - Deployment guide
- **Template File**: [vars.env.template](vars.env.template) - Variable template
- **Cleanup Guide**: [cleanup-zabbix.bash](cleanup-zabbix.bash) - Reset to defaults
- **Troubleshooting**: [troubleshoot-zabbix.bash](troubleshoot-zabbix.bash) - Diagnostic tool

---

## Change Log

| Date | Change | Reason |
|------|--------|--------|
| 2026-01-25 | Added `ZABBIX_VERSION` variable | Make version configurable |
| 2026-01-25 | Changed default to 7.4.6 | Updated to latest stable |
| 2026-01-27 | Created this documentation | User request for variable reference |
| 2026-01-27 | Moved database config to vars.env | Removed hardcoded PostgreSQL settings |
| 2026-01-27 | Added `POSTGRES_VERSION`, `POSTGRES_USER`, `POSTGRES_DB`, `ZBX_AGENT_HOSTNAME` | Better configurability and maintainability |
| 2026-01-27 | Removed version defaults from scripts | All versions now sourced from vars.env only |

---

**Last Updated:** 2026-01-27  
**Version:** 1.0
