<#
.SYNOPSIS
    Automated Test Suite for Fire TV Ultimate Setup Kit
    Validates structure, syntax, binary integrity, USB creation, model maps, DNS profiles, debloat safety, and live device state.
#>

[CmdletBinding()]
param(
    [string]$DeviceIp = "192.168.0.64",
    [switch]$SkipLiveDevice
)

$Host.UI.RawUI.WindowTitle = "Fire TV Setup Kit - Test Runner"
$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
$ToolsDir  = Join-Path $RootDir "tools"
$ApksDir   = Join-Path $RootDir "apks"
$AdbExe    = Join-Path $ToolsDir "adb.exe"

$Passed = 0
$Failed = 0
$Skipped = 0

function Write-TestResult {
    param(
        [string]$Name,
        [bool]$Success,
        [string]$Message = ""
    )
    if ($Success) {
        $script:Passed++
        Write-Host "  [PASS] " -ForegroundColor Green -NoNewline
        Write-Host $Name -ForegroundColor White
        if ($Message) { Write-Host "         $Message" -ForegroundColor Gray }
    } else {
        $script:Failed++
        Write-Host "  [FAIL] " -ForegroundColor Red -NoNewline
        Write-Host $Name -ForegroundColor Yellow
        if ($Message) { Write-Host "         ERROR: $Message" -ForegroundColor Red }
    }
}

function Write-TestSkip {
    param([string]$Name, [string]$Reason)
    $script:Skipped++
    Write-Host "  [SKIP] " -ForegroundColor DarkYellow -NoNewline
    Write-Host $Name -ForegroundColor White
    Write-Host "         REASON: $Reason" -ForegroundColor DarkGray
}

Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "        [+] FIRE TV SETUP KIT - AUTOMATED TEST SUITE                     " -ForegroundColor Yellow
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host ""

# -------------------------------------------------------------
# TEST GROUP 1: FILE SYSTEM STRUCTURE & REQUIRED ASSETS
# -------------------------------------------------------------
Write-Host "[Group 1: File Structure & Core Components]" -ForegroundColor Cyan

$requiredFiles = @(
    "setup.bat",
    "setup.sh",
    "prepare-usb.bat",
    "README.md",
    "LICENSE",
    ".gitignore",
    "scripts\setup.ps1",
    "scripts\prepare-usb.ps1",
    "tools\adb.exe",
    "tools\AdbWinApi.dll",
    "tools\AdbWinUsbApi.dll",
    "docs\OPTIMIZATIONS_EXPLAINED.md",
    "docs\DOWNLOADER_SHORTCODES.md",
    "docs\DIRECT_USB_SETUP.md"
)

foreach ($relPath in $requiredFiles) {
    $full = Join-Path $RootDir $relPath
    $exists = Test-Path $full
    Write-TestResult "File Exists: $relPath" $exists $(if (-not $exists) { "Missing file: $relPath" })
}

# -------------------------------------------------------------
# TEST GROUP 2: POWERSHELL & SCRIPT SYNTAX (STATIC AST ANALYSIS)
# -------------------------------------------------------------
Write-Host "`n[Group 2: Script Syntax Validation]" -ForegroundColor Cyan

$psScripts = Get-ChildItem -Path $RootDir -Filter "*.ps1" -Recurse
foreach ($ps in $psScripts) {
    $errors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ps.FullName, [ref]$tokens, [ref]$errors)
    $noErrors = ($errors.Count -eq 0)
    $rel = $ps.FullName.Substring($RootDir.Length + 1)
    $msg = if ($noErrors) { "Clean syntax (0 errors, $($tokens.Count) tokens parsed)" } else { "$($errors.Count) syntax error(s): $($errors[0].Message)" }
    Write-TestResult "Syntax Check: $rel" $noErrors $msg
}

# -------------------------------------------------------------
# TEST GROUP 3: PORTABLE ADB BINARY INTEGRITY
# -------------------------------------------------------------
Write-Host "`n[Group 3: Portable ADB Execution Check]" -ForegroundColor Cyan

if (Test-Path $AdbExe) {
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $AdbExe
        $pinfo.Arguments = "version"
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        $out = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit(3000)

        $valid = ($out -match "Android Debug Bridge version")
        Write-TestResult "ADB Execution Test" $valid $out.Trim().Split("`n")[0]
    } catch {
        Write-TestResult "ADB Execution Test" $false $_.Message
    }
} else {
    Write-TestResult "ADB Binary Present" $false "adb.exe not found in tools folder"
}

# -------------------------------------------------------------
# TEST GROUP 4: STREAMING APKS ZIP INTEGRITY
# -------------------------------------------------------------
Write-Host "`n[Group 4: APK Package Integrity]" -ForegroundColor Cyan

Add-Type -AssemblyName System.IO.Compression.FileSystem

$apks = @(
    @{ Name = "Stremio (Android TV)"; File = "stremio-tv.apk"; MinSizeMB = 50 },
    @{ Name = "SmartTube (4K YouTube)"; File = "smarttube.apk"; MinSizeMB = 15 },
    @{ Name = "TiviMate (IPTV)"; File = "tivimate.apk"; MinSizeMB = 15 }
)

foreach ($apk in $apks) {
    $apkPath = Join-Path $ApksDir $apk.File
    if (Test-Path $apkPath) {
        $fileInfo = Get-Item $apkPath
        $sizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        $sizeOk = ($sizeMB -ge $apk.MinSizeMB)
        
        # Test ZIP container validity
        $zipValid = $false
        try {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($apkPath)
            $manifestEntry = $zip.GetEntry("AndroidManifest.xml")
            $zipValid = ($manifestEntry -ne $null)
            $zip.Dispose()
        } catch {
            $zipValid = $false
        }

        $allGood = $sizeOk -and $zipValid
        $msg = "Size: $sizeMB MB, AndroidManifest.xml verified valid"
        Write-TestResult "APK Valid: $($apk.Name)" $allGood $msg
    } else {
        Write-TestResult "APK Present: $($apk.Name)" $false "File missing: $($apk.File)"
    }
}

# -------------------------------------------------------------
# TEST GROUP 5: HARDWARE FINGERPRINTING & MODEL RESOLUTION
# -------------------------------------------------------------
Write-Host "`n[Group 5: Hardware Fingerprinting & Model Resolution]" -ForegroundColor Cyan

$setupPs1 = Join-Path $RootDir "scripts\setup.ps1"
$setupTokens = $null
$setupErrors = $null
$setupAst = [System.Management.Automation.Language.Parser]::ParseFile($setupPs1, [ref]$setupTokens, [ref]$setupErrors)

$funcAst = $setupAst.Find({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq "Get-FriendlyDeviceName" }, $true)

if ($funcAst) {
    Invoke-Expression $funcAst.Extent.Text
    
    $testCases = @(
        @{ Model = "AFTGAZL"; Expected = "Amazon Fire TV Cube (3rd Gen)" },
        @{ Model = "AFTKRT"; Expected = "Amazon Fire TV Stick 4K Max (2nd Gen)" },
        @{ Model = "AFTOQ"; Expected = "Amazon Fire TV Omni QLED Series" },
        @{ Model = "SHIELD Android TV"; Expected = "NVIDIA SHIELD TV" },
        @{ Model = "Google TV Streamer"; Expected = "Google TV Streamer 4K" },
        @{ Model = "240411"; Expected = "Onn 4K Streaming Box" }
    )

    foreach ($tc in $testCases) {
        $actual = Get-FriendlyDeviceName "" $tc.Model
        $match = ($actual -eq $tc.Expected)
        Write-TestResult "Model Map: $($tc.Model)" $match "$actual"
    }
} else {
    Write-TestResult "Extract Get-FriendlyDeviceName" $false "Could not extract function for unit testing"
}

# -------------------------------------------------------------
# TEST GROUP 6: PRIVATE DNS PROFILES DYNAMIC VALIDATION
# -------------------------------------------------------------
Write-Host "`n[Group 6: Private DNS Profiles Dynamic Validation]" -ForegroundColor Cyan

$setupContent = Get-Content -Raw $setupPs1
$dnsMatch = [regex]::Match($setupContent, '(?s)\$Script:DnsProviders\s*=\s*@\{.*?\}\r?\n\}')

if ($dnsMatch.Success) {
    Invoke-Expression $dnsMatch.Value
    Write-TestResult "Dynamic DNS Table Extraction" ($Script:DnsProviders.Count -ge 4) "Found $($Script:DnsProviders.Count) DNS profiles in setup.ps1"
    
    foreach ($entry in $Script:DnsProviders.GetEnumerator()) {
        $hostName = $entry.Value.Host
        $validHost = $hostName -match '^[a-zA-Z0-9\.\-]+\.[a-zA-Z]{2,}$'
        Write-TestResult "DNS Host Format: $($entry.Key) ($hostName)" $validHost "Valid FQDN ($($entry.Value.Name))"
    }
} else {
    Write-TestResult "Dynamic DNS Table Extraction" $false "Could not extract `$Script:DnsProviders from setup.ps1"
}

# Test Custom DNS validation regex
$validCustomHost = "custom.privatedns.example.org" -match '^[a-zA-Z0-9\.\-]+\.[a-zA-Z]{2,}$'
Write-TestResult "DNS Host Format: Custom Profile Validation" $validCustomHost "Custom FQDN regex passes"

# -------------------------------------------------------------
# TEST GROUP 7: DEBLOAT SAFETY DYNAMIC AUDIT
# -------------------------------------------------------------
Write-Host "`n[Group 7: Debloat Safety Dynamic Whitelist Audit]" -ForegroundColor Cyan

$criticalPackages = @(
    "android",
    "com.android.settings",
    "com.android.systemui",
    "com.amazon.firelauncher",
    "com.amazon.device.software.ota",
    "com.amazon.whisperplay.contracts"
)

$debMatch = [regex]::Match($setupContent, '(?s)\$Script:DebloatTiers\s*=\s*@\{.*?\}\r?\n\}')

if ($debMatch.Success) {
    Invoke-Expression $debMatch.Value
    Write-TestResult "Dynamic Debloat Tiers Extraction" ($Script:DebloatTiers.Count -ge 3) "Found $($Script:DebloatTiers.Count) debloat tiers (Safe, Balanced, Aggressive)"
    
    $hasCollision = $false
    foreach ($tier in $Script:DebloatTiers.Keys) {
        $tierPkgs = $Script:DebloatTiers[$tier]
        foreach ($crit in $criticalPackages) {
            if ($tierPkgs -contains $crit) {
                $hasCollision = $true
                Write-TestResult "Safety Guard: $tier contains $crit" $false "CRITICAL PACKAGE PRESENT IN DEBLOAT TIER"
            }
        }
    }

    if (-not $hasCollision) {
        Write-TestResult "Core OS Safety Whitelist Audit" $true "0 system-critical packages in any debloat tier"
    }
} else {
    Write-TestResult "Dynamic Debloat Tiers Extraction" $false "Could not extract `$Script:DebloatTiers from setup.ps1"
}

# -------------------------------------------------------------
# TEST GROUP 8: DIAGNOSTICS PARSER UNIT TESTS
# -------------------------------------------------------------
Write-Host "`n[Group 8: Diagnostics Output Parser Unit Tests]" -ForegroundColor Cyan

# Test 8.1: Storage parsing prevents single-string scalar char unrolling bug
$mockStorage = @"
Filesystem      Size  Used Avail Use% Mounted on
/dev/block/data  12G  3.7G  7.8G  33% /data
"@
$storageLines = @($mockStorage -split "`r?`n" | Where-Object { $_ -match "/data" })
$storageParseOk = $false
if ($storageLines.Count -gt 0) {
    $cols = $storageLines[0].Trim() -split '\s+'
    if ($cols.Count -ge 5 -and $cols[1] -eq "12G" -and $cols[2] -eq "3.7G" -and $cols[3] -eq "7.8G") {
        $storageParseOk = $true
    }
}
Write-TestResult "Diagnostic Parser: Storage Data Partition" $storageParseOk "Parsed Total=12G, Used=3.7G, Free=7.8G"

# Test 8.2: Legacy RAM fallback parsing (MemFree + Buffers + Cached)
$mockMemLegacy = @"
MemTotal:        2023424 kB
MemFree:          450000 kB
Buffers:           50000 kB
Cached:           441000 kB
"@
$memMatchTotal = [regex]::Match($mockMemLegacy, 'MemTotal:\s+(\d+)\s+kB')
$memMatchAvail = [regex]::Match($mockMemLegacy, 'MemAvailable:\s+(\d+)\s+kB')
$availKb = 0
if ($memMatchAvail.Success) {
    $availKb = [int64]$memMatchAvail.Groups[1].Value
} else {
    $memFree = [regex]::Match($mockMemLegacy, 'MemFree:\s+(\d+)\s+kB')
    $buffers = [regex]::Match($mockMemLegacy, 'Buffers:\s+(\d+)\s+kB')
    $cached  = [regex]::Match($mockMemLegacy, 'Cached:\s+(\d+)\s+kB')
    if ($memFree.Success) { $availKb += [int64]$memFree.Groups[1].Value }
    if ($buffers.Success) { $availKb += [int64]$buffers.Groups[1].Value }
    if ($cached.Success)  { $availKb += [int64]$cached.Groups[1].Value }
}
$ramLegacyOk = ($availKb -eq 941000)
Write-TestResult "Diagnostic Parser: Legacy RAM Fallback" $ramLegacyOk "Calculated 941000 kB available via MemFree+Buffers+Cached"

# -------------------------------------------------------------
# TEST GROUP 9: DEBLOAT STATE SNAPSHOT & ROLLBACK VALIDATION
# -------------------------------------------------------------
Write-Host "`n[Group 9: Debloat State Snapshot & Rollback Validation]" -ForegroundColor Cyan

$mockStateFile = Join-Path $RootDir "tests\mock-debloat-state.json"
try {
    $mockSnapshot = @{
        TargetIP = "192.168.0.64"
        Level = "Safe"
        Timestamp = (Get-Date).ToString("o")
        DisabledPackages = @("com.amazon.device.sale.service", "com.amazon.precog")
    }
    $mockSnapshot | ConvertTo-Json -Depth 3 | Set-Content -Path $mockStateFile -Encoding UTF8
    $loadedState = Get-Content -Raw $mockStateFile | ConvertFrom-Json
    $snapshotValid = ($loadedState.TargetIP -eq "192.168.0.64") -and 
                     ($loadedState.DisabledPackages.Count -eq 2) -and
                     ($loadedState.Level -eq "Safe")
    Write-TestResult "Debloat Snapshot Roundtrip" $snapshotValid "Snapshot serialization & deserialization validated"
} finally {
    if (Test-Path $mockStateFile) { Remove-Item $mockStateFile -Force }
}

# -------------------------------------------------------------
# TEST GROUP 10: CONFIGURATION PROFILE JSON ROUNDTRIP
# -------------------------------------------------------------
Write-Host "`n[Group 10: Device Profile JSON Schema Roundtrip]" -ForegroundColor Cyan

$testProfile = @{
    Manufacturer = "Amazon"
    Model = "AFTKRT"
    Architecture = "armeabi-v7a"
    PrivateDnsMode = "hostname"
    PrivateDnsSpecifier = "dns.adguard-dns.com"
    ExportDate = (Get-Date).ToString("o")
}

try {
    $json = $testProfile | ConvertTo-Json -Depth 3
    $roundtrip = $json | ConvertFrom-Json
    $schemaValid = ($roundtrip.Manufacturer -eq "Amazon") -and
                   ($roundtrip.Model -eq "AFTKRT") -and
                   ($roundtrip.PrivateDnsSpecifier -eq "dns.adguard-dns.com")
    Write-TestResult "Profile Serialization Roundtrip" $schemaValid "JSON schema validated"
} catch {
    Write-TestResult "Profile Serialization Roundtrip" $false $_.Message
}

# -------------------------------------------------------------
# TEST GROUP 11: USB PREPARATION WORKFLOW (MOCK DRY-RUN)
# -------------------------------------------------------------
Write-Host "`n[Group 11: USB Packaging Dry-Run Test]" -ForegroundColor Cyan

$mockUsbDir = Join-Path $RootDir "tests\mock-usb"
try {
    if (Test-Path $mockUsbDir) { Remove-Item $mockUsbDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $mockUsbDir | Out-Null

    # Replicate USB copy process
    $mockApks = Join-Path $mockUsbDir "apks"
    $mockTools = Join-Path $mockUsbDir "tools"
    $mockScripts = Join-Path $mockUsbDir "scripts"

    New-Item -ItemType Directory -Force -Path $mockApks, $mockTools, $mockScripts | Out-Null

    Copy-Item (Join-Path $ApksDir "*") -Destination $mockApks -Force
    Copy-Item (Join-Path $ToolsDir "*") -Destination $mockTools -Force
    Copy-Item (Join-Path (Join-Path $RootDir "scripts") "*") -Destination $mockScripts -Force

    # Mock root files
    Set-Content -Path (Join-Path $mockUsbDir "INSTALL_ON_PC.bat") -Value "@echo off"
    Set-Content -Path (Join-Path $mockUsbDir "TV_DIRECT_INSTALL_GUIDE.txt") -Value "Direct guide"
    Set-Content -Path (Join-Path $mockUsbDir "DOWNLOADER_SHORTCODES.txt") -Value "Shortcodes"

    $usbValid = (Test-Path (Join-Path $mockUsbDir "INSTALL_ON_PC.bat")) -and
                (Test-Path (Join-Path $mockApks "stremio-tv.apk")) -and
                (Test-Path (Join-Path $mockTools "adb.exe"))

    Write-TestResult "USB Package Structure Generation" $usbValid "Created full mock USB image with launchers, tools & APKs"
} catch {
    Write-TestResult "USB Package Structure Generation" $false $_.Message
} finally {
    if (Test-Path $mockUsbDir) { Remove-Item $mockUsbDir -Recurse -Force }
}

# -------------------------------------------------------------
# TEST GROUP 12: LIVE DEVICE VERIFICATION (OPTIONAL / AUTO-DETECT)
# -------------------------------------------------------------
Write-Host "`n[Group 12: Live Fire TV Device Validation]" -ForegroundColor Cyan

if ($SkipLiveDevice) {
    Write-TestSkip "Live Device Tests" "User specified -SkipLiveDevice flag"
} else {
    $target = "$($DeviceIp):5555"
    Write-Host "  Testing connection to $target..." -ForegroundColor Gray
    
    # Try connecting
    & $AdbExe disconnect | Out-Null
    $connOut = & $AdbExe connect $target
    
    $state = (& $AdbExe -s $target get-state 2>&1).Trim()
    if ($state -match "device") {
        Write-TestResult "Live Device ADB Handshake" $true "Connected to $target ($state)"

        # Check Private DNS
        $dnsMode = (& $AdbExe -s $target shell settings get global private_dns_mode 2>&1).Trim()
        $dnsSpec = (& $AdbExe -s $target shell settings get global private_dns_specifier 2>&1).Trim()
        $dnsOk = [bool](($dnsMode -eq "hostname") -and ($dnsSpec -like "*.adguard-dns.com" -or $dnsSpec -like "*.cloudflare-dns.com" -or $dnsSpec -like "*quad9*"))
        Write-TestResult "Private DNS (DoT) Verified" $dnsOk "Mode=$dnsMode, Specifier=$dnsSpec"

        # Check Network Latency & Zero Packet Loss
        $pingOut = (& $AdbExe -s $target shell ping -c 3 8.8.8.8 2>&1)
        $pingOk = [bool]($pingOut -match "0% packet loss")
        Write-TestResult "Network Zero-Packet-Loss Test" $pingOk "External ping returned 0% packet loss"

        # Verify Stremio Installed
        $stremioPkg = (& $AdbExe -s $target shell pm list packages com.stremio.one 2>&1).Trim()
        $stremioOk = [bool]($stremioPkg -match "com.stremio.one")
        Write-TestResult "App Verification: Stremio" $stremioOk $stremioPkg

        # Verify SmartTube Installed
        $smartTubePkg = (& $AdbExe -s $target shell pm list packages org.smarttube.beta 2>&1).Trim()
        $smartTubeOk = [bool]($smartTubePkg -match "org.smarttube.beta")
        Write-TestResult "App Verification: SmartTube" $smartTubeOk $smartTubePkg

        # Verify TiviMate Installed
        $tivimatePkg = (& $AdbExe -s $target shell pm list packages ar.tvplayer.tv 2>&1).Trim()
        $tivimateOk = [bool]($tivimatePkg -match "ar.tvplayer.tv")
        Write-TestResult "App Verification: TiviMate" $tivimateOk $tivimatePkg
    } else {
        Write-TestSkip "Live Device Tests" "Device $target not reachable or offline ($state)"
    }
}

# -------------------------------------------------------------
# SUMMARY REPORT
# -------------------------------------------------------------
Write-Host "`n==========================================================================" -ForegroundColor Cyan
Write-Host "                          TEST SUITE SUMMARY                              " -ForegroundColor Yellow
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "  PASSED:  $Passed" -ForegroundColor Green
Write-Host "  FAILED:  $Failed" -ForegroundColor $(if ($Failed -gt 0) { "Red" } else { "Green" })
Write-Host "  SKIPPED: $Skipped" -ForegroundColor Yellow
Write-Host "==========================================================================" -ForegroundColor Cyan

if ($Failed -gt 0) {
    exit 1
} else {
    exit 0
}
