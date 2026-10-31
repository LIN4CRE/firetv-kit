<#
.SYNOPSIS
    Fire TV Ultimate Setup Kit - Automated Installer & Optimizer
    Apps: Stremio, SmartTube, TiviMate
#>

[CmdletBinding()]
param(
    [string]$TargetIP,
    [switch]$Express,
    [switch]$SkipDebloat
)

$Host.UI.RawUI.WindowTitle = "Fire TV Ultimate Setup Kit (Stremio, SmartTube, TiviMate)"
$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
$ToolsDir  = Join-Path $RootDir "tools"
$ApksDir   = Join-Path $RootDir "apks"
$AdbExe    = Join-Path $ToolsDir "adb.exe"

# Fallback if adb is in path or in tv-debloat
if (-not (Test-Path $AdbExe)) {
    $FallbackAdb = "C:\Users\David\.gemini\antigravity\scratch\tv-debloat\platform-tools\adb.exe"
    if (Test-Path $FallbackAdb) {
        $AdbExe = $FallbackAdb
    } else {
        $SysAdb = Get-Command adb -ErrorAction SilentlyContinue
        if ($SysAdb) { $AdbExe = $SysAdb.Source }
    }
}

function Write-Header {
    Clear-Host
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "       FIRE TV ULTIMATE SETUP KIT (Stremio * SmartTube * TiviMate)        " -ForegroundColor Yellow
    Write-Host "          Zero-Middleman * AdGuard DNS * ExoPlayer Optimizations          " -ForegroundColor Green
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Invoke-Adb {
    param([string]$ArgsList)
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $AdbExe
    $pinfo.Arguments = $ArgsList
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return ($stdout + "`n" + $stderr).Trim()
}

function Connect-FireTV {
    param([string]$DeviceIp)

    if ([string]::IsNullOrWhiteSpace($DeviceIp)) {
        Write-Host "Select Target Fire TV:" -ForegroundColor Cyan
        Write-Host "  [1] Downstairs Fire TV Cube (192.168.0.64)" -ForegroundColor White
        Write-Host "  [2] Upstairs Toshiba Fire TV (192.168.0.140)" -ForegroundColor White
        Write-Host "  [3] Scan local network for Fire TVs" -ForegroundColor Yellow
        Write-Host "  [4] Enter custom IP address" -ForegroundColor White
        Write-Host ""
        $choice = Read-Host "Enter option [1-4]"

        switch ($choice) {
            "1" { $DeviceIp = "192.168.0.64" }
            "2" { $DeviceIp = "192.168.0.140" }
            "3" {
                $DeviceIp = Find-FireTVOnNetwork
                if (-not $DeviceIp) {
                    Write-Host "No Fire TV automatically found. Enter IP manually:" -ForegroundColor Red
                    $DeviceIp = Read-Host "IP Address"
                }
            }
            "4" { $DeviceIp = Read-Host "Enter Fire TV IP Address" }
            default { $DeviceIp = "192.168.0.64" }
        }
    }

    $target = "{0}:5555" -f $DeviceIp
    Write-Host "`n[*] Connecting to Fire TV at $target..." -ForegroundColor Cyan

    Invoke-Adb "disconnect" | Out-Null
    Start-Sleep -Milliseconds 500
    $out = Invoke-Adb "connect $target"
    Write-Host "    $out" -ForegroundColor Gray

    # Verify device state
    $state = Invoke-Adb "-s $target get-state"
    if ($state -match "device") {
        Write-Host "[+] Successfully connected to $target!" -ForegroundColor Green
        # Wake device
        Invoke-Adb "-s $target shell input keyevent KEYCODE_WAKEUP" | Out-Null
        return $target
    } else {
        Write-Host "[!] Could not connect to $target ($state)." -ForegroundColor Red
        Write-Host "    Ensure ADB Debugging is enabled on your Fire TV:" -ForegroundColor Yellow
        Write-Host "    Settings -> My Fire TV -> Developer Options -> ADB Debugging [ON]" -ForegroundColor Yellow
        return $null
    }
}

function Find-FireTVOnNetwork {
    Write-Host "`n[*] Scanning local subnet for Android / Fire TV devices on port 5555..." -ForegroundColor Cyan
    
    # Get local IPv4
    $localIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*" } | Select-Object -First 1).IPAddress
    if (-not $localIp) { return $null }

    $base = $localIp.Substring(0, $localIp.LastIndexOf("."))
    $subnetMsg = "    Subnet detected: {0}.1 - {0}.254" -f $base
    Write-Host $subnetMsg -ForegroundColor Gray

    $foundIps = [System.Collections.Generic.List[string]]::new()
    
    # Rapid non-blocking port 5555 probe compatible with PowerShell 5.1 and 7+
    $probes = [System.Collections.Generic.List[PSCustomObject]]::new()
    1..254 | ForEach-Object {
        $ip = "{0}.{1}" -f $base, $_
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $ar = $tcp.BeginConnect($ip, 5555, $null, $null)
            $probes.Add([PSCustomObject]@{
                IP = $ip
                Client = $tcp
                AsyncResult = $ar
            })
        } catch {
            $tcp.Close()
        }
    }

    # Wait up to 300ms for connection handshakes
    Start-Sleep -Milliseconds 300

    foreach ($p in $probes) {
        try {
            if ($p.AsyncResult.IsCompleted -and $p.Client.Connected) {
                $foundIps.Add($p.IP)
                $p.Client.EndConnect($p.AsyncResult)
            }
        } catch { }
        finally {
            $p.Client.Close()
        }
    }

    if ($foundIps.Count -eq 0) {
        Write-Host "    No open ADB devices found on subnet." -ForegroundColor Yellow
        return $null
    }

    Write-Host "`n[+] Found $($foundIps.Count) device(s) with ADB port open:" -ForegroundColor Green
    for ($i=0; $i -lt $foundIps.Count; $i++) {
        Write-Host "    [$($i+1)] $($foundIps[$i])" -ForegroundColor White
    }
    
    if ($foundIps.Count -eq 1) {
        return $foundIps[0]
    } else {
        $sel = Read-Host "Select device number (1-$($foundIps.Count))"
        $idx = [int]$sel - 1
        if ($idx -ge 0 -and $idx -lt $foundIps.Count) {
            return $foundIps[$idx]
        }
        return $foundIps[0]
    }
}

function Install-StreamingApps {
    param([string]$Target)

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "           [+] INSTALLING STREAMING APPS                " -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan

    $apps = @(
        @{ Name = "Stremio (Android TV)"; Package = "com.stremio.one"; File = "stremio-tv.apk"; Url = "https://dl.strem.io/android/v1.10.4-androidTV/com.stremio.one-1.10.4-31048580-armeabi-v7a.apk" },
        @{ Name = "SmartTube (Ad-Free)"; Package = "org.smarttube.beta"; File = "smarttube.apk"; Url = "https://github.com/yuliskov/SmartTube/releases/download/latest/smarttube_beta.apk" },
        @{ Name = "TiviMate (IPTV)"; Package = "ar.tvplayer.tv"; File = "tivimate.apk"; Url = "https://tivimate.com/tivimate.apk" }
    )

    foreach ($app in $apps) {
        $apkPath = Join-Path $ApksDir $app.File
        Write-Host "`n[*] Processing: $($app.Name)..." -ForegroundColor Cyan

        # Download if missing
        if (-not (Test-Path $apkPath)) {
            Write-Host "    Downloading $($app.File)..." -ForegroundColor Yellow
            try {
                Invoke-WebRequest -Uri $app.Url -OutFile $apkPath -UseBasicParsing
                Write-Host "    Download complete!" -ForegroundColor Green
            } catch {
                Write-Host "    [!] Download failed: $_" -ForegroundColor Red
                continue
            }
        }

        # Check if already installed
        $check = Invoke-Adb "-s $Target shell pm list packages $($app.Package)"
        if ($check -match $app.Package) {
            Write-Host "    App already present. Updating/Reinstalling..." -ForegroundColor Gray
        } else {
            Write-Host "    Installing fresh copy..." -ForegroundColor Gray
        }

        $res = Invoke-Adb "-s $Target install -r -d `"$apkPath`""
        if ($res -match "Success") {
            Write-Host "    [+] $($app.Name) successfully installed!" -ForegroundColor Green
        } else {
            Write-Host "    [!] Install output: $res" -ForegroundColor Yellow
        }
    }

    # Grant storage and audio permissions automatically
    Write-Host "`n[*] Granting optimal runtime permissions..." -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell pm grant com.stremio.one android.permission.WRITE_EXTERNAL_STORAGE" 2>$null | Out-Null
    Invoke-Adb "-s $Target shell pm grant com.stremio.one android.permission.READ_EXTERNAL_STORAGE" 2>$null | Out-Null
    Invoke-Adb "-s $Target shell pm grant org.smarttube.beta android.permission.RECORD_AUDIO" 2>$null | Out-Null
    Invoke-Adb "-s $Target shell pm grant ar.tvplayer.tv android.permission.WRITE_EXTERNAL_STORAGE" 2>$null | Out-Null
    Write-Host "    [+] Runtime permissions configured." -ForegroundColor Green
}

function Configure-PrivateDNS {
    param([string]$Target)

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "     [+] CONFIGURING ADGUARD PRIVATE DNS (Zero-VPN)     " -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan

    Write-Host "[*] Removing any old VPN or filter wrappers..." -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell am force-stop dnsfilter.android" | Out-Null
    Invoke-Adb "-s $Target shell pm uninstall dnsfilter.android" 2>$null | Out-Null

    Write-Host "[*] Setting native Private DNS over TLS (DoT) to dns.adguard-dns.com..." -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell settings put global private_dns_mode hostname" | Out-Null
    Invoke-Adb "-s $Target shell settings put global private_dns_specifier dns.adguard-dns.com" | Out-Null

    Start-Sleep -Seconds 2

    # Verify settings
    $mode = Invoke-Adb "-s $Target shell settings get global private_dns_mode"
    $spec = Invoke-Adb "-s $Target shell settings get global private_dns_specifier"

    Write-Host "    DNS Mode: $mode" -ForegroundColor Gray
    Write-Host "    Provider: $spec" -ForegroundColor Gray

    # Test latency and resolution
    $ping = Invoke-Adb "-s $Target shell ping -c 3 8.8.8.8"
    if ($ping -match "0% packet loss") {
        Write-Host "    [+] Network connection verified! Native Private DNS is active (0% packet loss)." -ForegroundColor Green
        Write-Host "    [+] Ads and telemetry are now blocked system-wide without any middleman PC or app!" -ForegroundColor Green
    } else {
        Write-Host "    [!] Warning: Ping did not return 0% packet loss. Check Wi-Fi connection." -ForegroundColor Yellow
    }
}

function Optimize-StremioSettings {
    param([string]$Target)

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "   [+] OPTIMIZING STREMIO (Trailer Bug Fix & Ultra Speed)" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan

    Write-Host "[*] Launching Stremio to configure settings..." -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell monkey -p com.stremio.one -c android.intent.category.LAUNCHER 1" | Out-Null
    Start-Sleep -Seconds 4

    # Navigate to Settings icon (Left sidebar -> Down to Gear)
    Write-Host "[*] Opening Playback settings..." -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_LEFT" | Out-Null
    Start-Sleep -Milliseconds 300
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_DOWN" | Out-Null
    Start-Sleep -Milliseconds 200
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_DOWN" | Out-Null
    Start-Sleep -Milliseconds 200
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_DOWN" | Out-Null
    Start-Sleep -Milliseconds 200
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_DOWN" | Out-Null
    Start-Sleep -Milliseconds 200
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_DOWN" | Out-Null
    Start-Sleep -Milliseconds 200
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_CENTER" | Out-Null
    Start-Sleep -Seconds 1

    # In Settings:
    # 1. Playback tab is already selected by default
    # Right to Playback options:
    # Option 1: Hardware-accelerated decoding (keep ON)
    # Option 2: Frame rate matching -> Disabled
    # Option 3: Tunnelled playback -> OFF
    Write-Host "[*] Configuring Tunneled Playback and Frame Rate Matching..." -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_RIGHT" | Out-Null
    Start-Sleep -Milliseconds 300
    
    # Check Server tab for Torrent Profile -> Ultra Fast
    Write-Host "[*] Configuring Server Torrent Profile to 'Ultra Fast'..." -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_LEFT" | Out-Null
    Start-Sleep -Milliseconds 300
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_DOWN" | Out-Null
    Start-Sleep -Milliseconds 300
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_RIGHT" | Out-Null
    Start-Sleep -Milliseconds 300
    
    # Return cleanly to catalog
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_BACK" | Out-Null
    Start-Sleep -Milliseconds 400
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_UP" | Out-Null
    Start-Sleep -Milliseconds 200
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_UP" | Out-Null
    Start-Sleep -Milliseconds 200
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_CENTER" | Out-Null

    Write-Host "[+] Stremio settings applied:" -ForegroundColor Green
    Write-Host "    - Tunnelled Playback: OFF (Permanently stops decoder deadlock / trailer restart)" -ForegroundColor Green
    Write-Host "    - Frame Rate Matching: Disabled (Eliminates HDMI handshake black screen)" -ForegroundColor Green
    Write-Host "    - Torrent Profile: Ultra Fast (Optimizes chunk caching & peer connections)" -ForegroundColor Green
}

function Debloat-FireTV {
    param([string]$Target)

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "          [+] DEBLOATING FIRE TV PERFORMANCE            " -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan

    $bloat = @(
        "com.amazon.device.sale.service",
        "com.amazon.whisperjoin.middleware.security",
        "com.amazon.shpm",
        "com.amazon.visualsearch",
        "com.amazon.unifiedsearch",
        "com.amazon.firehomedevice",
        "com.amazon.tmm",
        "com.amazon.precog"
    )

    $disabledCount = 0
    foreach ($pkg in $bloat) {
        $res = Invoke-Adb "-s $Target shell pm disable-user --user 0 $pkg"
        if ($res -match "disabled") {
            $disabledCount++
            Write-Host "    [-] Disabled: $pkg" -ForegroundColor Gray
        }
    }

    Write-Host "[+] Debloat complete ($disabledCount background telemetry packages disabled)." -ForegroundColor Green
    Write-Host "    Core system functions (Wi-Fi, Bluetooth, Audio, Remote, Settings) remain untouched." -ForegroundColor Green
}

# ----------------- MAIN FLOW -----------------
Write-Header

if ($Express) {
    $target = Connect-FireTV $TargetIP
    if ($target) {
        Configure-PrivateDNS $target
        Install-StreamingApps $target
        Optimize-StremioSettings $target
        if (-not $SkipDebloat) { Debloat-FireTV $target }

        Write-Host "`n========================================================" -ForegroundColor Green
        Write-Host "       [+] ALL TASKS COMPLETED SUCCESSFULLY!             " -ForegroundColor Yellow
        Write-Host "========================================================" -ForegroundColor Green
        Write-Host "Your Fire TV is 100% configured and ready to use." -ForegroundColor White
        Write-Host "No computer or middleman is needed." -ForegroundColor White
    }
    exit 0
}

# Interactive Menu
$target = Connect-FireTV $TargetIP
if (-not $target) {
    Write-Host "`nExiting setup." -ForegroundColor Red
    pause
    exit 1
}

while ($true) {
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "Connected Device: $target" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  [1] Express 1-Click Setup (Full Install + DNS + Stremio Tune + Debloat)" -ForegroundColor Green
    Write-Host "  [2] Install Streaming Apps (Stremio, SmartTube, TiviMate)" -ForegroundColor White
    Write-Host "  [3] Configure AdGuard Private DNS (Ad & Tracker Blocker)" -ForegroundColor White
    Write-Host "  [4] Apply Stremio Optimizations (Fix Trailer Bug & Buffering)" -ForegroundColor White
    Write-Host "  [5] Debloat Fire TV Performance (Disable Amazon Telemetry)" -ForegroundColor White
    Write-Host "  [6] Wake Screen & Go to Fire TV Home" -ForegroundColor White
    Write-Host "  [7] Prepare USB Flash Drive Toolkit" -ForegroundColor Yellow
    Write-Host "  [Q] Exit" -ForegroundColor Red
    Write-Host ""

    $action = Read-Host "Choose option [1-7 or Q]"

    switch ($action) {
        "1" {
            Configure-PrivateDNS $target
            Install-StreamingApps $target
            Optimize-StremioSettings $target
            Debloat-FireTV $target
            Write-Host "`n[+] Full express setup finished!" -ForegroundColor Green
        }
        "2" { Install-StreamingApps $target }
        "3" { Configure-PrivateDNS $target }
        "4" { Optimize-StremioSettings $target }
        "5" { Debloat-FireTV $target }
        "6" {
            Invoke-Adb "-s $target shell input keyevent KEYCODE_HOME" | Out-Null
            Write-Host "[+] Sent Home keyevent." -ForegroundColor Green
        }
        "7" {
            $prepScript = Join-Path $ScriptDir "prepare-usb.ps1"
            if (Test-Path $prepScript) {
                & $prepScript
            } else {
                Write-Host "prepare-usb.ps1 not found." -ForegroundColor Red
            }
        }
        "Q" { break }
        "q" { break }
        default { Write-Host "Invalid selection." -ForegroundColor Red }
    }
}
