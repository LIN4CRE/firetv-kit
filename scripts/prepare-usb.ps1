<#
.SYNOPSIS
    Prepare a USB Drive as a portable Fire TV Installation & Recovery Toolkit
#>

$ErrorActionPreference = "Continue"

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "       💾 PREPARE PORTABLE USB SETUP DRIVE              " -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
$ToolsDir  = Join-Path $RootDir "tools"
$ApksDir   = Join-Path $RootDir "apks"

# Find removable drives
$removableDrives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }

if ($removableDrives) {
    Write-Host "`nDetected Removable Drives (USB):" -ForegroundColor Green
    foreach ($d in $removableDrives) {
        $freeGB = [math]::Round($d.FreeSpace / 1GB, 2)
        $sizeGB = [math]::Round($d.Size / 1GB, 2)
        Write-Host "  -> Drive $($d.DeviceID) [$($d.VolumeName)] - Free: $freeGB GB / Total: $sizeGB GB" -ForegroundColor White
    }
    Write-Host ""
    $driveLetter = Read-Host "Enter USB Drive letter (e.g. E:)"
} else {
    Write-Host "`nNo removable USB drives automatically detected." -ForegroundColor Yellow
    Write-Host "Please insert your USB drive, or enter drive letter manually:" -ForegroundColor Yellow
    $driveLetter = Read-Host "Drive letter (e.g. E:)"
}

if (-not $driveLetter.EndsWith(":")) {
    $driveLetter = "$driveLetter`:"
}

if (-not (Test-Path "$driveLetter\")) {
    Write-Host "[!] Drive path $driveLetter does not exist or is not accessible." -ForegroundColor Red
    return
}

Write-Host "`nTarget selected: $driveLetter\" -ForegroundColor Cyan
$confirm = Read-Host "Copy Fire TV Setup Toolkit to $driveLetter\ ? (Y/N)"
if ($confirm -notmatch "^[Yy]") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    return
}

# 1. Create target directories on USB
Write-Host "`n[*] Creating folder structure on $driveLetter\..." -ForegroundColor Cyan
$targetApksDir   = Join-Path "$driveLetter\" "apks"
$targetToolsDir  = Join-Path "$driveLetter\" "tools"
$targetScriptsDir = Join-Path "$driveLetter\" "scripts"

New-Item -ItemType Directory -Force -Path $targetApksDir, $targetToolsDir, $targetScriptsDir | Out-Null

# 2. Copy APKs
Write-Host "[*] Copying Streaming APKs (Stremio, SmartTube, TiviMate)..." -ForegroundColor Cyan
Copy-Item (Join-Path $ApksDir "*") -Destination $targetApksDir -Force
Write-Host "    [+] APKs copied." -ForegroundColor Green

# 3. Copy Tools
Write-Host "[*] Copying portable ADB tools..." -ForegroundColor Cyan
Copy-Item (Join-Path $ToolsDir "*") -Destination $targetToolsDir -Force
Write-Host "    [+] ADB tools copied." -ForegroundColor Green

# 4. Copy Scripts
Write-Host "[*] Copying automation scripts..." -ForegroundColor Cyan
Copy-Item (Join-Path $ScriptDir "*") -Destination $targetScriptsDir -Force
Write-Host "    [+] Scripts copied." -ForegroundColor Green

# 5. Create Root Launchers on USB
$usbBatContent = @"
@echo off
title Fire TV Setup Kit (Running from USB)
cls
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup.ps1"
pause
"@
Set-Content -Path (Join-Path "$driveLetter\" "INSTALL_ON_PC.bat") -Value $usbBatContent -Force

# 6. Create Direct-on-TV Guide on USB
$guideContent = @"
========================================================================
   FIRE TV SETUP TOOLKIT - DIRECT USB PLUG-IN INSTRUCTIONS
========================================================================

You have plugged this USB drive directly into your Fire TV (e.g. Fire TV
Cube or Fire Stick with an OTG Cable).

Follow these quick steps on your TV:

1. ENABLE INSTALL UNKNOWN APPS:
   On Fire TV, go to:
   Settings -> My Fire TV -> Developer Options -> Install Unknown Apps
   Turn it ON for your file manager (Downloader, Total Commander, etc.).
   (If Developer Options is hidden, go to Settings -> My Fire TV -> About
    and click the TV name 7 times rapidly to unlock it).

2. BROWSE USB DRIVE ON TV:
   Open any file manager on your TV (such as 'Total Commander' or 'Downloader').
   Navigate to the USB drive -> 'apks' folder.

3. INSTALL THE BIG 3 APPS:
   - stremio-tv.apk    (Stremio with ExoPlayer Android TV UI)
   - smarttube.apk     (Ad-free YouTube with SponsorBlock & 4K)
   - tivimate.apk      (IPTV player)

4. RECOMMENDED AUTOMATIC SETUP (BETTER & FASTER):
   Instead of clicking each APK with the remote, you can plug this USB 
   drive into ANY computer or laptop on your home Wi-Fi and double-click:
   
       INSTALL_ON_PC.bat

   It will automatically install the apps wirelessly, set AdGuard Private
   DNS (blocks all ads system-wide without any VPN), and configure Stremio
   to prevent the trailer restart bug!
========================================================================
"@
Set-Content -Path (Join-Path "$driveLetter\" "TV_DIRECT_INSTALL_GUIDE.txt") -Value $guideContent -Force

# 7. Create Downloader Shortcodes text on USB
$shortcodesContent = @"
========================================================================
   FIRE TV ZERO-PC DOWNLOADER SHORTCODES (100% REMOTE SETUP)
========================================================================

If you are setting up a brand-new Fire TV without any PC or USB:

1. Open the 'Downloader' app on your Fire TV.
2. In the URL bar, type any of these direct shortcodes / URLs:

   - SmartTube (Ad-free YouTube):
     URL: https://smarttubeapp.github.io
     Or Shortcode: 28544

   - Stremio (Android TV):
     URL: https://www.stremio.com/downloads
     Or Direct APK: https://dl.strem.io/android/v1.10.4-androidTV/com.stremio.one-1.10.4-31048580-armeabi-v7a.apk

   - TiviMate:
     URL: https://tivimate.com/tivimate.apk
     Or Shortcode: 272483

3. To block ads system-wide without apps or middleman:
   Use Fire TV ADB or Network Settings to set Private DNS to:
   dns.adguard-dns.com
========================================================================
"@
Set-Content -Path (Join-Path "$driveLetter\" "DOWNLOADER_SHORTCODES.txt") -Value $shortcodesContent -Force

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "       🎉 USB DRIVE READY FOR DEPLOYMENT!               " -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Drive $driveLetter\ is now a portable Fire TV installer toolkit." -ForegroundColor White
Write-Host "- Plug into any PC on the network -> Run INSTALL_ON_PC.bat" -ForegroundColor White
Write-Host "- Or plug directly into Fire TV Cube -> Install from 'apks' folder" -ForegroundColor White
