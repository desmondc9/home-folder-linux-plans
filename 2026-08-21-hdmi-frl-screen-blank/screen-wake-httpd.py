#!/usr/bin/env python3
# screen-wake-httpd.py — 专用唤醒端点: 任何 HTTP 请求到达即点亮屏幕。
# 用法: curl http://<主机>:47800/wake  (路径任意,任何方法都行)
# 安全说明: 只点亮屏幕,不解锁 —— 知道密码才能进桌面,所以对 LAN/tailnet 暴露无副作用。
import http.server
import subprocess

PORT = 47800
WAKE_CMD = [
    "bash", "-c",
    "qdbus6 org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.SimulateUserActivity 2>/dev/null; "
    "kscreen-doctor --dpms on 2>/dev/null",
]


class Handler(http.server.BaseHTTPRequestHandler):
    def _handle(self):
        try:
            subprocess.run(WAKE_CMD, timeout=15)
            body = b"woken\n"
            code = 200
        except Exception as e:  # noqa: BLE001
            body = f"wake failed: {e}\n".encode()
            code = 500
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_GET = do_POST = do_HEAD = _handle

    def log_message(self, format, *args):  # 静音访问日志
        pass


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
