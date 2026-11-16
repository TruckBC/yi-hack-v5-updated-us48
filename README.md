# yi-hack-v5-updated-us48

A patched fork of [`alienatedsec/yi-hack-v5`](https://github.com/alienatedsec/yi-hack-v5) `0.4.1`, targeting the **2018 YI 1080p Home Camera (US/48US variant, `yi_home_1080p` / hardware `y20`, Hi3518e V200)** and tuned for **Frigate NVR**.

## ⚠️ Tested hardware

**All modifications in this fork have only been tested on the `48US` `yi_home_1080p` (y20) camera.** The CI build produces a package only for that model. Other YI models listed by upstream are *not* tested here and may not work — use upstream directly for anything else.

Two cameras ran this fork through the full test matrix (idle, TCP streaming with mid-stream keepalives, Frigate soak): both stable.

## What this fork changes

Base: upstream `0.4.1`, repacked by GitHub Actions (`.github/workflows/build.yml`) — no local toolchain needed.

### Streaming (the big one)
- **`rRTSPServer` is the WaveBird hardened build** ([`yi-hack-v5-rtsp-enhanced`](https://github.com/WaveBird/yi-hack-v5-rtsp-enhanced), GPL, md5 `9e3ad7d291d709566f96f01a89d31bed`). The stock LIVE555 v2023.01.19 server has a verified bug on this camera: **any mid-stream RTSP request** (`GET_PARAMETER` keepalive, `OPTIONS`) **permanently kills RTP for that session** (reproduced: 217 KB delivered → 0 KB after the keepalive; stream dies ~30 s in). The hardened build survives keepalives and also fixes their documented IDR-truncation (smearing/artifact) root cause.
- go2rtc/Frigate can use **plain TCP**: `rtsp://<camera>:554/ch0_0.h264` — no `#transport=udp` hack needed.
- On-camera A/B verification: stock server died at 1.8 MB streamed; hardened delivered 14.9–18.5 MB continuously through three keepalives.

### Watchdog / stability
- `wd_rtsp.sh` fixes:
  - Recognizes and uses the hardened `rRTSPServer` binary (name resolution for `pidof`/`killall`).
  - CPU-delta lock detection reading `/proc` directly (a stalled LIVE555 delivering 0 bytes consumes no CPU).
  - **Fixed inverted `DISABLE_CLOUD` logic** — upstream respawned `./cloud` every 15 s *only when cloud was disabled*, spamming thousands of failed spawns.
  - **`check_rmm` no longer reboots the camera on a single missed `ps` scan** — it requires 3 consecutive misses. One flapped scan under load was causing spontaneous reboots.
- Boot (`system.sh`): `wpa/` upgrade reboot-loop removed, clean WPA2-PSK-only `wpa_supplicant.conf` rewritten at boot (the stock WPA+WEP config crashes the `mt7601Usta` module), CRLF-safe Wi-Fi recovery parsing, `rRTSPServer` starts in all RTSP modes, empty-credential `-u/-w` args omitted.
- Misc (ported from `Temporalwar/yi-hack-v5-updated`): append-mode crontab writes, `camera_settings.sh` persistence, CGI syntax fixes, `setsid` for `onvif_simple_server`.

### Frigate-ready defaults
Single high-res RTSP stream (`ch0_0.h264`), audio off, cloud off, MQTT off, on-camera AI/motion off, swap on (swappiness 15).

## Installing

1. Download `yi_home_1080p_0.4.1-48us-frigate.tgz` from the [`latest` release](../../releases/tag/latest).
2. Format a microSD card FAT32 (≤32 GB, or a small FAT32 partition on a larger card).
3. Extract the archive onto the card root — you should end up with a `yi_home_1080p/` folder.
4. Power off, insert the card, power on.
   - **Fresh install:** the camera flashes `rootfs_y20`/`home_y20` (yellow light phases) and boots.
   - **Already running yi-hack-v5 (any version):** verified working — at boot the staged `fw_upgrade_in_progress` marker makes the running system copy the new tree over the SD install and reboot once more. Takes 2–3 minutes; SSH/web UI return on the same IP.
5. Web UI at `http://<camera-ip>`, SSH `root` with the password you set (empty by default).

## Frigate / go2rtc config

```yaml
# go2rtc.yaml
streams:
  yi_203: rtsp://192.168.2.203:554/ch0_0.h264

# frigate.yaml
cameras:
  yi_203:
    ffmpeg:
      output_args:
        record: preset record generic
      inputs:
        - path: rtsp://127.0.0.1:8554/yi_203
          input_args: preset-rtsp-restream
          roles: [detect, record]
```

Keep `detect` resolution ≤1080p and restream through go2rtc so multiple Frigate consumers share one camera connection.

## Troubleshooting

### Wi-Fi performance suddenly bad / camera unresponsive under load
The `mt7601` USB Wi-Fi module degrades badly with a **loose or unseated antenna connector** — symptom is the camera (and sometimes the whole 2.4 GHz band) wedging the moment any video streams, while ping is fine when idle. Before blaming firmware:

1. **Reseat the Wi-Fi antenna.** Disassembly: remove the 4 Phillips screws on the rear, pull the PCB out of the shell while pushing the lens in from the front. The Wi-Fi antenna plug is on the **front side** of the PCB — unplug it and reseat it firmly.
2. Retest: `ping <camera>` while a video stream is active. If ping survives streaming (2–20 ms, no loss), the radio is fine.

Even with a healthy radio, this Wi-Fi module can stall under sustained load (known upstream issue, unfixable in userspace); **wired ethernet remains the gold standard** for a camera serving Frigate 24/7.

### Camera reboots on its own
Check `/tmp/sd/wd_rtsp.log` and `/tmp/sd/camwatch.log`. This fork fixes the two known self-reboot triggers (cloud respawn spam, single-miss rmm reboot). Remaining reboots are usually power-related — try a different 5V/2A USB adapter and cable.

## Repo layout (vs upstream)

- `.github/workflows/build.yml` — CI package build (repacks upstream `0.4.1` + overlays `src/static/...`)
- `.github/workflows/rtsp-repro.yml` + `scripts/rtsp_probe.py` — x86 repro harness for the stock-server keepalive bug (proves the bug is camera-build-specific)
- `src/static/static/home/yi-hack-v5/{bin,script,etc,www}` — patched files overlaid into the package

## Acknowledgments

This fork stands on [alienatedsec/yi-hack-v5](https://github.com/alienatedsec/yi-hack-v5) (itself built on yi-hack-v4/v3/v2 lineage — see upstream for full credits), the WaveBird hardened RTSP build, and `Temporalwar`'s watchdog fixes.

## Disclaimer

**USE AT YOUR OWN RISK. This is intended for educational/personal purposes only. No warranty; flashing firmware can brick hardware.**
