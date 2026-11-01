#!/usr/bin/env bash
# Fire TV Setup Kit - Linux / macOS Cross-Platform Runner (Production Edition)

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

get_friendly_model() {
    local model="$1"
    local manuf="$2"
    case "$model" in
        "AFTGAZL") echo "Amazon Fire TV Cube (3rd Gen)" ;;
        "AFTR") echo "Amazon Fire TV Cube (2nd Gen)" ;;
        "AFTKM") echo "Amazon Fire TV Cube (1st Gen)" ;;
        "AFTKA") echo "Amazon Fire TV Stick 4K Max (1st Gen)" ;;
        "AFTKRT") echo "Amazon Fire TV Stick 4K Max (2nd Gen)" ;;
        "AFTMM") echo "Amazon Fire TV Stick 4K (1st Gen)" ;;
        "AFTKMST") echo "Amazon Fire TV Stick 4K (2nd Gen)" ;;
        "AFTSSS") echo "Amazon Fire TV Stick Lite" ;;
        "AFTSS") echo "Amazon Fire TV Stick (3rd Gen)" ;;
        "AFTT") echo "Amazon Fire TV Stick (2nd Gen)" ;;
        "AFTOQ") echo "Amazon Fire TV Omni QLED Series" ;;
        "SHIELD Android TV"|"SHIELD Android TV Pro"|"mdarcy") echo "NVIDIA SHIELD TV Pro" ;;
        "sif") echo "NVIDIA SHIELD TV (Tube)" ;;
        "Chromecast"|"GA01919") echo "Chromecast with Google TV (4K)" ;;
        "Google TV Streamer") echo "Google TV Streamer 4K" ;;
        "G454V") echo "Chromecast with Google TV (HD)" ;;
        "240411"|"onn. 4K Pro") echo "Onn 4K Streaming Box" ;;
        *) echo "$manuf $model" ;;
    esac
}

echo "[*] Scanning local network for Smart TVs with ADB (port 5555)..."
FOUND_IPS=()

# Determine local IP / subnet across Linux and macOS
LOCAL_IP=""
if command -v ip >/dev/null 2>&1; then
    LOCAL_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7}' | grep -E '^(192\.168\.|10\.|172\.)' | head -n 1)
    if [ -z "$LOCAL_IP" ]; then
        LOCAL_IP=$(ip -4 addr show 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | grep -E '^(192\.168\.|10\.|172\.)' | head -n 1)
    fi
fi
if [ -z "$LOCAL_IP" ] && command -v ifconfig >/dev/null 2>&1; then
    LOCAL_IP=$(ifconfig 2>/dev/null | awk '/inet / {print $2}' | sed 's/addr://' | grep -E '^(192\.168\.|10\.|172\.)' | head -n 1)
fi

if [ -n "$LOCAL_IP" ]; then
    SUBNET=$(echo "$LOCAL_IP" | cut -d'.' -f1-3)
    echo "    Detected subnet: $SUBNET.1 - $SUBNET.254"
    TMP_SCAN=$(mktemp 2>/dev/null || echo "/tmp/firetv_found_ips.txt")
    (
        for i in $(seq 1 254); do
            (nc -z -w 1 "$SUBNET.$i" 5555 2>/dev/null && echo "$SUBNET.$i") &
        done
        wait
    ) | sort -u > "$TMP_SCAN" 2>/dev/null || true
    
    if [ -f "$TMP_SCAN" ]; then
        while IFS= read -r ip; do
            if [ -n "$ip" ]; then
                FOUND_IPS+=("$ip")
            fi
        done < "$TMP_SCAN"
        rm -f "$TMP_SCAN"
    fi
fi

if [ ${#FOUND_IPS[@]} -gt 0 ]; then
    echo "[+] Found ${#FOUND_IPS[@]} device(s) on your Wi-Fi:"
    INDEX=1
    for ip in "${FOUND_IPS[@]}"; do
        adb connect "$ip:5555" >/dev/null 2>&1 || true
        MODEL=$(adb -s "$ip:5555" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
        MANUF=$(adb -s "$ip:5555" shell getprop ro.product.manufacturer 2>/dev/null | tr -d '\r')
        FRIENDLY=$(get_friendly_model "$MODEL" "$MANUF")
        echo "  [$INDEX] $FRIENDLY [$ip]"
        INDEX=$((INDEX + 1))
    done
    echo "  [M] Enter custom IP address manually"
    read -r -p "Select TV [1-${#FOUND_IPS[@]} or M]: " CHOICE
    
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -le "${#FOUND_IPS[@]}" ]; then
        TARGET="${FOUND_IPS[$((CHOICE-1))]}:5555"
    else
        read -r -p "Enter TV IP Address: " MANUAL_IP
        TARGET="${MANUAL_IP}:5555"
    fi
else
    echo "[!] No ADB devices found automatically on this network."
    read -r -p "Enter Fire TV / Android TV IP: " MANUAL_IP
    TARGET="${MANUAL_IP}:5555"
fi

echo "[*] Connecting to $TARGET..."
adb disconnect >/dev/null 2>&1 || true
adb connect "$TARGET"

echo "[*] Waking screen..."
adb -s "$TARGET" shell input keyevent KEYCODE_WAKEUP

echo ""
echo "Select Private DNS Provider (Zero-VPN):"
echo "  [1] AdGuard Default (dns.adguard-dns.com) - Ad & Tracking blocker"
echo "  [2] AdGuard Family (family.adguard-dns.com) - Ads + Safe Search"
echo "  [3] Cloudflare Security (security.cloudflare-dns.com) - 1.1.1.2 Threat protection"
echo "  [4] Quad9 (dns.quad9.net) - Swiss Privacy & Malware Defense"
read -r -p "Choice [1-4, default 1]: " DNS_CHOICE

DNS_SPEC="dns.adguard-dns.com"
case "$DNS_CHOICE" in
    2) DNS_SPEC="family.adguard-dns.com" ;;
    3) DNS_SPEC="security.cloudflare-dns.com" ;;
    4) DNS_SPEC="dns.quad9.net" ;;
esac

echo "[*] Configuring Private DNS ($DNS_SPEC)..."
adb -s "$TARGET" shell settings put global private_dns_mode hostname
adb -s "$TARGET" shell settings put global private_dns_specifier "$DNS_SPEC"

echo "[*] Installing APK packages from $APKS_DIR..."
if [ -d "$APKS_DIR" ]; then
    for APK in "$APKS_DIR"/*.apk; do
        if [ -f "$APK" ]; then
            echo "    Installing $(basename "$APK")..."
            adb -s "$TARGET" install -r -d "$APK" || true
        fi
    done
fi

echo "[*] Granting runtime permissions..."
adb -s "$TARGET" shell pm grant com.stremio.one android.permission.WRITE_EXTERNAL_STORAGE >/dev/null 2>&1 || true
adb -s "$TARGET" shell pm grant com.stremio.one android.permission.READ_EXTERNAL_STORAGE >/dev/null 2>&1 || true
adb -s "$TARGET" shell pm grant org.smarttube.beta android.permission.RECORD_AUDIO >/dev/null 2>&1 || true
adb -s "$TARGET" shell pm grant ar.tvplayer.tv android.permission.WRITE_EXTERNAL_STORAGE >/dev/null 2>&1 || true

echo ""
echo "Debloat Telemetry & Background Services:"
echo "  [1] Balanced (Default - telemetry, ads, shopping, retail demos)"
echo "  [2] Safe (Minimal - essential telemetry & metrics only)"
echo "  [3] Aggressive (Deep - retail demo, shopping, screensaver, buyer services)"
echo "  [N] Skip debloat"
read -r -p "Select debloat tier [1/2/3/N, default 1]: " DEBLOAT_CONFIRM

if [[ ! "$DEBLOAT_CONFIRM" =~ ^[Nn] ]]; then
    echo "[*] Disabling background telemetry and services..."
    BLOAT=(
        "com.amazon.device.sale.service"
        "com.amazon.whisperjoin.middleware.security"
        "com.amazon.shpm"
        "com.amazon.visualsearch"
        "com.amazon.unifiedsearch"
        "com.amazon.tmm"
        "com.amazon.precog"
    )
    if [ "$DEBLOAT_CONFIRM" != "2" ]; then
        BLOAT+=(
            "com.amazon.firehomedevice"
            "com.amazon.advertising.idprovider"
            "com.amazon.kor.demo"
            "com.amazon.altair.retail"
            "com.amazon.cardinal"
        )
    fi
    if [ "$DEBLOAT_CONFIRM" = "3" ]; then
        BLOAT+=(
            "com.amazon.ftv.screensaver"
            "com.amazon.buysettings"
        )
    fi
    for pkg in "${BLOAT[@]}"; do
        adb -s "$TARGET" shell pm disable-user --user 0 "$pkg" 2>/dev/null || true
    done
    echo "[+] Telemetry debloat completed (${#BLOAT[@]} services disabled)."
fi

echo ""
echo "=========================================================================="
echo "       FIRE TV SYSTEM & HARDWARE DIAGNOSTICS"
echo "=========================================================================="
DISP=$(adb -s "$TARGET" shell wm size 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | head -n 1)
DENS=$(adb -s "$TARGET" shell wm density 2>/dev/null | grep -oE '[0-9]+' | head -n 1)
DATA_PART=$(adb -s "$TARGET" shell df -h /data 2>/dev/null | grep '/data' | awk '{print "Total " $2 ", Used " $3 ", Free " $4 " (" $5 " used)"}')
MEM_INFO=$(adb -s "$TARGET" shell cat /proc/meminfo 2>/dev/null)
MEM_TOT=$(echo "$MEM_INFO" | grep 'MemTotal:' | awk '{printf "%.0f", $2/1024}')
MEM_AVL=$(echo "$MEM_INFO" | grep 'MemAvailable:' | awk '{printf "%.0f", $2/1024}')

[ -n "$DISP" ] && echo "  [+] Display Resolution : $DISP"
[ -n "$DENS" ] && echo "  [+] Screen Density     : $DENS DPI"
[ -n "$DATA_PART" ] && echo "  [+] Data Partition     : $DATA_PART"
if [ -n "$MEM_TOT" ] && [ -n "$MEM_AVL" ] && [ "$MEM_TOT" -gt 0 ]; then
    MEM_USED=$((MEM_TOT - MEM_AVL))
    MEM_PCT=$((MEM_USED * 100 / MEM_TOT))
    echo "  [+] System RAM         : Total ${MEM_TOT}MB, Available ${MEM_AVL}MB (${MEM_PCT}% in use)"
fi

echo ""
echo "=========================================================================="
echo "  [+] Setup completed successfully on $TARGET!"
echo "=========================================================================="
