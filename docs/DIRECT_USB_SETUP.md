# Direct USB Drive Setup Guide (Fire TV Cube & OTG Cables)

This guide covers how to use the physical USB drive when plugged directly into a Fire TV device.

---

## Hardware Requirements
* **Fire TV Cube (2nd or 3rd Gen):** Has a built-in micro-USB or full-size USB port on the back.
* **Fire TV Stick (Lite, 4K, 4K Max):** Requires an inexpensive **Micro-USB OTG Y-Cable** (plugs between your power cable and the Fire Stick to provide a standard USB-A port).
* **Format:** USB thumb drive formatted as **FAT32** (Fire OS does not support NTFS or exFAT natively).

---

## Step 1: Prepare the USB Drive
On your Windows PC:
1. Insert your USB thumb drive.
2. Double-click `prepare-usb.bat` in this repository.
3. Choose your USB drive letter (e.g., `E:`). The script will automatically format and copy:
   * All three APKs (`stremio-tv.apk`, `smarttube.apk`, `tivimate.apk`) into `E:\apks\`.
   * Portable ADB tools into `E:\tools\`.
   * Automation scripts and documentation into `E:\scripts\`.

---

## Step 2: Plug USB Drive into Fire TV
1. Insert the prepared USB drive into your Fire TV Cube's USB port or your Fire Stick's OTG cable.
2. A prompt may appear on screen: *"USB drive detected"*.

---

## Step 3: Install the Apps
1. Open any File Manager on your Fire TV (e.g., **Downloader**, **Total Commander**, or **CX File Explorer** from the Amazon Appstore).
2. Open the USB storage root and go to the `apks` folder.
3. Click and install each app:
   1. `stremio-tv.apk`
   2. `smarttube.apk`
   3. `tivimate.apk`

---

## Pro Tip: Wi-Fi Setup via USB Drive (Zero Remote Typing)
Even if you carry this USB drive with you, the fastest way to set up any TV is:
1. Plug the USB drive into **any PC or laptop** connected to the same home Wi-Fi as the TV.
2. Open the drive and double-click `INSTALL_ON_PC.bat`.
3. The script will automatically discover the Fire TV over Wi-Fi, install all 3 apps, configure AdGuard Private DNS, debloat telemetry, and tune Stremio in 30 seconds without pressing a single button on the remote!
