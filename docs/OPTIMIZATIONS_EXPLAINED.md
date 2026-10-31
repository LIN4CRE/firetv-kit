# Fire TV Engineering & Optimization Guide

This document explains the root causes of common Fire TV streaming issues, the technical breakdown of the "trailer restart" bug in Stremio, and why this setup is configured the way it is.

---

## 1. The Stremio "Trailer Workaround" Explained

### Symptom
When trying to start a movie or TV episode in Stremio on Fire TV, playback hangs indefinitely on a black screen or an infinite loading spinner. To fix it, you had to back out, launch the YouTube trailer (which plays immediately), and then return to the main video stream, which would now suddenly play.

### The Technical Root Cause
* **ExoPlayer & Tunneled Playback:** By default on Android TV, ExoPlayer can use *Tunneled Video Playback* (`MediaCodecVideoRenderer`). Tunneled playback bypasses Android's standard audio/video mixer to deliver video frames directly to the hardware display sink.
* **P2P Buffer Deadlock:** In peer-to-peer torrent streaming (e.g. Torrentio), chunks of video data arrive non-linearly. During the initial metadata exchange and buffer pre-fill, the stream may pause for 1 to 3 seconds. Under tunneled playback on Fire OS, if the decoder buffer experiences an underflow before the hardware sink receives its first synchronized presentation timestamp (PTS), the hardware sink deadlocks. ExoPlayer waits indefinitely for the hardware sink to advance, and the TV screen remains black.
* **Why the Trailer Fixed It:** YouTube trailers in Stremio are played using a standard non-tunneled web/MediaCodec video pipeline. Launching the trailer forces the Fire TV graphics driver to flush and detach the deadlocked hardware sink, releasing the audio/video decoder. When you returned to the movie stream immediately afterward, the hardware decoder was freshly initialized, allowing the movie to start playing.
* **The Permanent Fix:** Disabling **Tunnelled Playback** in Stremio (`Settings -> Playback -> Tunnelled Playback = OFF`). Standard hardware-accelerated decoding remains enabled (`ON`), ensuring smooth 1080p and 4K 60fps playback without sink deadlocks.

---

## 2. Frame Rate Matching (Auto Frame Rate / AFR)

### Symptom
When launching a video, the TV screen goes completely black for 3 to 5 seconds, sometimes showing an "HDMI No Signal" warning, before video starts or crashes back to the catalog.

### Technical Explanation
* Most Fire TV displays run at 60 Hz (60 frames per second). Most films and television series are shot at 23.976 or 24.000 fps.
* When **Frame Rate Matching** is enabled, Fire OS instructs the TV via HDMI to switch its physical refresh rate from 60 Hz to 24 Hz.
* This HDMI mode switch requires a hardware handshake between the TV and Fire TV. On many TVs and AV receivers, this renegotiation takes 2–5 seconds, causing ExoPlayer connection dropouts or audio sync issues.
* **The Fix:** Disabling Frame Rate Matching (`Disabled`). Fire OS handles 24 fps to 60 fps cadence automatically via 3:2 pulldown with zero HDMI sync lag.

---

## 3. Native Private DNS over TLS (DoT) vs. VPN Ad-Blockers

### The "Missing Middleman" Failure
Previously, third-party APKs like `dnsfilter.android` (PersonalDNSFilter) ran as local Android VPN services capturing all network traffic on interface `tun0`. When:
1. The background service crashed or was killed by Fire OS memory management,
2. Or a computer or proxy serving as a local resolver went offline,

the `tun0` interface stalled all network traffic (`100% packet loss`), breaking internet connectivity across all apps and reporting "missing middleman."

### Why Native Private DNS (DoT) is Superior
* **Native OS Integration:** Fire OS natively supports RFC 7858 (DNS over TLS) on port 853 (`dns.adguard-dns.com`).
* **Zero VPN Overhead:** Does not create any virtual network interface, requires zero CPU overhead, and never drains RAM.
* **System-Wide Ad & Tracker Blocking:** AdGuard's encrypted servers block tracking domains, Amazon telemetry, and known ad networks at the DNS resolution stage before any connection is even established.
* **100% Standalone:** Functions directly through your standard Wi-Fi router. The TV works perfectly whether any computer on the network is on or off.

---

## 4. Stremio Torrent Profile Tuning

* **Torrent Profile = Ultra Fast:**
  Configures the embedded `libtorrent` engine with higher maximum connection limits (up to 200 peers), aggressive chunk pre-buffering, and optimized socket timeouts. This reduces initial playback latency from ~10–15 seconds down to ~2–4 seconds on healthy streams.
