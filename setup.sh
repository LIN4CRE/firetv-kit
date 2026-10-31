#!/usr/bin/env bash
# Fire TV Setup Kit - Linux / macOS Cross-Platform Runner

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
APKS_DIR="$DIR/apks"

echo "=========================================================================="
echo "       FIRE TV ULTIMATE SETUP KIT - MULTI-DEVICE INSTALLER"
echo "         Auto Network Discovery * App Checklist * Zero-Middleman"
echo "=========================================================================="
echo ""

# Check for adb
if ! command -v adb &> /dev/null; then
    echo "[!] 'adb' command not found. Please install Android platform-tools:"
    echo "    macOS: brew install android-platform-tools"
    echo "    Linux: sudo apt install adb"
    exit 1
fi

echo "[*] Scanning local network for Smart TVs with ADB (port 5555)..."
FOUND_IPS=()

# Determine local IP / subnet
LOCAL_IP=$(ifconfig 2>/dev/null | grep -E 'inet (192\.168\.|10\.|172\.)' | awk '{print $2}' | head -n 1 || ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -E '^(192\.168\.|10\.|172\.)' | head -n 1)

if [ -n "$LOCAL_IP" ]; then
    SUBNET=$(echo "$LOCAL_IP" | cut -d'.' -f1-3)
    echo "    Detected subnet: $SUBNET.1 - $SUBNET.254"
    for i in $(seq 1 254); do
        (nc -z -w 1 "$SUBNET.$i" 5555 2>/dev/null && echo "$SUBNET.$i") &
    done | sort -u > /tmp/firetv_found_ips.txt 2>/dev/null || true
    wait
    
    if [ -f /tmp/firetv_found_ips.txt ]; then
        while IFS= read -r ip; do
            if [ -n "$ip" ]; then
                FOUND_IPS+=("$ip")
            fi
        done < /tmp/firetv_found_ips.txt
        rm -f /tmp/firetv_found_ips.txt
    fi
fi

if [ ${#FOUND_IPS[@]} -gt 0 ]; then
    echo "[+] Found ${#FOUND_IPS[@]} device(s) on your Wi-Fi:"
    INDEX=1
    for ip in "${FOUND_IPS[@]}"; do
        adb connect "$ip:5555" >/dev/null 2>&1 || true
        MODEL=$(adb -s "$ip:5555" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
        MANUF=$(adb -s "$ip:5555" shell getprop ro.product.manufacturer 2>/dev/null | tr -d '\r')
        echo "  [$INDEX] $MANUF $MODEL [$ip]"
        INDEX=$((INDEX + 1))
    done
    echo "  [M] Enter custom IP address manually"
    read -p "Select TV [1-${#FOUND_IPS[@]} or M]: " CHOICE
    
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -le "${#FOUND_IPS[@]}" ]; then
        TARGET="${FOUND_IPS[$((CHOICE-1))]}:5555"
    else
        read -p "Enter TV IP Address: " MANUAL_IP
        TARGET="${MANUAL_IP}:5555"
    fi
else
    echo "[!] No ADB devices found automatically on this network."
    read -p "Enter Fire TV / Android TV IP: " MANUAL_IP
    TARGET="${MANUAL_IP}:5555"
fi

echo "[*] Connecting to $TARGET..."
adb disconnect >/dev/null 2>&1 || true
adb connect "$TARGET"

echo "[*] Waking screen..."
adb -s "$TARGET" shell input keyevent KEYCODE_WAKEUP

echo "[*] Configuring AdGuard Private DNS (dns.adguard-dns.com)..."
adb -s "$TARGET" shell settings put global private_dns_mode hostname
adb -s "$TARGET" shell settings put global private_dns_specifier dns.adguard-dns.com

echo "[*] Installing APKs from $APKS_DIR..."
for APK in "$APKS_DIR"/*.apk; do
    if [ -f "$APK" ]; then
        echo "    Installing $(basename "$APK")..."
        adb -s "$TARGET" install -r -d "$APK" || true
    fi
done

echo "[*] Granting runtime permissions..."
adb -s "$TARGET" shell pm grant com.stremio.one android.permission.WRITE_EXTERNAL_STORAGE >/dev/null 2>&1 || true
adb -s "$TARGET" shell pm grant com.stremio.one android.permission.READ_EXTERNAL_STORAGE >/dev/null 2>&1 || true
adb -s "$TARGET" shell pm grant org.smarttube.beta android.permission.RECORD_AUDIO >/dev/null 2>&1 || true
adb -s "$TARGET" shell pm grant ar.tvplayer.tv android.permission.WRITE_EXTERNAL_STORAGE >/dev/null 2>&1 || true

echo ""
echo "=========================================================================="
echo "  [+] Setup completed successfully on $TARGET!"
echo "=========================================================================="
