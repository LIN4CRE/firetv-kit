# Contributing to Fire TV Ultimate Setup Kit

Thank you for your interest in improving the **Fire TV Ultimate Setup Kit**!

## Development Guidelines

1. **Testing:** Before submitting changes, always run the automated test suite locally:
   ```powershell
   .\tests\Run-Tests.ps1 -DeviceIp <your-fire-tv-ip>
   # Or offline:
   .\tests\Run-Tests.ps1 -SkipLiveDevice
   ```
2. **Compatibility:** Ensure scripts maintain compatibility with:
   * Windows PowerShell 5.1 and PowerShell 7+
   * macOS / Linux Bash (via `setup.sh`)
   * Android TV 9+ / Fire OS 6, 7, and 8
3. **No VPN Overrides:** We enforce native Private DNS over TLS (`dns.adguard-dns.com` over port 853) instead of local VPN interceptors (`dnsfilter.android`), ensuring 100% standalone operation with zero CPU overhead and zero packet stalls.
4. **Decoder Safety:** Keep ExoPlayer *Tunnelled Playback* and *Frame Rate Matching* disabled in Stremio configs to prevent hardware sink deadlocks.
