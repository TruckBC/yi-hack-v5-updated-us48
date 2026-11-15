import socket, time, sys

HOST = "127.0.0.1"
PORT = 8554  # unprivileged: RTSPServer falls back to IPv6 bind() which needs root on :554

def probe(mid_cmd=None, label=""):
    s = socket.create_connection((HOST, PORT), timeout=8)
    s.settimeout(5)

    def req(cmd, wait=0.8):
        s.sendall(cmd.encode())
        time.sleep(wait)
        try:
            return s.recv(65536)
        except socket.timeout:
            return b""

    r = req(f"OPTIONS rtsp://{HOST}:554/ch0_0.h264 RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: probe\r\n\r\n")
    if b"200" not in r:
        print(f"PROBE {label}: OPTIONS failed: {r[:80]!r}")
        s.close()
        return

    r = req(f"SETUP rtsp://{HOST}:554/ch0_0.h264/track1 RTSP/1.0\r\nCSeq: 3\r\nUser-Agent: probe\r\nTransport: RTP/AVP/TCP;unicast;interleaved=0-1\r\n\r\n")
    if b"Session: " not in r:
        print(f"PROBE {label}: SETUP failed: {r[:80]!r}")
        s.close()
        return
    sess = r.split(b"Session: ")[1].split(b";")[0].decode()

    req(f"PLAY rtsp://{HOST}:554/ch0_0.h264 RTSP/1.0\r\nCSeq: 4\r\nUser-Agent: probe\r\nSession: {sess}\r\n\r\n")

    total = 0
    t0 = time.time()
    s.settimeout(2)
    try:
        while time.time() - t0 < 6:
            d = s.recv(65536)
            if not d:
                break
            total += len(d)
    except socket.timeout:
        pass
    before = total / 1024

    after = 0.0
    if mid_cmd:
        resp = req(mid_cmd.replace("%SESS%", sess), 1.5)
        resp_ok = b"200 OK" in resp
        total = 0
        t0 = time.time()
        try:
            while time.time() - t0 < 8:
                d = s.recv(65536)
                if not d:
                    break
                total += len(d)
        except socket.timeout:
            pass
        after = total / 1024
        verdict = "OK" if after > 20 else "KILLED"
        print(f"PROBE {label}: before={before:.0f}KB resp200={resp_ok} after={after:.0f}KB -> {verdict}")
    else:
        print(f"PROBE {label}: (no mid-stream cmd) streamed={before:.0f}KB -> {'OK' if before > 20 else 'FAIL'}")
    s.close()

probe(None, "baseline-no-keepalive")
probe(f"GET_PARAMETER rtsp://{HOST}:554/ch0_0.h264 RTSP/1.0\r\nCSeq: 5\r\nUser-Agent: probe\r\nSession: %SESS%\r\nContent-Length: 0\r\n\r\n", "keepalive-get_parameter")
probe(f"OPTIONS rtsp://{HOST}:554/ch0_0.h264 RTSP/1.0\r\nCSeq: 6\r\nUser-Agent: probe\r\nSession: %SESS%\r\n\r\n", "keepalive-options")
