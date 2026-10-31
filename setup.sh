#!/usr/bin/env bash
# Fire TV Setup Kit - Linux / macOS Runner

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
APKS_DIR="$DIR/apks"

echo "=========================================================================="
echo "       🔥 FIRE TV ULTIMATE SETUP KIT (Stremio • SmartTube • TiviMate)"
echo "=========================================================================="
echo ""

# Check for adb
if ! command -v adb &> /dev/null; then
    echo "[!] 'adb' command not found. Please install Android platform-tools:"
    echo "    macOS: brew install android-platform-tools"
    echo "    Linux: sudo apt install adb"
    exit 1
fi

echo "Select Target Fire TV:"
echo "  [1] Downstairs Fire TV Cube (192.168.0.64)"
echo "  [2] Upstairs Toshiba Fire TV (192.168.0.140)"
echo "  [3] Custom IP address"
read -p "Option [1-3]: " CHOICE

case "$CHOICE" in
    1) TARGET="192.168.0.64:5555" ;;
    2) TARGET="192.168.0.140:5555" ;;
    3) read -p "Enter IP: " CUSTOM_IP; TARGET="${CUSTOM_IP}:5555" ;;
    *) TARGET="192.168.0.64:5555" ;;
esac

echo "[*] Connecting to $TARGET..."
adb disconnect >/dev/null 2>&1 || true
adb connect "$TARGET"

echo "[*] Waking screen..."
adb -s "$TARGET" shell input keyevent KEYCODE_WAKEUP

echo "[*] Configuring AdGuard Private DNS (dns.adguard-dns.com)..."
adb -s "$TARGET" shell settings put global private_dns_mode hostname
adb -s "$TARGET" shell settings put global private_dns_specifier dns.adguard-dns.com

echo "[*] Installing APKs..."
for APK in "$APKS_DIR"/*.apk; do
    if [ -f "$APK" ]; then
        echo "    Installing $(basename "$APK")..."
        adb -s "$TARGET" install -r -d "$APK" || true
    fi
done

echo "[*] Granting app permissions..."
adb -s "$TARGET" shell pm grant com.stremio.one android.permission.WRITE_EXTERNAL_STORAGE >/dev/null 2>&1 || true
adb -s "$TARGET" shell pm grant com.stremio.one android.permission.READ_EXTERNAL_STORAGE >/dev/null 2>&1 || true
adb -s "$TARGET" shell pm grant org.smarttube.beta android.permission.RECORD_AUDIO >/dev/null 2>&1 || true
adb -s "$TARGET" shell pm grant ar.tvplayer.tv android.permission.WRITE_EXTERNAL_STORAGE >/dev/null 2>&1 || true

echo ""
echo "=========================================================================="
echo "  🎉 Setup completed successfully on $TARGET!"
echo "=========================================================================="
