#!/usr/bin/env python3
"""Boots the exported web build in a real browser and screenshots it.

The export succeeding proves the files were written, not that the game runs.
gl_compatibility, the single-threaded WASM build and the audio context all
only fail once a browser actually executes them, so this drives the real
artifact in docs/ the way GitHub Pages will serve it.

Usage: python3 tests/web_smoke.py [--out DIR] [--touch]
"""

import argparse
import http.server
import socketserver
import subprocess
import sys
import threading
from functools import partial
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
PORT = 8912


def serve():
    handler = partial(http.server.SimpleHTTPRequestHandler, directory=str(DOCS))
    httpd = socketserver.TCPServer(("127.0.0.1", PORT), handler)
    httpd.allow_reuse_address = True
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/tmp/web_shots")
    ap.add_argument("--touch", action="store_true", help="emulate a touchscreen")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    from playwright.sync_api import sync_playwright

    httpd = serve()
    errors, logs = [], []
    try:
        with sync_playwright() as p:
            # Point at whichever Chromium is actually on this machine rather
            # than the build this Playwright release pins: CI images ship a
            # preinstalled browser whose version rarely matches, and
            # `playwright install` isn't reliably available offline.
            launch: dict = {"args": ["--use-gl=swiftshader", "--enable-webgl"]}
            for candidate in (
                Path("/opt/pw-browsers/chromium-1194/chrome-linux/chrome"),
                Path("/opt/pw-browsers/chromium/chrome-linux/chrome"),
            ):
                if candidate.exists():
                    launch["executable_path"] = str(candidate)
                    break
            browser = p.chromium.launch(**launch)
            ctx_args = {"viewport": {"width": 1280, "height": 720}}
            if args.touch:
                ctx_args.update(has_touch=True, is_mobile=True,
                                viewport={"width": 430, "height": 860})
            ctx = browser.new_context(**ctx_args)
            page = ctx.new_page()
            page.on("pageerror", lambda e: errors.append(str(e)))
            page.on("console", lambda m: logs.append(f"{m.type}: {m.text}"))

            page.goto(f"http://127.0.0.1:{PORT}/index.html", wait_until="load")
            # The WASM module has to download, compile and boot before anything
            # is on the canvas; there is no load event for that.
            page.wait_for_timeout(35000)
            page.screenshot(path=str(out / "01_boot.png"))

            # Drive it: walk, then swing a few times.
            for key in ("KeyW", "KeyW", "KeyD"):
                page.keyboard.down(key)
                page.wait_for_timeout(700)
                page.keyboard.up(key)
            page.screenshot(path=str(out / "02_moved.png"))

            for _ in range(3):
                page.keyboard.press("Space")
                page.wait_for_timeout(1100)
            page.screenshot(path=str(out / "03_swung.png"))

            page.keyboard.press("Digit3")
            page.wait_for_timeout(1200)
            page.screenshot(path=str(out / "04_ragdoll.png"))

            browser.close()
    finally:
        httpd.shutdown()

    for line in logs[:25]:
        print("LOG", line)
    if errors:
        print(f"FAIL {len(errors)} page error(s):")
        for e in errors[:10]:
            print("  ", e)
        return 1
    print(f"WEB_SMOKE_OK shots in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
