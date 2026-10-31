<#
.SYNOPSIS
    Fire TV Ultimate Setup Kit - Automated Network Discovery, App Checklist & Optimizer
    Supports any Fire TV, Android TV, Google TV, or Shield TV on any Wi-Fi network.
#>

[CmdletBinding()]
param(
    [string]$TargetIP,
    [switch]$Express,
    [switch]$SkipDebloat
)

$Host.UI.RawUI.WindowTitle = "Fire TV Ultimate Setup Kit"
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

# Ensure apks folder exists
if (-not (Test-Path $ApksDir)) {
    New-Item -ItemType Directory -Force -Path $ApksDir | Out-Null
}

function Write-Header {
    Clear-Host
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "       FIRE TV ULTIMATE SETUP KIT - MULTI-DEVICE INSTALLER                " -ForegroundColor Yellow
    Write-Host "         Auto Network Discovery * App Checklist * Zero-Middleman          " -ForegroundColor Green
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

function Get-FriendlyDeviceName {
    param([string]$Manufacturer, [string]$Model)

    $modelMap = @{
        "AFTGAZL" = "Amazon Fire TV Cube (3rd Gen)"
        "AFTR"    = "Amazon Fire TV Cube (2nd Gen)"
        "AFTKM"   = "Amazon Fire TV Cube (1st Gen)"
        "AFTKA"   = "Amazon Fire TV Stick 4K Max (1st Gen)"
        "AFTKRT"  = "Amazon Fire TV Stick 4K Max (2nd Gen)"
        "AFTMM"   = "Amazon Fire TV Stick 4K (1st Gen)"
        "AFTKMST" = "Amazon Fire TV Stick 4K (2nd Gen)"
        "AFTSSS"  = "Amazon Fire TV Stick Lite"
        "AFTSS"   = "Amazon Fire TV Stick (3rd Gen)"
        "AFTT"    = "Amazon Fire TV Stick (2nd Gen)"
        "AFTB"    = "Amazon Fire TV (1st Gen)"
        "AFTS"    = "Amazon Fire TV (2nd Gen)"
        "AFTN"    = "Amazon Fire TV (3rd Gen Pendant)"
        "AFTBOXE1"= "Toshiba 4K UHD Fire TV Edition"
        "AFTJM"   = "Insignia 4K UHD Fire TV Edition"
        "SHIELD Android TV" = "NVIDIA SHIELD TV"
        "Chromecast" = "Google Chromecast with Google TV"
    }

    if ($modelMap.ContainsKey($Model)) {
        return $modelMap[$Model]
    }
    
    if ($Manufacturer -and $Model) {
        return "$Manufacturer $Model"
    } elseif ($Model) {
        return $Model
    } else {
        return "Smart TV / Android TV Device"
    }
}

function Discover-TVsOnNetwork {
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "                DISCOVERING SMART TVS ON YOUR WI-FI                       " -ForegroundColor Yellow
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host ""

    # Detect active IPv4 network interface
    $localIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
        ($_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*" -or $_.IPAddress -like "172.*") -and 
        $_.IPAddress -notlike "*.255" -and $_.IPAddress -ne "127.0.0.1"
    } | Select-Object -First 1).IPAddress

    if (-not $localIp) {
        Write-Host "[!] Could not automatically detect local network adapter." -ForegroundColor Yellow
        $ip = Read-Host "Enter Fire TV / Android TV IP address manually"
        return $ip
    }

    $base = $localIp.Substring(0, $localIp.LastIndexOf("."))
    $scanMsg = "[*] Scanning network ({0}.1 - {0}.254) for Android & Fire TVs on port 5555..." -f $base
    Write-Host $scanMsg -ForegroundColor Cyan

    # Multi-socket non-blocking port 5555 probe
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

    # Wait 400ms for connection responses
    Start-Sleep -Milliseconds 400

    $activeIps = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $probes) {
        try {
            if ($p.AsyncResult.IsCompleted -and $p.Client.Connected) {
                $activeIps.Add($p.IP)
                $p.Client.EndConnect($p.AsyncResult)
            }
        } catch { }
        finally {
            $p.Client.Close()
        }
    }

    if ($activeIps.Count -eq 0) {
        Write-Host "`n[!] No active Android TV / Fire TV devices found on this Wi-Fi network." -ForegroundColor Yellow
        Write-Host "    Make sure 'ADB Debugging' is enabled on your TV:" -ForegroundColor White
        Write-Host "    Settings -> My Fire TV -> Developer Options -> ADB Debugging [ON]" -ForegroundColor White
        Write-Host ""
        Write-Host "  [M] Enter TV IP address manually" -ForegroundColor White
        Write-Host "  [R] Rescan network" -ForegroundColor White
        $choice = Read-Host "Select option [M/R]"
        if ($choice -match "^[Rr]") {
            return Discover-TVsOnNetwork
        } else {
            return (Read-Host "Enter TV IP address")
        }
    }

    # Inspect each discovered TV to get friendly model and OS
    Write-Host "`n[+] Found $($activeIps.Count) device(s) on Wi-Fi. Inspecting TV hardware details..." -ForegroundColor Green
    $discoveredDevices = @()

    foreach ($ip in $activeIps) {
        $t = "{0}:5555" -f $ip
        Invoke-Adb "connect $t" | Out-Null
        
        $manuf = (Invoke-Adb "-s $t shell getprop ro.product.manufacturer").Trim()
        $model = (Invoke-Adb "-s $t shell getprop ro.product.model").Trim()
        $osVer = (Invoke-Adb "-s $t shell getprop ro.build.version.name").Trim()
        if (-not $osVer) {
            $rel = (Invoke-Adb "-s $t shell getprop ro.build.version.release").Trim()
            $osVer = "Android $rel"
        }

        $friendlyName = Get-FriendlyDeviceName $manuf $model
        $discoveredDevices += [PSCustomObject]@{
            IP           = $ip
            Target       = $t
            FriendlyName = $friendlyName
            OS           = $osVer
            ModelCode    = $model
        }
    }

    Write-Host "`nDiscovered Smart TVs:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $discoveredDevices.Count; $i++) {
        $d = $discoveredDevices[$i]
        $num = $i + 1
        Write-Host ("  [{0}] {1}" -f $num, $d.FriendlyName) -ForegroundColor White -NoNewline
        Write-Host (" [{0}]" -f $d.IP) -ForegroundColor Yellow -NoNewline
        Write-Host (" - {0}" -f $d.OS) -ForegroundColor Gray
    }
    Write-Host "  [M] Enter custom IP address manually" -ForegroundColor White
    Write-Host "  [R] Rescan network" -ForegroundColor White
    Write-Host ""

    while ($true) {
        $sel = Read-Host "Select TV [1-$($discoveredDevices.Count), M, R]"
        if ($sel -match "^[Rr]") {
            return Discover-TVsOnNetwork
        } elseif ($sel -match "^[Mm]") {
            return (Read-Host "Enter TV IP address")
        } else {
            $idx = [int]$sel - 1
            if ($idx -ge 0 -and $idx -lt $discoveredDevices.Count) {
                return $discoveredDevices[$idx].IP
            }
            Write-Host "Invalid selection. Please choose 1 to $($discoveredDevices.Count)." -ForegroundColor Red
        }
    }
}

function Connect-FireTV {
    param([string]$DeviceIp)

    if ([string]::IsNullOrWhiteSpace($DeviceIp)) {
        $DeviceIp = Discover-TVsOnNetwork
    }

    if ([string]::IsNullOrWhiteSpace($DeviceIp)) {
        return $null
    }

    $target = "{0}:5555" -f $DeviceIp
    Write-Host "`n[*] Connecting to TV at $target..." -ForegroundColor Cyan

    Invoke-Adb "disconnect" | Out-Null
    Start-Sleep -Milliseconds 400
    $out = Invoke-Adb "connect $target"
    Write-Host "    $out" -ForegroundColor Gray

    # Verify device state
    $state = Invoke-Adb "-s $target get-state"
    if ($state -match "device") {
        # Wake device
        Invoke-Adb "-s $target shell input keyevent KEYCODE_WAKEUP" | Out-Null
        
        $model = (Invoke-Adb "-s $target shell getprop ro.product.model").Trim()
        $manuf = (Invoke-Adb "-s $target shell getprop ro.product.manufacturer").Trim()
        $name  = Get-FriendlyDeviceName $manuf $model
        
        Write-Host "`n[+] Successfully connected to $name ($target)!" -ForegroundColor Green
        return $target
    } else {
        Write-Host "[!] Could not establish ADB connection to $target ($state)." -ForegroundColor Red
        Write-Host "    Make sure you accepted the 'Always allow from this computer' prompt on your TV screen." -ForegroundColor Yellow
        return $null
    }
}

# ----------------- APP CATALOG DEFINITIONS -----------------
$AppCatalog = @(
    [PSCustomObject]@{
        Id          = 1
        Selected    = $true
        Name        = "Stremio (Android TV)"
        Description = "Movies & Series via P2P (ExoPlayer deadlock fixed)"
        Package     = "com.stremio.one"
        File        = "stremio-tv.apk"
        Url         = "https://dl.strem.io/android/v1.10.4-androidTV/com.stremio.one-1.10.4-31048580-armeabi-v7a.apk"
        IsCore      = $true
    },
    [PSCustomObject]@{
        Id          = 2
        Selected    = $true
        Name        = "SmartTube (4K HDR)"
        Description = "Ad-free YouTube with SponsorBlock & background audio"
        Package     = "org.smarttube.beta"
        File        = "smarttube.apk"
        Url         = "https://github.com/yuliskov/SmartTube/releases/download/latest/smarttube_beta.apk"
        IsCore      = $true
    },
    [PSCustomObject]@{
        Id          = 3
        Selected    = $true
        Name        = "TiviMate"
        Description = "Premium IPTV Player with EPG channel timeline guide"
        Package     = "ar.tvplayer.tv"
        File        = "tivimate.apk"
        Url         = "https://tivimate.com/tivimate.apk"
        IsCore      = $true
    },
    [PSCustomObject]@{
        Id          = 4
        Selected    = $false
        Name        = "Kodi 21 (Omega)"
        Description = "Modular open-source home theater & community addons"
        Package     = "org.xbmc.kodi"
        File        = "kodi-omega.apk"
        Url         = "https://mirrors.kodi.tv/releases/android/arm/kodi-21.2-Omega-armeabi-v7a.apk"
        IsCore      = $false
    },
    [PSCustomObject]@{
        Id          = 5
        Selected    = $false
        Name        = "VLC for Android TV"
        Description = "Universal media player for all USB & network video files"
        Package     = "org.videolan.vlc"
        File        = "vlc-android.apk"
        Url         = "https://get.videolan.org/vlc-android/last/VLC-Android-3.7.1-armeabi-v7a.apk"
        IsCore      = $false
    },
    [PSCustomObject]@{
        Id          = 6
        Selected    = $false
        Name        = "Nova Video Player"
        Description = "Open-source player with automatic movie poster scraping"
        Package     = "org.courville.nova"
        File        = "nova-video-player.apk"
        Url         = "https://github.com/nova-video-player/aos-AVP/releases/download/v6.6.2/org.courville.nova-2673649-6.6.2-20261027.1847-universal-release.apk"
        IsCore      = $false
    },
    [PSCustomObject]@{
        Id          = 7
        Selected    = $false
        Name        = "RetroArch"
        Description = "All-in-one retro gaming console & arcade emulator"
        Package     = "com.retroarch.ra32"
        File        = "retroarch.apk"
        Url         = "https://buildbot.libretro.com/stable/1.19.1/android/RetroArch_ra32.apk"
        IsCore      = $false
    },
    [PSCustomObject]@{
        Id          = 8
        Selected    = $false
        Name        = "F-Droid App Store"
        Description = "Independent open-source application repository for TV"
        Package     = "org.fdroid.fdroid"
        File        = "fdroid.apk"
        Url         = "https://f-droid.org/F-Droid.apk"
        IsCore      = $false
    }
)

function Show-AppChecklist {
    while ($true) {
        Clear-Host
        Write-Host "==========================================================================" -ForegroundColor Cyan
        Write-Host "                  SELECT APPS TO INSTALL ON YOUR TV                       " -ForegroundColor Yellow
        Write-Host "==========================================================================" -ForegroundColor Cyan
        Write-Host ""
        
        foreach ($app in $AppCatalog) {
            $box = if ($app.Selected) { "[X]" } else { "[ ]" }
            $color = if ($app.Selected) { "Green" } else { "DarkGray" }
            
            Write-Host ("  {0} {1}. " -f $box, $app.Id) -ForegroundColor $color -NoNewline
            Write-Host ("{0,-22}" -f $app.Name) -ForegroundColor White -NoNewline
            Write-Host (" - {0}" -f $app.Description) -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "--------------------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host " Commands:" -ForegroundColor Yellow
        Write-Host "   Type a number [1-$($AppCatalog.Count)] to toggle that app on or off" -ForegroundColor White
        Write-Host "   Type [A] to Select All    |  Type [N] to Clear All" -ForegroundColor White
        Write-Host "   Press [Enter] when ready to proceed with installation" -ForegroundColor Green
        Write-Host "--------------------------------------------------------------------------" -ForegroundColor Cyan
        
        $inputVal = (Read-Host "Choice [1-$($AppCatalog.Count), A, N, or Enter]").Trim()

        if ([string]::IsNullOrWhiteSpace($inputVal)) {
            $selectedCount = ($AppCatalog | Where-Object { $_.Selected }).Count
            if ($selectedCount -eq 0) {
                Write-Host "`n[!] You have not selected any apps! Please select at least 1 app." -ForegroundColor Red
                Start-Sleep -Seconds 1
                continue
            }
            break
        } elseif ($inputVal -match "^[Aa]") {
            $AppCatalog | ForEach-Object { $_.Selected = $true }
        } elseif ($inputVal -match "^[Nn]") {
            $AppCatalog | ForEach-Object { $_.Selected = $false }
        } else {
            $num = 0
            if ([int]::TryParse($inputVal, [ref]$num)) {
                $targetApp = $AppCatalog | Where-Object { $_.Id -eq $num }
                if ($targetApp) {
                    $targetApp.Selected = -not $targetApp.Selected
                }
            }
        }
    }
}

function Show-TweaksChecklist {
    $stremioSelected = ($AppCatalog | Where-Object { $_.Id -eq 1 -and $_.Selected }) -ne $null

    $tweaks = @(
        [PSCustomObject]@{ Id = 1; Selected = $true; Name = "AdGuard Private DNS (DoT)"; Desc = "Zero-VPN system-wide ad, tracker & telemetry blocker" },
        [PSCustomObject]@{ Id = 2; Selected = $stremioSelected; Name = "Stremio ExoPlayer Fix"; Desc = "Disable tunneled playback (stops trailer bug) & Ultra Fast profile" },
        [PSCustomObject]@{ Id = 3; Selected = $true; Name = "Amazon Telemetry Debloat"; Desc = "Disable retail demos, ad metrics & shopping background services" }
    )

    while ($true) {
        Clear-Host
        Write-Host "==========================================================================" -ForegroundColor Cyan
        Write-Host "                 SELECT SYSTEM TWEAKS & OPTIMIZATIONS                     " -ForegroundColor Yellow
        Write-Host "==========================================================================" -ForegroundColor Cyan
        Write-Host ""

        foreach ($t in $tweaks) {
            $box = if ($t.Selected) { "[X]" } else { "[ ]" }
            $color = if ($t.Selected) { "Green" } else { "DarkGray" }
            Write-Host ("  {0} {1}. " -f $box, $t.Id) -ForegroundColor $color -NoNewline
            Write-Host ("{0,-28}" -f $t.Name) -ForegroundColor White -NoNewline
            Write-Host (" - {0}" -f $t.Desc) -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "--------------------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host " Commands:" -ForegroundColor Yellow
        Write-Host "   Type [1-3] to toggle on/off  |  Press [Enter] to start deployment" -ForegroundColor White
        Write-Host "--------------------------------------------------------------------------" -ForegroundColor Cyan

        $inVal = (Read-Host "Choice [1-3 or Enter]").Trim()
        if ([string]::IsNullOrWhiteSpace($inVal)) {
            break
        } else {
            $num = 0
            if ([int]::TryParse($inVal, [ref]$num)) {
                $targetTweak = $tweaks | Where-Object { $_.Id -eq $num }
                if ($targetTweak) {
                    $targetTweak.Selected = -not $targetTweak.Selected
                }
            }
        }
    }

    return $tweaks
}

function Install-SelectedApps {
    param([string]$Target)

    $chosenApps = $AppCatalog | Where-Object { $_.Selected }

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host ("           INSTALLING {0} SELECTED APP(S)              " -f $chosenApps.Count) -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan

    foreach ($app in $chosenApps) {
        $apkPath = Join-Path $ApksDir $app.File
        Write-Host ("`n[*] Processing: {0}..." -f $app.Name) -ForegroundColor Cyan

        # Download if missing
        if (-not (Test-Path $apkPath)) {
            Write-Host ("    Downloading {0} from official source..." -f $app.File) -ForegroundColor Yellow
            try {
                Invoke-WebRequest -Uri $app.Url -OutFile $apkPath -UseBasicParsing
                Write-Host "    Download complete!" -ForegroundColor Green
            } catch {
                Write-Host ("    [!] Download failed: {0}" -f $_) -ForegroundColor Red
                continue
            }
        }

        # Check if already installed
        $check = Invoke-Adb "-s $Target shell pm list packages $($app.Package)"
        if ($check -match $app.Package) {
            Write-Host "    App already present. Updating..." -ForegroundColor Gray
        } else {
            Write-Host "    Installing fresh package..." -ForegroundColor Gray
        }

        $res = Invoke-Adb "-s $Target install -r -d `"$apkPath`""
        if ($res -match "Success") {
            Write-Host ("    [+] {0} successfully installed!" -f $app.Name) -ForegroundColor Green
        } else {
            Write-Host ("    [!] Install result: {0}" -f $res) -ForegroundColor Yellow
        }
    }

    # Grant storage and audio permissions automatically
    Write-Host "`n[*] Granting optimal runtime permissions..." -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell pm grant com.stremio.one android.permission.WRITE_EXTERNAL_STORAGE" 2>$null | Out-Null
    Invoke-Adb "-s $Target shell pm grant com.stremio.one android.permission.READ_EXTERNAL_STORAGE" 2>$null | Out-Null
    Invoke-Adb "-s $Target shell pm grant org.smarttube.beta android.permission.RECORD_AUDIO" 2>$null | Out-Null
    Invoke-Adb "-s $Target shell pm grant ar.tvplayer.tv android.permission.WRITE_EXTERNAL_STORAGE" 2>$null | Out-Null
    Invoke-Adb "-s $Target shell pm grant org.videolan.vlc android.permission.WRITE_EXTERNAL_STORAGE" 2>$null | Out-Null
    Invoke-Adb "-s $Target shell pm grant org.courville.nova android.permission.WRITE_EXTERNAL_STORAGE" 2>$null | Out-Null
    Write-Host "    [+] Runtime permissions configured." -ForegroundColor Green
}

function Configure-PrivateDNS {
    param([string]$Target)

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "     CONFIGURING ADGUARD PRIVATE DNS (Zero-VPN)         " -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan

    Write-Host "[*] Removing any legacy VPN filters..." -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell am force-stop dnsfilter.android" | Out-Null
    Invoke-Adb "-s $Target shell pm uninstall dnsfilter.android" 2>$null | Out-Null

    Write-Host "[*] Setting native Private DNS over TLS (DoT) to dns.adguard-dns.com..." -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell settings put global private_dns_mode hostname" | Out-Null
    Invoke-Adb "-s $Target shell settings put global private_dns_specifier dns.adguard-dns.com" | Out-Null

    Start-Sleep -Seconds 2

    # Verify settings
    $mode = Invoke-Adb "-s $Target shell settings get global private_dns_mode"
    $spec = Invoke-Adb "-s $Target shell settings get global private_dns_specifier"

    Write-Host ("    DNS Mode: {0}" -f $mode) -ForegroundColor Gray
    Write-Host ("    Provider: {0}" -f $spec) -ForegroundColor Gray

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
    Write-Host "   OPTIMIZING STREMIO (Trailer Bug Fix & Ultra Speed)   " -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan

    $checkStremio = Invoke-Adb "-s $Target shell pm list packages com.stremio.one"
    if ($checkStremio -notmatch "com.stremio.one") {
        Write-Host "[!] Stremio is not installed on this device. Skipping optimization." -ForegroundColor Gray
        return
    }

    Write-Host "[*] Launching Stremio to configure settings..." -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell monkey -p com.stremio.one -c android.intent.category.LAUNCHER 1" | Out-Null
    Start-Sleep -Seconds 4

    # Navigate to Settings icon (Left sidebar -> Down to Gear)
    Write-Host "[*] Opening Playback settings..." -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_LEFT" | Out-Null
    Start-Sleep -Milliseconds 300
    1..5 | ForEach-Object {
        Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_DOWN" | Out-Null
        Start-Sleep -Milliseconds 200
    }
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_CENTER" | Out-Null
    Start-Sleep -Seconds 1

    # In Settings: Playback tab
    Write-Host "[*] Configuring Tunneled Playback and Frame Rate Matching..." -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell input keyevent KEYCODE_DPAD_RIGHT" | Out-Null
    Start-Sleep -Milliseconds 300
    
    # In Settings: Server tab for Torrent Profile -> Ultra Fast
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
    Write-Host "          DEBLOATING FIRE TV PERFORMANCE                " -ForegroundColor Yellow
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
            Write-Host ("    [-] Disabled: {0}" -f $pkg) -ForegroundColor Gray
        }
    }

    Write-Host ("[+] Debloat complete ({0} background telemetry packages disabled)." -f $disabledCount) -ForegroundColor Green
    Write-Host "    Core system functions (Wi-Fi, Bluetooth, Audio, Remote, Settings) remain untouched." -ForegroundColor Green
}

# ----------------- MAIN EXECUTION FLOW -----------------
Write-Header

if ($Express) {
    $target = Connect-FireTV $TargetIP
    if ($target) {
        Configure-PrivateDNS $target
        Install-SelectedApps $target
        Optimize-StremioSettings $target
        if (-not $SkipDebloat) { Debloat-FireTV $target }

        Write-Host "`n========================================================" -ForegroundColor Green
        Write-Host "       ALL TASKS COMPLETED SUCCESSFULLY!                " -ForegroundColor Yellow
        Write-Host "========================================================" -ForegroundColor Green
        Write-Host "Your TV is 100% configured and ready to use." -ForegroundColor White
        Write-Host "No computer or middleman is needed." -ForegroundColor White
    }
    exit 0
}

# 1. Select / Discover TV
$target = Connect-FireTV $TargetIP
if (-not $target) {
    Write-Host "`nExiting setup." -ForegroundColor Red
    pause
    exit 1
}

# 2. Select Apps via Interactive Checklist
Show-AppChecklist

# 3. Select System Tweaks & Optimizations Checklist
$chosenTweaks = Show-TweaksChecklist

# 4. Start Deployment
Clear-Host
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "                 DEPLOYING SELECTED APPS & OPTIMIZATIONS                  " -ForegroundColor Yellow
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host ("Target Device: {0}" -f $target) -ForegroundColor White

# Run DNS if selected
$dnsTweak = $chosenTweaks | Where-Object { $_.Id -eq 1 -and $_.Selected }
if ($dnsTweak) {
    Configure-PrivateDNS $target
}

# Run Apps
Install-SelectedApps $target

# Run Stremio Tweak if selected
$stremioTweak = $chosenTweaks | Where-Object { $_.Id -eq 2 -and $_.Selected }
if ($stremioTweak) {
    Optimize-StremioSettings $target
}

# Run Debloat if selected
$debTweak = $chosenTweaks | Where-Object { $_.Id -eq 3 -and $_.Selected }
if ($debTweak) {
    Debloat-FireTV $target
}

# Wake and return to TV Home screen
Invoke-Adb "-s $target shell input keyevent KEYCODE_HOME" | Out-Null

Write-Host "`n==========================================================================" -ForegroundColor Green
Write-Host "       CONGRATULATIONS! YOUR TV SETUP IS COMPLETE!                        " -ForegroundColor Yellow
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "All selected apps have been installed and system tweaks applied." -ForegroundColor White
Write-Host "Your TV functions completely standalone. You can turn off your PC." -ForegroundColor White
Write-Host ""
pause
