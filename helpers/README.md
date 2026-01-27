# Zabbix Troubleshooting Helper Scripts

This directory contains helper scripts for troubleshooting Zabbix agent connectivity and monitoring issues.

## Scripts

### 1. `test-agent-connectivity.bash`

**Purpose:** Tests Zabbix server's ability to connect to and pull data from a remote agent.

**Run from:** Zabbix server (this host)

**Usage:**
```bash
./helpers/test-agent-connectivity.bash <IP_OR_HOSTNAME>
```

**Example:**
```bash
./helpers/test-agent-connectivity.bash columbia.lab
./helpers/test-agent-connectivity.bash 10.1.10.21
```

**What it tests:**
1. Network connectivity (ping)
2. DNS resolution
3. Zabbix agent port accessibility (10050/tcp)
4. Zabbix server container status
5. Agent ping response
6. Common agent items (system info, load, etc.)
7. NUT/UPS monitoring items (if applicable)

**Output:**
- ✓ Green checkmark: Test passed
- ⚠ Yellow warning: Non-critical issue
- ✗ Red X: Test failed

---

### 2. `check-agent-config.bash`

**Purpose:** Checks Zabbix agent configuration and NUT setup on the monitored host.

**Run from:** The monitored host (e.g., columbia.lab)

**Usage:**
```bash
# Copy script to remote host
scp helpers/check-agent-config.bash root@columbia.lab:/tmp/

# SSH to remote host and run
ssh root@columbia.lab
cd /tmp
chmod +x check-agent-config.bash
./check-agent-config.bash
```

**What it checks:**
1. Agent installation (agent2 vs agentd)
2. Agent service status (running/enabled)
3. Agent configuration (Server=, ServerActive=, Hostname=)
4. Firewall configuration (port 10050)
5. NUT installation and configuration
6. Local agent response test
7. NUT item availability

**Output:**
- Configuration parameters
- Service status
- Recommendations for fixes

---

### 3. `fix-nut-monitoring.bash`

**Purpose:** Diagnoses and fixes NUT/UPS monitoring issues on monitored hosts.

**Run from:** The monitored host (e.g., columbia.lab)

**Usage:**
```bash
# Copy script to remote host
scp helpers/fix-nut-monitoring.bash root@<hostname>:/tmp/

# SSH to remote host and run
ssh root@<hostname>
cd /tmp
chmod +x fix-nut-monitoring.bash
./fix-nut-monitoring.bash
```

**What it checks:**
1. NUT installation status
2. NUT services (nut-server, nut-monitor)
3. NUT configuration files
4. UPS device discovery
5. Zabbix agent NUT plugin
6. Plugin configuration files

**What it fixes:**
- Creates missing NUT plugin configuration
- Identifies stopped services
- Shows UPS device status
- Provides step-by-step fix instructions

**Output:**
- Detailed diagnostic results
- Automatic creation of plugin config
- Specific commands to fix issues

---

## Common Troubleshooting Workflow

### Issue: Host not reporting data to Zabbix

**Step 1:** Run connectivity test from Zabbix server
```bash
./helpers/test-agent-connectivity.bash <hostname>
```

**Step 2:** If connection fails, check remote agent configuration
```bash
# Copy and run check script on remote host
scp helpers/check-agent-config.bash root@<hostname>:/tmp/
ssh root@<hostname> '/tmp/check-agent-config.bash'
```

**Step 2b:** If NUT/UPS monitoring specifically is not working
```bash
# Copy and run NUT diagnostic script on remote host
scp helpers/fix-nut-monitoring.bash root@<hostname>:/tmp/
ssh root@<hostname> '/tmp/fix-nut-monitoring.bash'
```

**Step 3:** Fix based on findings

Common fixes:

| Issue | Solution |
|-------|----------|
| Port 10050 closed | `firewall-cmd --add-port=10050/tcp --permanent && firewall-cmd --reload` |
| Server IP not allowed | Add Zabbix server IP to `Server=` in `/etc/zabbix/zabbix_agent2.conf` |
| Agent not running | `systemctl start zabbix-agent2 && systemctl enable zabbix-agent2` |
| NUT not installed | `dnf install nut && configure /etc/ups/` |
| Hostname mismatch | Match hostname in Zabbix UI with agent's `Hostname=` parameter |

**Step 4:** Restart agent and retest
```bash
# On remote host
systemctl restart zabbix-agent2

# From Zabbix server
./helpers/test-agent-connectivity.bash <hostname>
```

---

## Quick Reference

### Fix Agent Connection Refused

On the monitored host, ensure Zabbix server IP is allowed:

```bash
# Get Zabbix server IP (run on Zabbix server)
hostname -I | awk '{print $1}'

# On monitored host, edit agent config
vim /etc/zabbix/zabbix_agent2.conf

# Add/modify this line (replace with actual Zabbix server IP):
Server=127.0.0.1,10.1.10.50

# Restart agent
systemctl restart zabbix-agent2
```

### Enable NUT/UPS Monitoring

On the monitored host:

```bash
# 1. Install NUT
dnf install nut

# 2. Configure your UPS
vim /etc/ups/ups.conf
# Add:
# [myups]
#   driver = usbhid-ups
#   port = auto

# 3. Set NUT mode
echo "MODE=standalone" > /etc/ups/nut.conf

# 4. Start services
systemctl start nut-server nut-monitor
systemctl enable nut-server nut-monitor

# 5. Test
upsc myups@localhost

# 6. Verify Zabbix can query
zabbix_agent2 -t nut.ups.status
```

---

## Tips

- Always test from the Zabbix server first to verify connectivity
- Check agent logs: `journalctl -u zabbix-agent2 -n 50 -f`
- Verify hostname matches: hostname in Zabbix UI must match agent's `Hostname=` parameter
- For NUT, ensure agent has permission to query UPS data
- Test locally before testing remotely: `zabbix_agent2 -t <item_key>`

---

## Support

For issues or questions:
1. Check Zabbix server logs: `podman logs zabbix-server-pgsql | grep <hostname>`
2. Review main troubleshooting script: `../troubleshoot-zabbix.bash`
3. Consult Zabbix documentation: https://www.zabbix.com/documentation/
