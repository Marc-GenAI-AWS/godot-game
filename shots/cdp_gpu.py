import asyncio, base64, json, subprocess, sys, time, urllib.request
import websockets

URL = sys.argv[1]
TIMES = [float(t) for t in sys.argv[2].split(",")]
OUT = sys.argv[3]
KEYS = [(float(k.split(":")[0]), k.split(":")[1]) for k in sys.argv[4].split(",")] if len(sys.argv) > 4 and sys.argv[4] else []
PORT = 9333

proc = subprocess.Popen([
    "/usr/bin/chromium-browser", "--headless=new", "--no-sandbox",
    "--use-gl=angle", "--use-angle=gl-egl", "--enable-gpu-rasterization", "--disable-gpu-sandbox", "--ignore-gpu-blocklist",
    "--window-size=1280,720", "--hide-scrollbars", f"--remote-debugging-port={PORT}",
    "--user-data-dir=/home/marc/dev/graphics-gen/shots/.profile", "--disk-cache-size=1", "about:blank"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def targets():
    for _ in range(50):
        try:
            return json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json"))
        except Exception:
            time.sleep(0.3)
    raise SystemExit("no devtools")

async def main():
    page = [t for t in targets() if t["type"] == "page"][0]
    async with websockets.connect(page["webSocketDebuggerUrl"], max_size=None) as ws:
        mid = 0
        async def send(method, **params):
            nonlocal mid
            mid += 1
            await ws.send(json.dumps({"id": mid, "method": method, "params": params}))
            while True:
                msg = json.loads(await ws.recv())
                if msg.get("id") == mid:
                    return msg.get("result", msg)
                ev = msg.get("method")
                if ev == "Runtime.consoleAPICalled":
                    args = " ".join(str(a.get("value", a.get("description", ""))) for a in msg["params"]["args"])
                    print(f"[console.{msg['params']['type']}] {args[:300]}")
                elif ev == "Runtime.exceptionThrown":
                    print("[exception]", msg["params"]["exceptionDetails"].get("text"), str(msg["params"]["exceptionDetails"].get("exception", {}).get("description", ""))[:300])
        await send("Network.enable")
        await send("Network.clearBrowserCache")
        await send("Network.setCacheDisabled", cacheDisabled=True)
        await send("Runtime.enable")
        await send("Page.enable")
        await send("Page.navigate", url=URL)
        # sync the clock to the game's "world ready" line so key scripts are
        # deterministic regardless of load time (falls back after 40 s)
        t0 = time.time()
        deadline = t0 + 40.0
        while time.time() < deadline:
            try:
                msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=0.5))
            except asyncio.TimeoutError:
                continue
            if msg.get("method") == "Runtime.consoleAPICalled":
                args = " ".join(str(a.get("value", a.get("description", ""))) for a in msg["params"]["args"])
                print(f"[console.{msg['params']['type']}] {args[:300]}")
                if "world ready" in args:
                    t0 = time.time()
                    print("synced at world ready (%.1fs after navigate)" % (t0 - (deadline - 40.0)))
                    break
        KEYMAP = {"Space": (" ", "Space", 32), "ArrowUp": ("ArrowUp", "ArrowUp", 38), "ArrowDown": ("ArrowDown", "ArrowDown", 40), "ArrowLeft": ("ArrowLeft", "ArrowLeft", 37), "ArrowRight": ("ArrowRight", "ArrowRight", 39), "KeyE": ("e", "KeyE", 69), "Enter": ("Enter", "Enter", 13)}
        async def drag(dx, dy):
            x, y = 640, 300
            await send("Input.dispatchMouseEvent", type="mousePressed", x=x, y=y, button="left", clickCount=1)
            steps = 12
            for k in range(1, steps + 1):
                await send("Input.dispatchMouseEvent", type="mouseMoved", x=x + dx * k / steps, y=y + dy * k / steps, button="left", buttons=1)
                await asyncio.sleep(0.03)
            await send("Input.dispatchMouseEvent", type="mouseReleased", x=x + dx, y=y + dy, button="left", clickCount=1)
            print("dragged", dx, dy)
        focused = [False]
        async def focus_canvas():
            # give the Godot canvas keyboard focus (a click would also count as a
            # tap and toggle the walker's pace, so focus it directly)
            if focused[0]:
                return
            focused[0] = True
            r = await send("Runtime.evaluate", expression="(function(){var c=document.getElementById('canvas'); if(c){c.focus();} return document.activeElement===c;})()")
            print("focus", r.get("result", {}).get("value"))
        async def key_event(kind, name):
            key, code, vk = KEYMAP[name]
            await send("Input.dispatchKeyEvent", type=kind, key=key, code=code, windowsVirtualKeyCode=vk, nativeVirtualKeyCode=vk)
        # expand "t:Key~hold" into a keyDown at t and a keyUp at t+hold so
        # holds never block the loop (screenshots can land mid-hold)
        events = []
        for t_at, name in KEYS:
            hold = 0.12
            if "~" in name:
                name, h = name.split("~"); hold = float(h)
            if name.startswith("Drag"):
                _, dx, dy = name.split("_")
                events.append((t_at, ("drag", float(dx), float(dy))))
            else:
                events.append((t_at, ("keyDown", name, hold)))
        events.sort(key=lambda e: e[0])
        pending = events
        await focus_canvas()
        async def fire(ev):
            await focus_canvas()
            if ev[0] == "drag":
                await drag(ev[1], ev[2])
            else:
                await key_event(ev[0], ev[1])
                now = time.time() - t0
                print(ev[0], ev[1], "at %.1fs" % now)
                if ev[0] == "keyDown":   # schedule the release from the real press time
                    pending.append((now + ev[2], ("keyUp", ev[1])))
                    pending.sort(key=lambda e: e[0])
        for i, t in enumerate(TIMES):
            # drain events while waiting
            while time.time() - t0 < t:
                while pending and time.time() - t0 >= pending[0][0]:
                    await fire(pending.pop(0)[1])
                try:
                    # wake up in time for the next scheduled key event
                    wait = 0.2
                    if pending:
                        wait = max(0.005, min(wait, pending[0][0] - (time.time() - t0)))
                    msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=wait))
                    ev = msg.get("method")
                    if ev == "Runtime.consoleAPICalled":
                        args = " ".join(str(a.get("value", a.get("description", ""))) for a in msg["params"]["args"])
                        print(f"[console.{msg['params']['type']}] {args[:300]}")
                    elif ev == "Runtime.exceptionThrown":
                        print("[exception]", str(msg["params"]["exceptionDetails"])[:400])
                except asyncio.TimeoutError:
                    pass
            r = await send("Page.captureScreenshot", format="png")
            fn = f"{OUT}_{i}_{int(t)}s.png"
            open(fn, "wb").write(base64.b64decode(r["data"]))
            print("wrote", fn)
    proc.terminate()

asyncio.run(main())
