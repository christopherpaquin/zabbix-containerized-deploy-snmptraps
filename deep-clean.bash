#!/bin/bash
#
#Run the standard cleanup plus delete local volumes
#
# 2. Wipe the persistent data directories
sudo rm -rf /var/lib/zabbix/postgres/*
sudo rm -rf /var/lib/zabbix/snmptraps/*
