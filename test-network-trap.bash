#!/bin/bash
# DESCRIPTION: Sends a test trap using community string from vars.env

if [ -f "vars.env" ]; then
    source vars.env
else
    echo "[ERROR] vars.env missing."
    exit 1
fi

MESSAGE="${1:-LAB_ENV_VALIDATION_TEST}"
TRAP_OID="1.3.6.1.4.1.9.9.41.1.2.3.1.2.1"

echo "[*] Sending trap to Localhost:162 using community: ${SNMP_COMMUNITY}"

snmptrap -v 2c -c "$SNMP_COMMUNITY" 127.0.0.1:162 "" "$TRAP_OID" "$TRAP_OID" s "$MESSAGE"

[ $? -eq 0 ] && echo "[OK] Trap sent." || echo "[FAIL] Check net-snmp-utils."
