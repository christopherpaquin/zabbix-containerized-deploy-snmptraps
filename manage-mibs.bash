#!/bin/bash
# DESCRIPTION: Strategic MIB Manager (v2025.7)
# Supports: Standard, Cisco, Juniper, Dell (iDRAC), and APC (PDU/UPS).

if [ -f "vars.env" ]; then source vars.env; else echo "[ERROR] vars.env missing"; exit 1; fi

CONF_FILE="mibs.conf"
MIB_DIR="$INSTALL_DIR/mibs"
mkdir -p "$MIB_DIR"

echo "======================================================="
echo "          ZABBIX MIB MANAGEMENT UTILITY"
echo "======================================================="
echo "[*] Installation Directory: $MIB_DIR"

# --- 1. System Prerequisite Check ---
for tool in curl unzip; do
    if ! command -v "$tool" &> /dev/null; then
        echo "[*] Missing $tool. Installing..."
        sudo dnf install -y "$tool" &>/dev/null
    fi
done

# --- 2. Processing Loop ---
while IFS='|' read -r vendor url || [ -n "$vendor" ]; do
    vendor=$(echo "$vendor" | tr -d '\r' | xargs)
    url=$(echo "$url" | tr -d '\r' | xargs)

    [[ "$vendor" =~ ^#.*$ || -z "$vendor" ]] && continue

    echo "[*] Validating Vendor: $vendor"
    
    if curl -L --output /dev/null --silent --head --fail "$url"; then
        echo "    -> URL Status: [OK]"
        
        if [[ "$url" == *.zip ]]; then
            echo "    -> Action: Extracting specific MIB folders..."
            curl -sL -o /tmp/mibs.zip "$url"
            
            case "$vendor" in
                "Standard_Core")
                    sudo unzip -o -j /tmp/mibs.zip "*-master/mibs/*" -d "$MIB_DIR" > /dev/null
                    ;;
                "Cisco_Mibs")
                    sudo unzip -o -j /tmp/mibs.zip "*-master/mibs/cisco/*" -d "$MIB_DIR" > /dev/null
                    ;;
                "Juniper_Mibs")
                    sudo unzip -o -j /tmp/mibs.zip "*-master/mibs/juniper/*" -d "$MIB_DIR" > /dev/null
                    ;;
                "Dell_iDRAC")
                    # Pulls Dell-specific MIBs (includes iDRAC and OpenManage)
                    sudo unzip -o -j /tmp/mibs.zip "*-master/mibs/dell/*" -d "$MIB_DIR" > /dev/null
                    ;;
                "APC_PDU")
                    # Pulls APC/American Power Conversion MIBs (PowerNet-MIB)
                    sudo unzip -o -j /tmp/mibs.zip "*-master/mibs/apc/*" -d "$MIB_DIR" > /dev/null
                    ;;
                *)
                    sudo unzip -o -j /tmp/mibs.zip "*" -d "$MIB_DIR" > /dev/null
                    ;;
            esac
            rm /tmp/mibs.zip
        else
            filename=$(basename "$url")
            echo "    -> Action: Downloading single file ($filename)..."
            sudo curl -sL -o "$MIB_DIR/$filename" "$url"
        fi
    else
        echo "    -> URL Status: [FAILED] (Unreachable: $url)"
    fi
done < "$CONF_FILE"

# --- 3. Normalization & Permissions ---
echo "-------------------------------------------------------"
echo "[*] Normalizing file extensions to .mib..."
sudo find "$MIB_DIR" -type f \( -name "*.txt" -o -name "*.my" \) -exec sh -c 'mv "$1" "${1%.*}.mib"' _ {} \;

echo "[*] Setting Podman-compatible permissions..."
sudo chmod -R 755 "$MIB_DIR"
sudo chown -R root:root "$MIB_DIR"

if command -v restorecon &> /dev/null; then
    echo "[*] Applying SELinux container_file_t contexts..."
    sudo restorecon -R "$MIB_DIR"
fi

# --- 4. Summary & Service Reload ---
FILE_COUNT=$(ls -1 "$MIB_DIR" 2>/dev/null | wc -l)
echo "[SUMMARY] MIB Library Status"
echo "    -> Location: $MIB_DIR"
echo "    -> Total Files: $FILE_COUNT"
echo "-------------------------------------------------------"
echo "[*] Restarting Zabbix containers to index new MIBs..."
podman restart zabbix-snmptraps zabbix-server-pgsql > /dev/null

echo "======================================================="
echo "[OK] MIB Update Cycle Complete."
