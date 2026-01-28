#!/bin/bash
# DESCRIPTION: Sends a test trap using community string from vars.env

if [ -f "vars.env" ]; then
    source vars.env
else
    echo "[ERROR] vars.env missing."
    exit 1
fi

MESSAGE="${1:-LAB_ENV_VALIDATION_TEST}"

echo "[*] Sending trap to ${TRAP_TEST_TARGET}:${PORT_SNMP_TRAP} using community: ${SNMP_COMMUNITY}"

snmptrap -v 2c -c "$SNMP_COMMUNITY" ${TRAP_TEST_TARGET}:${PORT_SNMP_TRAP} "" "$TRAP_TEST_OID" "$TRAP_TEST_OID" s "$MESSAGE"

[ $? -eq 0 ] && echo "[OK] Trap sent." || echo "[FAIL] Check net-snmp-utils."
