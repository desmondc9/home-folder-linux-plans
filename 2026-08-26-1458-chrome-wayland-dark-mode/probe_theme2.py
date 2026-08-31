import asyncio, json, subprocess, time
import websockets

CHROME = "/usr/bin/google-chrome-stable"
PORT = 9335
OUT = "/tmp/drhistory/theme-results2.json"

SITES = {
    "bilibili.com": "https://www.bilibili.com/",
    "google.com": "https://www.google.com/",
    "youtube.com": "https://www.youtube.com/",
    "apple.com.cn": "https://www.apple.com.cn/",
    "notion.com": "https://www.notion.com/",
    "supabase.com": "https://supabase.com/docs",
    "bandwagonhost.com": "https://bandwagonhost.com/",
    "skills.sh": "https://www.skills.sh/",
    "amazon.com": "https://www.amazon.com/",
    "douyu.com": "https://www.douyu.com/",
    "dedao.cn": "https://www.dedao.cn/",
    "nvidia.com": "https://www.nvidia.com/",
    "godaddy.com": "https://www.godaddy.com/",
    "minimaxi.com": "https://www.minimaxi.com/",
    "z.ai": "https://chat.z.ai/",
    "x.com": "https://x.com/",
    "__ADULT_SITE_REDACTED__": "__REDACTED__",
    "okx.com": "https://www.okx.com/",
    "v.qq.com": "https://v.qq.com/",
}

SAMPLE_JS = """
(function(){
  function bgOf(el){
    if(!el) return null;
    var c = getComputedStyle(el).backgroundColor;
    var m = c.match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)(?:,\\s*([\\d.]+))?\\)/);
    if(!m) return null;
    return [parseInt(m[1]),parseInt(m[2]),parseInt(m[3]), m[4]===undefined?1:parseFloat(m[4])];
  }
  var body = bgOf(document.body), html = bgOf(document.documentElement);
  var eff = (body && body[3] > 0) ? body : ((html && html[3] > 0) ? html : [255,255,255,1]);
  var lum = (0.2126*eff[0]+0.7152*eff[1]+0.0722*eff[2])/255;
  return JSON.stringify({title: document.title.slice(0,50), lum: lum});
})()
"""

def launch():
    subprocess.run(["pkill", "-f", "remote-debugging-port=933" + "5"], capture_output=True)
    time.sleep(1.5)
    subprocess.Popen([CHROME,
        "--user-data-dir=/tmp/drhistory/profile", "--no-first-run",
        "--remote-debugging-port=%d" % PORT, "--window-size=1000,900",
        "--proxy-server=http://127.0.0.1:10809", "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    import urllib.request
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    for _ in range(40):
        time.sleep(0.5)
        try:
            opener.open("http://127.0.0.1:%d/json/version" % PORT, timeout=1)
            return opener
        except Exception:
            pass
    raise RuntimeError("no chrome")

def lum_of(sample):
    try:
        return json.loads(sample)["lum"]
    except Exception:
        return None

async def test_site(opener, url, scheme, wait=9):
    data = json.load(opener.open("http://127.0.0.1:%d/json/list" % PORT, timeout=3))
    ws_url = next(t["webSocketDebuggerUrl"] for t in data if t["type"] == "page")
    async with websockets.connect(ws_url, max_size=16*1024*1024) as ws:
        mid = 0
        async def send(method, params=None, timeout=40):
            nonlocal mid
            mid += 1
            await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
            deadline = asyncio.get_event_loop().time() + timeout
            while True:
                rem = deadline - asyncio.get_event_loop().time()
                if rem <= 0: return {"error": "timeout"}
                r = json.loads(await asyncio.wait_for(ws.recv(), rem))
                if r.get("id") == mid: return r
        await send("Page.enable")
        await send("Emulation.setEmulatedMedia", {"features": [{"name": "prefers-color-scheme", "value": scheme}]})
        await send("Page.navigate", {"url": "about:blank"})
        await asyncio.sleep(0.5)
        await send("Page.navigate", {"url": url})
        await asyncio.sleep(wait)
        r = await send("Runtime.evaluate", {"expression": SAMPLE_JS, "returnByValue": True})
        try:
            return json.loads(r["result"]["result"]["value"])
        except Exception:
            return {"title": "SAMPLE-ERR", "lum": None, "raw": json.dumps(r)[:100]}

async def main():
    opener = launch()
    results = {}
    for dom, url in SITES.items():
        try:
            dark = await test_site(opener, url, "dark")
            dl = dark.get("lum")
            if dl is None:
                # one retry with longer wait
                dark = await test_site(opener, url, "dark", wait=14)
                dl = dark.get("lum")
            verdict = "DARK-ON-BOOT" if (dl is not None and dl < 0.45) else ("ALREADY-DARK?" if (dl is not None and dl < 0.45) else "no")
            results[dom] = {"url": url, "dark_boot_lum": dl, "title": dark.get("title",""), "follows": dl is not None and dl < 0.45}
            print("%-18s dark_boot=%.2f  %-14s %s" % (dom, dl if dl is not None else -1, verdict, dark.get("title","")[:36]), flush=True)
        except Exception as e:
            print("%-18s CONN-DIED, relaunching (%s)" % (dom, str(e)[:60]), flush=True)
            results[dom] = {"url": url, "error": str(e)[:120]}
            try:
                opener = launch()
            except Exception as e2:
                print("relaunch failed:", e2, flush=True)
                break
    json.dump(results, open(OUT, "w"), ensure_ascii=False, indent=1)
    print("saved", OUT)

asyncio.run(main())
