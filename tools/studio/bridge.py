"""A tiny localhost bridge between Roblox Studio and this project folder.

Studio's edit DataModel (through the Studio MCP's execute_luau, with
HttpService.HttpEnabled on) can GET any file under the project root and POST a
text body to be written under work/ or assets/. That is how data that only exists
in Studio (generated mesh ids, measured sizes) gets back onto disk, where it is
the source of truth, without passing through anyone's context window.

    python tools/studio/bridge.py [--port 34881]

    GET  /design/mesh_jobs.json
    POST /save?path=work/meshes/staged.json      (body = file content, utf-8)

Binds to 127.0.0.1 only. Writes are refused outside work/ and assets/.
"""

from __future__ import annotations

import argparse
import http.server
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WRITABLE = ("work", "assets")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def log_message(self, fmt, *args):  # keep the console quiet
        pass

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        rel = (query.get("path") or [""])[0].replace("\\", "/")
        target = (ROOT / rel).resolve()
        ok = parsed.path == "/save" and rel and rel.split("/")[0] in WRITABLE and ROOT in target.parents
        if not ok:
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"refused")
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length)
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_suffix(target.suffix + ".tmp")
        tmp.write_bytes(body)
        tmp.replace(target)  # atomic: a half-written file never passes for a finished one
        self.send_response(200)
        self.end_headers()
        self.wfile.write(f"saved {rel} {len(body)}".encode())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=34881)
    a = ap.parse_args()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", a.port), Handler)
    print(f"bridge on http://127.0.0.1:{a.port}/ serving {ROOT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
