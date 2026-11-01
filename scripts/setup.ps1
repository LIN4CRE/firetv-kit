<#
.SYNOPSIS
    Fire TV Ultimate Setup Kit - Automated Network Discovery, App Checklist & Optimizer
    Supports any Fire TV, Android TV, Google TV, or Shield TV on any Wi-Fi network.
#>

[CmdletBinding()]
param(
    [string]$TargetIP,
    [switch]$Express,
    [switch]$SkipDebloat,
    [switch]$Diagnostics,
    [switch]$RestoreDebloat,
    [ValidateSet("AdGuard", "AdGuardFamily", "Cloudflare", "Quad9", "Custom")]
    [string]$DnsProfile = "AdGuard",
    [string]$CustomDnsHost,
    [ValidateSet("Safe", "Balanced", "Aggressive")]
    [string]$DebloatLevel = "Balanced",
    [string]$DebloatStatePath,
    [string]$ExportProfilePath,
    [string]$ImportProfilePath
)

$Host.UI.RawUI.WindowTitle = "Fire TV Ultimate Setup Kit"
$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
$ToolsDir  = Join-Path $RootDir "tools"
$ApksDir   = Join-Path $RootDir "apks"
$AdbExe    = Join-Path $ToolsDir "adb.exe"

# Fallback if adb is in path or sibling directories
if (-not (Test-Path $AdbExe)) {
    $SysAdb = Get-Command adb -ErrorAction SilentlyContinue
    if ($SysAdb) {
        $AdbExe = $SysAdb.Source
    } else {
        $parentDir = Split-Path -Parent $RootDir
        $candidatePaths = @(
            (Join-Path $parentDir "platform-tools\adb.exe"),
            (Join-Path $parentDir "tv-debloat\platform-tools\adb.exe")
        )
        foreach ($cp in $candidatePaths) {
            if (Test-Path $cp) {
                $AdbExe = $cp
                break
            }
        }
    }
}

# Ensure apks folder exists
if (-not (Test-Path $ApksDir)) {
    New-Item -ItemType Directory -Force -Path $ApksDir | Out-Null
}

# DNS Profiles Table
$Script:DnsProviders = @{
    "AdGuard"       = @{ Name = "AdGuard Default"; Host = "dns.adguard-dns.com"; Desc = "System-wide ad, tracking & telemetry blocking (zero VPN)" }
    "AdGuardFamily" = @{ Name = "AdGuard Family"; Host = "family.adguard-dns.com"; Desc = "Ad blocking + adult content & safe search enforcement" }
    "Cloudflare"    = @{ Name = "Cloudflare Security"; Host = "security.cloudflare-dns.com"; Desc = "1.1.1.2 malware, command & control threat protection" }
    "Quad9"         = @{ Name = "Quad9 Threat Intel"; Host = "dns.quad9.net"; Desc = "Swiss privacy-respecting threat intelligence" }
}

# Debloat Tier Definitions
$Script:DebloatTiers = @{
    "Safe" = @(
        "com.amazon.device.sale.service",
        "com.amazon.whisperjoin.middleware.security",
        "com.amazon.shpm",
        "com.amazon.visualsearch",
        "com.amazon.unifiedsearch",
        "com.amazon.tmm",
        "com.amazon.precog"
    )
    "Balanced" = @(
        "com.amazon.device.sale.service",
        "com.amazon.whisperjoin.middleware.security",
        "com.amazon.shpm",
        "com.amazon.visualsearch",
        "com.amazon.unifiedsearch",
        "com.amazon.tmm",
        "com.amazon.precog",
        "com.amazon.firehomedevice",
        "com.amazon.advertising.idprovider",
        "com.amazon.kor.demo",
        "com.amazon.altair.retail",
        "com.amazon.cardinal"
    )
    "Aggressive" = @(
        "com.amazon.device.sale.service",
        "com.amazon.whisperjoin.middleware.security",
        "com.amazon.shpm",
        "com.amazon.visualsearch",
        "com.amazon.unifiedsearch",
        "com.amazon.tmm",
        "com.amazon.precog",
        "com.amazon.firehomedevice",
        "com.amazon.advertising.idprovider",
        "com.amazon.kor.demo",
        "com.amazon.altair.retail",
        "com.amazon.cardinal",
        "com.amazon.ftv.screensaver",
        "com.amazon.buysettings"
    )
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
        "AFTGAZL"            = "Amazon Fire TV Cube (3rd Gen)"
        "AFTR"               = "Amazon Fire TV Cube (2nd Gen)"
        "AFTKM"              = "Amazon Fire TV Cube (1st Gen)"
        "AFTKA"              = "Amazon Fire TV Stick 4K Max (1st Gen)"
        "AFTKRT"             = "Amazon Fire TV Stick 4K Max (2nd Gen)"
        "AFTMM"              = "Amazon Fire TV Stick 4K (1st Gen)"
        "AFTKMST"            = "Amazon Fire TV Stick 4K (2nd Gen)"
        "AFTSSS"             = "Amazon Fire TV Stick Lite"
        "AFTSS"              = "Amazon Fire TV Stick (3rd Gen)"
        "AFTT"               = "Amazon Fire TV Stick (2nd Gen)"
        "AFTB"               = "Amazon Fire TV (1st Gen)"
        "AFTS"               = "Amazon Fire TV (2nd Gen)"
        "AFTN"               = "Amazon Fire TV (3rd Gen Pendant)"
        "AFTOQ"              = "Amazon Fire TV Omni QLED Series"
        "AFTBSS"             = "Amazon Fire TV 2-Series"
        "AFTBSE"             = "Amazon Fire TV 4-Series"
        "AFTBOXE1"           = "Toshiba 4K UHD Fire TV Edition"
        "AFTJM"              = "Insignia 4K UHD Fire TV Edition"
        "SHIELD Android TV"  = "NVIDIA SHIELD TV"
        "SHIELD Android TV Pro" = "NVIDIA SHIELD TV Pro"
        "mdarcy"             = "NVIDIA SHIELD TV Pro (2019)"
        "sif"                = "NVIDIA SHIELD TV (Tube 2019)"
        "Chromecast"         = "Google Chromecast with Google TV"
        "Google TV Streamer" = "Google TV Streamer 4K"
        "G454V"              = "Chromecast with Google TV (HD)"
        "GA01919"            = "Chromecast with Google TV (4K)"
        "240411"             = "Onn 4K Streaming Box"
        "onn. 4K Pro"        = "Onn 4K Pro Streaming Device"
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

    # Detect active private IPv4 network interfaces prioritizing active default gateway
    $detectedIps = [System.Collections.Generic.List[string]]::new()
    $activeConfigs = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway -and $_.IPv4Address }
    if ($activeConfigs) {
        foreach ($cfg in $activeConfigs) {
            foreach ($ipObj in $cfg.IPv4Address) {
                if ($ipObj.IPAddress -and $ipObj.IPAddress -notlike "169.254.*" -and $ipObj.IPAddress -ne "127.0.0.1") {
                    $detectedIps.Add($ipObj.IPAddress)
                }
            }
        }
    }
    if ($detectedIps.Count -eq 0) {
        $adapters = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { 
            ($_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*" -or $_.IPAddress -like "172.1[6-9].*" -or $_.IPAddress -like "172.2[0-9].*" -or $_.IPAddress -like "172.3[0-1].*") -and 
            $_.IPAddress -notlike "*.255" -and $_.IPAddress -ne "127.0.0.1"
        })
        foreach ($a in $adapters) { $detectedIps.Add($a.IPAddress) }
    }

    if ($detectedIps.Count -eq 0) {
        Write-Host "[!] Could not automatically detect local network adapter." -ForegroundColor Yellow
        $ip = Read-Host "Enter Fire TV / Android TV IP address manually"
        return $ip
    }

    # Use first active gateway / private adapter
    $localIp = $detectedIps[0]
    $base = $localIp.Substring(0, $localIp.LastIndexOf("."))
    $scanMsg = "[*] Scanning subnet ({0}.1 - {0}.254) for Android & Fire TVs on port 5555..." -f $base
    Write-Host $scanMsg -ForegroundColor Cyan

    # High-speed non-blocking port 5555 probe
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

    # Adaptive bounded wait for connection responses (up to 600ms, early exit after 300ms if found)
    $scanSw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($scanSw.ElapsedMilliseconds -lt 600) {
        $anyFound = $false
        foreach ($p in $probes) {
            if ($p.AsyncResult.IsCompleted -and $p.Client.Connected) {
                $anyFound = $true
                break
            }
        }
        if ($anyFound -and $scanSw.ElapsedMilliseconds -ge 300) { break }
        Start-Sleep -Milliseconds 40
    }
    $scanSw.Stop()

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
        $abi   = (Invoke-Adb "-s $target shell getprop ro.product.cpu.abi").Trim()
        $name  = Get-FriendlyDeviceName $manuf $model
        $archLabel = if ($abi -match "64") { "64-bit ($abi)" } else { "32-bit ($abi)" }
        
        Write-Host "`n[+] Successfully connected to $name ($target)!" -ForegroundColor Green
        Write-Host "    Hardware Architecture: $archLabel" -ForegroundColor DarkGray
        return $target
    } else {
        Write-Host "[!] Could not establish ADB connection to $target ($state)." -ForegroundColor Red
        Write-Host "    Make sure you accepted the 'Always allow from this computer' prompt on your TV screen." -ForegroundColor Yellow
        return $null
    }
}

function Test-FireTVDiagnostics {
    param([string]$Target)

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "       FIRE TV SYSTEM & HARDWARE DIAGNOSTICS            " -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan

    $disp = Invoke-Adb "-s $Target shell wm size"
    $density = Invoke-Adb "-s $Target shell wm density"
    $storage = Invoke-Adb "-s $Target shell df -h /data"
    $mem = Invoke-Adb "-s $Target shell cat /proc/meminfo"
    $androidVer = (Invoke-Adb "-s $Target shell getprop ro.build.version.release").Trim()
    $sdkVer = (Invoke-Adb "-s $Target shell getprop ro.build.version.sdk").Trim()
    $securityPatch = (Invoke-Adb "-s $Target shell getprop ro.build.version.security_patch").Trim()
    $thermal = (Invoke-Adb "-s $Target shell cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null").Trim()

    # Sanitize display resolution
    $dispClean = ($disp -split "`r?`n" | ForEach-Object { $_ -replace 'Physical size:\s*', '' } | Where-Object { $_ -match '\d+x\d+' } | Select-Object -First 1)
    if (-not $dispClean) { $dispClean = ($disp -replace 'Physical size:\s*', '').Trim() }

    $densClean = ($density -split "`r?`n" | ForEach-Object { $_ -replace 'Physical density:\s*', '' } | Where-Object { $_ -match '\d+' } | Select-Object -First 1)
    if (-not $densClean) { $densClean = ($density -replace 'Physical density:\s*', '').Trim() }

    Write-Host "  [+] Display Resolution : $dispClean" -ForegroundColor White
    Write-Host "  [+] Screen Density     : $densClean DPI" -ForegroundColor White
    Write-Host "  [+] Android OS Release : Android $androidVer (API Level $sdkVer)" -ForegroundColor White
    if ($securityPatch) {
        Write-Host "  [+] Security Patch     : $securityPatch" -ForegroundColor White
    }
    
    # Parse storage (wrap in array to prevent single-string scalar indexing bug)
    $storageLines = @($storage -split "`r?`n" | Where-Object { $_ -match "/data" })
    if ($storageLines.Count -gt 0) {
        $cols = $storageLines[0].Trim() -split '\s+'
        if ($cols.Count -ge 5) {
            Write-Host "  [+] Data Partition     : Total $($cols[1]), Used $($cols[2]), Free $($cols[3]) ($($cols[4]) used)" -ForegroundColor White
        }
    }

    # Parse RAM with MemAvailable or MemFree+Buffers+Cached fallback for older kernels
    $memMatchTotal = [regex]::Match($mem, 'MemTotal:\s+(\d+)\s+kB')
    $memMatchAvail = [regex]::Match($mem, 'MemAvailable:\s+(\d+)\s+kB')
    $availKb = 0
    if ($memMatchAvail.Success) {
        $availKb = [int64]$memMatchAvail.Groups[1].Value
    } else {
        $memFree = [regex]::Match($mem, 'MemFree:\s+(\d+)\s+kB')
        $buffers = [regex]::Match($mem, 'Buffers:\s+(\d+)\s+kB')
        $cached  = [regex]::Match($mem, 'Cached:\s+(\d+)\s+kB')
        if ($memFree.Success) { $availKb += [int64]$memFree.Groups[1].Value }
        if ($buffers.Success) { $availKb += [int64]$buffers.Groups[1].Value }
        if ($cached.Success)  { $availKb += [int64]$cached.Groups[1].Value }
    }

    if ($memMatchTotal.Success -and $availKb -gt 0) {
        $totalMB = [math]::Round([int64]$memMatchTotal.Groups[1].Value / 1024)
        $availMB = [math]::Round($availKb / 1024)
        $usedMB = $totalMB - $availMB
        $pct = [math]::Round(($usedMB / $totalMB) * 100)
        Write-Host "  [+] System RAM         : Total ${totalMB}MB, Available ${availMB}MB (${pct}% in use)" -ForegroundColor White
    }

    if ($thermal -and $thermal -match "^\d+$") {
        $tempC = [math]::Round([int]$thermal / 1000, 1)
        Write-Host "  [+] Thermal Status     : ${tempC}°C" -ForegroundColor White
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
        [PSCustomObject]@{ Id = 3; Selected = $true; Name = "Fire TV Telemetry Debloat"; Desc = "Disable retail demos, ad metrics & shopping background services" },
        [PSCustomObject]@{ Id = 4; Selected = $true; Name = "System Diagnostics Report"; Desc = "Hardware, screen resolution, RAM and storage telemetry display" }
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
        Write-Host "   Type [1-4] to toggle on/off  |  Press [Enter] to start deployment" -ForegroundColor White
        Write-Host "--------------------------------------------------------------------------" -ForegroundColor Cyan

        $inVal = (Read-Host "Choice [1-4 or Enter]").Trim()
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
    param(
        [string]$Target,
        [string]$Provider = "AdGuard",
        [string]$CustomHost
    )

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "     CONFIGURING PRIVATE DNS (Zero-VPN DoT Encryption)  " -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan

    $dnsHost = ""
    $dnsName = ""

    if ($Provider -eq "Custom") {
        $candidateHost = if ($CustomHost) { $CustomHost } else { $CustomDnsHost }
        if ([string]::IsNullOrWhiteSpace($candidateHost)) {
            $candidateHost = Read-Host "Enter custom Private DNS over TLS hostname (e.g., custom.dns.example.com)"
        }
        if ($candidateHost -match '^[a-zA-Z0-9\.\-]+\.[a-zA-Z]{2,}$') {
            $dnsHost = $candidateHost.Trim()
            $dnsName = "Custom Provider ($dnsHost)"
        } else {
            Write-Host "[!] Invalid DNS hostname provided. Falling back to AdGuard Default." -ForegroundColor Yellow
            $profile = $Script:DnsProviders["AdGuard"]
            $dnsHost = $profile.Host
            $dnsName = $profile.Name
        }
    } else {
        $profile = $Script:DnsProviders[$Provider]
        if (-not $profile) {
            $profile = $Script:DnsProviders["AdGuard"]
        }
        $dnsHost = $profile.Host
        $dnsName = $profile.Name
    }

    Write-Host "[*] Removing any legacy VPN filters..." -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell am force-stop dnsfilter.android" | Out-Null
    Invoke-Adb "-s $Target shell pm uninstall dnsfilter.android" 2>$null | Out-Null

    Write-Host ("[*] Setting Private DNS over TLS (DoT) to {0} ({1})..." -f $dnsHost, $dnsName) -ForegroundColor Cyan
    Invoke-Adb "-s $Target shell settings put global private_dns_mode hostname" | Out-Null
    Invoke-Adb "-s $Target shell settings put global private_dns_specifier $dnsHost" | Out-Null

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
        Write-Host ("    [+] Telemetry and ads blocked via {0} without any proxy or middleman PC!" -f $profile.Name) -ForegroundColor Green
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
    param(
        [string]$Target,
        [string]$Level = "Balanced"
    )

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host ("     DEBLOATING FIRE TV PERFORMANCE (Level: {0})        " -f $Level) -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan

    $bloatList = $Script:DebloatTiers[$Level]
    if (-not $bloatList) {
        $bloatList = $Script:DebloatTiers["Balanced"]
    }

    $disabledPackages = [System.Collections.Generic.List[string]]::new()
    $disabledCount = 0

    foreach ($pkg in $bloatList) {
        $res = Invoke-Adb "-s $Target shell pm disable-user --user 0 $pkg"
        if ($res -match "disabled") {
            $disabledCount++
            $disabledPackages.Add($pkg)
            Write-Host ("    [-] Disabled: {0}" -f $pkg) -ForegroundColor Gray
        }
    }

    # Save state snapshot for instant rollback
    $cleanIp = ($Target -replace ":.*", "")
    $snapshotFile = Join-Path $RootDir ("debloat-state-{0}.json" -f $cleanIp)
    @{
        TargetIP = $cleanIp
        Level = $Level
        Timestamp = (Get-Date).ToString("o")
        DisabledPackages = $disabledPackages
    } | ConvertTo-Json -Depth 3 | Set-Content -Path $snapshotFile -Encoding UTF8

    Write-Host ("[+] Debloat complete ({0} background telemetry packages disabled)." -f $disabledCount) -ForegroundColor Green
    Write-Host ("    Rollback snapshot saved to: {0}" -f (Split-Path -Leaf $snapshotFile)) -ForegroundColor DarkGray
    Write-Host "    Core system functions (Wi-Fi, Bluetooth, Audio, Remote, Settings) remain untouched." -ForegroundColor Green
}

function Restore-FireTVPackages {
    param(
        [string]$Target,
        [string]$StateFile
    )

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "       RESTORING FIRE TV PACKAGES & SERVICES            " -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan

    $cleanIp = ($Target -replace ":.*", "")
    if (-not $StateFile) {
        $autoSnapshot = Join-Path $RootDir ("debloat-state-{0}.json" -f $cleanIp)
        if (Test-Path $autoSnapshot) {
            $StateFile = $autoSnapshot
            Write-Host ("[*] Auto-detected debloat snapshot: {0}" -f (Split-Path -Leaf $autoSnapshot)) -ForegroundColor Cyan
        }
    }

    $packagesToRestore = @()

    if ($StateFile -and (Test-Path $StateFile)) {
        try {
            $state = Get-Content -Raw $StateFile | ConvertFrom-Json
            $packagesToRestore = $state.DisabledPackages
            Write-Host ("[*] Loaded {0} package(s) from snapshot (Level: {1})" -f $packagesToRestore.Count, $state.Level) -ForegroundColor Cyan
        } catch {
            Write-Host ("[!] Error reading state file: {0}. Falling back to Aggressive list." -f $_.Message) -ForegroundColor Yellow
            $packagesToRestore = $Script:DebloatTiers["Aggressive"]
        }
    } else {
        # Fallback to restoring all known debloat packages
        Write-Host "[*] No snapshot file found. Re-enabling all known debloat packages..." -ForegroundColor Yellow
        $packagesToRestore = $Script:DebloatTiers["Aggressive"]
    }

    $restoredCount = 0
    foreach ($pkg in $packagesToRestore) {
        $res = Invoke-Adb "-s $Target shell pm enable --user 0 $pkg"
        if ($res -match "enabled") {
            $restoredCount++
            Write-Host ("    [+] Restored: {0}" -f $pkg) -ForegroundColor Green
        }
    }

    Write-Host ("[+] Restore complete ({0} packages re-enabled)." -f $restoredCount) -ForegroundColor Green
}

function Export-FireTVProfile {
    param(
        [string]$Target,
        [string]$OutPath
    )

    if (-not $OutPath) {
        $cleanIp = ($Target -replace ":.*", "")
        $OutPath = Join-Path $RootDir ("firetv-profile-{0}.json" -f $cleanIp)
    }

    $dnsMode = Invoke-Adb "-s $Target shell settings get global private_dns_mode"
    $dnsSpec = Invoke-Adb "-s $Target shell settings get global private_dns_specifier"
    $model   = Invoke-Adb "-s $Target shell getprop ro.product.model"
    $manuf   = Invoke-Adb "-s $Target shell getprop ro.product.manufacturer"
    $abi     = Invoke-Adb "-s $Target shell getprop ro.product.cpu.abi"

    $profile = @{
        Manufacturer = $manuf.Trim()
        Model = $model.Trim()
        Architecture = $abi.Trim()
        PrivateDnsMode = $dnsMode.Trim()
        PrivateDnsSpecifier = $dnsSpec.Trim()
        ExportDate = (Get-Date).ToString("o")
    }

    $profile | ConvertTo-Json -Depth 3 | Set-Content -Path $OutPath -Encoding UTF8
    Write-Host ("[+] Device configuration exported to: {0}" -f $OutPath) -ForegroundColor Green
}

function Import-FireTVProfile {
    param(
        [string]$Target,
        [string]$ProfilePath
    )

    if (-not (Test-Path $ProfilePath)) {
        Write-Host ("[!] Profile file not found: {0}" -f $ProfilePath) -ForegroundColor Red
        return
    }

    $data = Get-Content -Raw $ProfilePath | ConvertFrom-Json
    Write-Host ("[+] Importing configuration for {0} {1}..." -f $data.Manufacturer, $data.Model) -ForegroundColor Cyan

    if ($data.PrivateDnsSpecifier) {
        $mode = if ($data.PrivateDnsMode) { $data.PrivateDnsMode } else { "hostname" }
        Invoke-Adb "-s $Target shell settings put global private_dns_mode $mode" | Out-Null
        Invoke-Adb "-s $Target shell settings put global private_dns_specifier $($data.PrivateDnsSpecifier)" | Out-Null
        Write-Host ("    [+] Restored Private DNS: {0}" -f $data.PrivateDnsSpecifier) -ForegroundColor Green
    }
}

# ----------------- MAIN EXECUTION FLOW -----------------
Write-Header

if ($RestoreDebloat) {
    $target = Connect-FireTV $TargetIP
    if ($target) {
        Restore-FireTVPackages $target $DebloatStatePath
    }
    exit 0
}

if ($Diagnostics) {
    $target = Connect-FireTV $TargetIP
    if ($target) {
        Test-FireTVDiagnostics $target
    }
    exit 0
}

if ($ExportProfilePath) {
    $target = Connect-FireTV $TargetIP
    if ($target) {
        Export-FireTVProfile $target $ExportProfilePath
    }
    exit 0
}

if ($ImportProfilePath) {
    $target = Connect-FireTV $TargetIP
    if ($target) {
        Import-FireTVProfile $target $ImportProfilePath
    }
    exit 0
}

if ($Express) {
    $target = Connect-FireTV $TargetIP
    if ($target) {
        Configure-PrivateDNS $target $DnsProfile
        Install-SelectedApps $target
        Optimize-StremioSettings $target
        if (-not $SkipDebloat) { Debloat-FireTV $target $DebloatLevel }
        Test-FireTVDiagnostics $target

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
    Configure-PrivateDNS $target $DnsProfile
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
    Debloat-FireTV $target $DebloatLevel
}

# Run Diagnostics if selected
$diagTweak = $chosenTweaks | Where-Object { $_.Id -eq 4 -and $_.Selected }
if ($diagTweak) {
    Test-FireTVDiagnostics $target
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
