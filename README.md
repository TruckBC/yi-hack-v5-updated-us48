<p align="center">
    <img height="200" src="https://raw.githubusercontent.com/alienatedsec/yi-hack-v5/master/imgs/yi-hack-v5-header.png">
</p>
<p align="center">
    <a target="_blank" href="https://discord.gg/bsKncwvRU7">
        <img src="https://img.shields.io/discord/825822449449828414?logo=discord" alt="Official Discord Server">
    </a>
    <a target="_blank" href="https://github.com/alienatedsec/yi-hack-v5/releases">
        <img src="https://img.shields.io/github/downloads/alienatedsec/yi-hack-v5/total.svg" alt="Releases Downloads">
    </a>
</p>

## 48US Frigate fork (`yi-hack-v5-updated-us48`)

This is a patched fork of [`alienatedsec/yi-hack-v5`](https://github.com/alienatedsec/yi-hack-v5) `0.4.1`, targeting the **2018 YI 1080p Home Camera (`48US`, `yi_home_1080p` / `y20`, Hi3518e V200)** and optimized for **Frigate NVR**:

- **No `wpa_supplicant` upgrade / reboot loop** — the 0.4.1 `wpa/` upgrade routine is removed and the flag file is neutralized; `wpa/` is excluded from the packaged archive.
- **Clean WPA2-PSK (RSN/CCMP) `wpa_supplicant.conf`** — the stock dual WPA-PSK + WEP config crashes the `mt7601Usta` USB Wi-Fi module (`wpa may crashed, now reset` → `no usb dev`); it is rewritten at boot from the credentials in `mtdblock2`.
- **CRLF-safe Wi-Fi recovery** — `/tmp/sd/recover/configure_wifi.cfg` is parsed with `tr -d '\r'` so Windows-edited configs don't corrupt SSID/PSK.
- **Watchdog & cron fixes** (ported from `Temporalwar/yi-hack-v5-updated`): `wd_rtsp.sh` port-variable fix so locked `rRTSPServer` processes are restarted, `>>` (append) instead of `>` for all crontab writes, `camera_settings.sh` persistence via `sed -i`, CGI `VAR = "x"` spacing/syntax fixes, `setsid` detachment for `onvif_simple_server`, and `rRTSPServer` now starts in *all* RTSP stream modes (previously only `both`).
- **Frigate-ready defaults** — single high-res RTSP stream (`ch0_0.h264`), audio disabled, cloud disabled, MQTT off, on-camera AI/motion detection off, swap enabled (swappiness 15), timezone PST8PDT.

- **Hardened RTSP server + watchdog fixes (2026-11-16)**: `rRTSPServer` is the WaveBird hardened build (survives mid-stream keepalives → go2rtc can use plain TCP again); `wd_rtsp.sh` resolves the `rRTSPServer.hardened` name for `pidof`/`killall`, the inverted `DISABLE_CLOUD` logic no longer respawns `./cloud` every 15 s when cloud is disabled, and `check_rmm` needs **3 consecutive** `pidof rmm` misses before calling `reboot` (a single missed `ps` scan under load was rebooting the camera spontaneously).

### ⚠️ go2rtc / Frigate transport

With the hardened `rRTSPServer`, plain TCP (`rtsp://192.168.2.203:554/ch0_0.h264`, no suffix) is now recommended. The notes below apply to the *stock* server only.

### ⚠️ Wi-Fi stability warning (mt7601 USB driver)

The `mt7601Usta` USB Wi-Fi module on this camera stalls under load (observed 4–15 s TX freezes) and, when the camera has been up a while under streaming load, the stalls can degrade **the whole 2.4 GHz network**, not just the camera. This matches WaveBird's findings in the upstream rtsp-enhanced fork (`wlan0` stalls are unfixable in userspace). If the camera is unreliable over Wi-Fi, the proven fix is **wired ethernet** (or a different Wi-Fi adapter).

The stock `rRTSPServer` (LIVE555 v2023.01.19) has a verified bug on this camera: **any RTSP request that arrives mid-stream (`GET_PARAMETER` keepalive, `OPTIONS`, …) permanently stops RTP data for that session** — new clients keep working, the affected one goes silent until it reconnects (and dies again at its next keepalive ~30 s later). Interleaved-TCP sessions are the ones that starve; UDP sessions are immune.

For go2rtc ≥ 1.9.11, add `#transport=udp` to the camera source:

```yaml
streams:
  yi_cam: rtsp://192.168.2.203:554/ch0_0.h264#transport=udp
```

go2rtc/Frigate can still consume the restream over TCP. (go2rtc needs to receive the inbound UDP — use `network_mode: host` in Docker, or a non-containerized install.) For older go2rtc, use `ffmpeg:rtsp://…#input=rtsp/udp` instead.

The GitHub Action (`.github/workflows/build.yml`) repacks the upstream `0.4.1` `yi_home_1080p` firmware image with these patched userland files and publishes `yi_home_1080p_0.4.1-48us-frigate.tgz`.

---

## Why this `YI-HACK-V5` firmware?

The answer is simple: missing updates, RTSP, and not based on the latest stock firmware (which features improvements and new cool stuff).
Besides, there were no updates to `yi-hack-v4`, and I am against that RTSP licensing model. I have contributed enough and will continue my work separately.

I am slowly working on pre-release versions, and I can see lots of downloads, testing and contributions. A big thank you to the community.

## Table of Contents

- [Features](#features)
- [Supported cameras](#supported-cameras)
- [Getting started](#getting-started)
- [Unbrick your camera](#unbrick-your-camera)
- [Acknowledgments](#acknowledgments)
- [Disclaimer](#disclaimer)
- [Donations](#donations)

## Features
This firmware will add the following features:

- **NEW FEATURES**
  - **NEW CAMERAS SUPPORTED**: Yi Outdoor 1080p and Yi Cloud Dome 1080p.
  - **RTSP server** - which will allow an RTSP stream of the video while keeping the cloud features enabled (available to all and it is free).
  - **MQTT** - detect motion directly from your home server!
  - WebServer - user-friendly stats and configurations.
  - SSH server -  _Enabled by default._
  - Telnet server -  _Disabled by default._
  - FTP server -  _Enabled by default._
  - Web server -  _Enabled by default._
  - The possibility to change some camera settings (copied from the official app):
    - camera on/off
    - video saving mode
    - detection sensitivity
    - status led
    - ir led
    - rotate
  - PTZ support through a web page.
  - Snapshot feature
  - Proxychains-ng - _Disabled by default. Useful if the camera is region-locked._
  - The possibility to disable all the cloud features while keeping the RTSP stream.

## Supported cameras

Currently, this project supports the following cameras:

- Yi 1080p Home 48US - confirmed
- Yi 1080p Home 20US - confirmed
- Yi Home 17CN / 27US / 47US - confirmed
- Yi Dome - confirmed, but heavy performance issues with Snapshot and ONVIF are killing the CPU
- Yi 1080p Dome - confirmed; however, I have no device to test
- Yi 1080p Cloud Dome - confirmed; however, I have no device to test
- Yi 1080p Outdoor - confirmed; however, I have no device to test

## Getting Started
1. Check that you have a correct Xiaomi Yi camera. (see the section above)

2. Get a microSD card, preferably of capacity 16 GB or less and format it by selecting File System as FAT32.

**_IMPORTANT: The microSD card must be formatted in FAT32. exFAT formatted microSD cards will not work._**
**I have not formatted any of my 32GB cards to load the firmware. Just copy files directly and it should work.**

<details><summary> (Click) How to format microSD cards > 32GB as FAT32 in Windows 10</summary><p>

For microSD cards larger than 32 GB, Windows 10 only gives you the option to format as NTFS or exFAT. You can create a small partition (e.g. 4 GB) on a large microSD card (e.g. 64 GB) to get the FAT32 formatting option.

* insert microSD card into PC card reader
* open Disk Management (e.g. <kbd>Win</kbd>+<kbd>x</kbd>, <kbd>k</kbd>)
  * Disk Management: delete all partitions on the microSD card
    * right click each partition > "Delete Volume..."
    * repeat until there are no partitions on the card
  * Disk Management: create a new FAT32 partition
    * Right-click on "Unallocated" > "New Simple Volume..."
    * Welcome to the New Simple Volume Wizard: click "Next"
    * Specify Volume Size: 4096 > "Next"
    * Assign Drive Letter or Path: (Any) > "Next"
    * Format Partition: Format this volume with the following settings:
      * File system: FAT32
      * Allocation unit size: Default
      * Volume label: Something
      * Perform a quick format: &#9745;

You should now have a FAT32 partition on your microSD card that will allow the camera to load the firmware files to update to `yi-hack-v5`.

### Example: 4 GB FAT32 partition on 64 GB microSD card

![example: 4 GB FAT32 on 64 GB](imgs/4gb-fat32-on-64gb-card.png)

Alternative way:
* open cmd with admin permissions
* run diskpart
* type "list disk"
* find your SD card (for example Disk 7)
* type "select disk 7"
* if it has one partition - type "select partition 1". If more - delete all the partitions and then create one
* type "format FS=FAT32 QUICK"
* done. 32GB partition in FAT32.

</p></details>

3. Get the correct firmware files for your camera from the latest baseline release link: https://github.com/alienatedsec/yi-hack-v5/releases/tag/0.4.1

| Camera | rootfs partition | home partition | Remarks |
| --- | --- | --- | --- |
| **Yi Home 17CN / 27US / 47US** | rootfs_y18 | home_y18 | Firmware files required for the Yi Home 17CN / 27US / 47US camera. |
| **Yi 1080p Home** | rootfs_y20 | home_y20 | Firmware files required for the Yi 1080p Home camera. |
| **Yi Dome** | rootfs_v201 | home_v201 | Firmware files required for the Yi Dome camera. |
| **Yi 1080p Dome** | rootfs_h20 | home_h20 | Firmware files required for the Yi 1080p Dome camera. |
| **Yi 1080p Cloud Dome** | rootfs_y19 | home_y19 | Firmware files required for the Yi 1080p Cloud Dome camera. |
| **Yi Outdoor** | rootfs_h30 | home_h30 | Firmware files required for the Yi Outdoor camera. |

4. Save both files (rootfs_xx and home_xx), and the `yi-hack-v5` folder on the root path of the microSD card.

**_IMPORTANT: Make sure that the filenames stored on the microSD card are correct and didn't get changed. e.g. The firmware filenames for the Yi 1080p Dome camera must be home_h20 and rootfs_h20._**

5. Remove power to the camera, insert the microSD card, and turn the power back ON.

6. The yellow light will come ON and flash for roughly 30 seconds, which means the firmware is being flashed successfully. The camera will boot up.

7. The yellow light will come ON again for the final stage of flashing. This will take up to 2 minutes.

8. Blue light should come ON indicating that your WiFi connection has been successful.

9. Go into the browser and access the web interface of the camera as a website.

Depending upon your network setup, accessing the web interface with the hostname **may not work**. In this case, the IP address of the camera has to be found.

This can be done from the App. Please open the app, and go to the Camera Settings --> Network Info --> IP Address.

Access the web interface by entering the IP address of the camera in a web browser. e.g. `http://192.168.1.5`

**_IMPORTANT: If you have multiple cameras. It is important to configure each camera with a unique hostname. Otherwise, the web interface will only be accessible by IP address._**

10. Done! You are now successfully running yi-hack-v5!

## Unbrick your camera
_TO DO - (It happened a few times and it's often possible to recover from it)_

## Troubleshooting

### Wi-Fi is connected, and the camera responds to ping but I'm not able to connect to the web interface
Verify that you did not forget to upload the `yi-hack-v5` folder to the SD card when uploading firmware. If you did, upload it and restart the camera.

### Cannot complete the pairing/wifi settings lost after reboot
Ensure you are using the correct app (Yi Home) to set up the wifi connection. For example, the "Xiaomi Home" app will also generate the correct QR code that will work with your camera for the initial connection, but then after power is removed
the settings will be lost.

## Introducing pre-releases
Please follow this [guide](https://github.com/alienatedsec/yi-hack-v5/discussions/248#discussion-5090628) if you want to test new features and improvements

## Acknowledgments
Special thanks to the following people and projects, without them `yi-hack-v5` wouldn't be possible.
- @TheCrypt0 - [https://github.com/TheCrypt0/yi-hack-v4](https://github.com/TheCrypt0/yi-hack-v4)
- @shadow-1 - [https://github.com/shadow-1/yi-hack-v3](https://github.com/shadow-1/yi-hack-v3)
- @fritz-smh - [https://github.com/fritz-smh/yi-hack](https://github.com/fritz-smh/yi-hack)
- @niclet  - [https://github.com/niclet/yi-hack-v2](https://github.com/niclet/yi-hack-v2)
- @xmflsct -  [https://github.com/xmflsct/yi-hack-1080p](https://github.com/xmflsct/yi-hack-1080p)
- @dvv - [Ideas for the RSTP stream](https://github.com/shadow-1/yi-hack-v3/issues/126)
- @andy2301 - [Ideas for the RSTP rtsp and rtsp2301](https://github.com/xmflsct/yi-hack-1080p/issues/5#issuecomment-294326131)
- @roleoroleo - [PTZ Implementation](https://github.com/roleoroleo/yi-hack-MStar)

## Acknowledgments #2
As much as TheCrypt0 has made it possible for the 'yi-hack-v4', the latest features are based on the work from:
- @roleoroleo - [https://github.com/roleoroleo](https://github.com/roleoroleo)

---
### DISCLAIMER
**I AM NOT RESPONSIBLE FOR ANY USE OR DAMAGE THIS SOFTWARE MAY CAUSE. THIS IS INTENDED FOR EDUCATIONAL PURPOSES ONLY. USE AT YOUR OWN RISK.**
---
### DONATIONS
**I HAVE BEEN ASKED FOR A LINK MULTIPLE TIMES; THEREFORE, PLEASE FOLLOW THE BELOW**
---
[![paypal](https://www.paypalobjects.com/en_US/GB/i/btn/btn_donateCC_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=K3V4PSH2CV9AA)
