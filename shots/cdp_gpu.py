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
        t0 = time.time()
        KEYMAP = {"Space": (" ", "Space", 32), "ArrowUp": ("ArrowUp", "ArrowUp", 38), "ArrowDown": ("ArrowDown", "ArrowDown", 40), "ArrowLeft": ("ArrowLeft", "ArrowLeft", 37), "ArrowRight": ("ArrowRight", "ArrowRight", 39)}
        pending = sorted(KEYS)
        async def drag(dx, dy):
            x, y = 640, 300
            await send("Input.dispatchMouseEvent", type="mousePressed", x=x, y=y, button="left", clickCount=1)
            steps = 12
            for k in range(1, steps + 1):
                await send("Input.dispatchMouseEvent", type="mouseMoved", x=x + dx * k / steps, y=y + dy * k / steps, button="left", buttons=1)
                await asyncio.sleep(0.03)
            await send("Input.dispatchMouseEvent", type="mouseReleased", x=x + dx, y=y + dy, button="left", clickCount=1)
            print("dragged", dx, dy)
        async def press(name):
            if name.startswith("Drag"):
                _, dx, dy = name.split("_")
                await drag(float(dx), float(dy)); return
            key, code, vk = KEYMAP[name]
            await send("Input.dispatchKeyEvent", type="keyDown", key=key, code=code, windowsVirtualKeyCode=vk, nativeVirtualKeyCode=vk)
            await asyncio.sleep(0.12)
            await send("Input.dispatchKeyEvent", type="keyUp", key=key, code=code, windowsVirtualKeyCode=vk, nativeVirtualKeyCode=vk)
            print("pressed", name)
        for i, t in enumerate(TIMES):
            # drain events while waiting
            while time.time() - t0 < t:
                while pending and time.time() - t0 >= pending[0][0]:
                    await press(pending.pop(0)[1])
                try:
                    msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=0.2))
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
