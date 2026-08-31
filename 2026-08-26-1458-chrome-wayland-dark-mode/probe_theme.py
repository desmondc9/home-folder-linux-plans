import asyncio, json, subprocess, time, re
import websockets

CHROME = "/usr/bin/google-chrome-stable"
PORT = 9335
OUT = "/tmp/drhistory/theme-results.json"

SITES = {
    "bilibili.com": "https://www.bilibili.com/",
    "google.com": "https://www.google.com/",
    "kimi.com": "https://www.kimi.com/",
    "youtube.com": "https://www.youtube.com/",
    "github.com": "https://github.com/obra/superpowers",
    "__ADULT_SITE_REDACTED__": "__REDACTED__",
    "claude.ai": "https://claude.ai/",
    "apple.com.cn": "https://www.apple.com.cn/",
    "bigmodel.cn": "https://bigmodel.cn/",
    "cursor.com": "https://cursor.com/",
    "notion.com": "https://www.notion.com/",
    "supabase.com": "https://supabase.com/docs",
    "cloudflare.com": "https://www.cloudflare.com/",
    "bandwagonhost.com": "https://bandwagonhost.com/",
    "skills.sh": "https://www.skills.sh/",
    "okx.com": "https://www.okx.com/",
    "amazon.com": "https://www.amazon.com/",
    "qq.com": "https://v.qq.com/",
    "douyu.com": "https://www.douyu.com/",
    "dedao.cn": "https://www.dedao.cn/",
    "nvidia.com": "https://www.nvidia.com/",
    "godaddy.com": "https://www.godaddy.com/",
    "minimaxi.com": "https://www.minimaxi.com/",
    "z.ai": "https://chat.z.ai/",
    "x.com": "https://x.com/",
    "ups.com": "https://www.ups.com/",
}

SAMPLE_JS = """
(function(){
  function bgOf(el){
    if(!el) return null;
    var c = getComputedStyle(el).backgroundColor;
    var m = c.match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)(?:,\\s*([\\d.]+))?\\)/);
    if(!m) return null;
    var a = m[4]===undefined ? 1 : parseFloat(m[4]);
    return [parseInt(m[1]),parseInt(m[2]),parseInt(m[3]),a];
  }
  var body = bgOf(document.body), html = bgOf(document.documentElement);
  var eff = (body && body[3] > 0) ? body : ((html && html[3] > 0) ? html : [255,255,255,1]);
  var meta = document.querySelector('meta[name="color-scheme"]');
  return JSON.stringify({
    title: document.title.slice(0,60),
    url: location.href.slice(0,80),
    bodyBg: body, htmlBg: html, effBg: eff,
    cssColorScheme: getComputedStyle(document.documentElement).colorScheme || '',
    metaColorScheme: meta ? meta.content : ''
  });
})()
"""

def lum(rgb):
    return (0.2126*rgb[0] + 0.7152*rgb[1] + 0.0722*rgb[2]) / 255.0

def launch():
    subprocess.run(["pkill", "-f", "remote-debugging-port=933" + "5"], capture_output=True)
    time.sleep(1)
    subprocess.Popen([CHROME,
        "--user-data-dir=/tmp/drhistory/profile", "--no-first-run",
        "--remote-debugging-port=%d" % PORT, "--window-size=1000,900",
        "--proxy-server=http://127.0.0.1:10809",
        "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    import urllib.request
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))  # bypass env proxies for localhost
    for _ in range(40):
        time.sleep(0.5)
        try:
            opener.open("http://127.0.0.1:%d/json/version" % PORT, timeout=1)
            return opener
        except Exception:
            pass
    raise RuntimeError("no chrome")

async def main():
    opener = launch()
    data = json.load(opener.open("http://127.0.0.1:%d/json/list" % PORT, timeout=3))
    ws_url = next(t["webSocketDebuggerUrl"] for t in data if t["type"] == "page")
    results = {}
    async with websockets.connect(ws_url, max_size=64*1024*1024) as ws:
        mid = 0
        async def send(method, params=None, timeout=25):
            nonlocal mid
            mid += 1
            await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
            deadline = asyncio.get_event_loop().time() + timeout
            while True:
                rem = deadline - asyncio.get_event_loop().time()
                if rem <= 0:
                    return {"error": "timeout"}
                r = json.loads(await asyncio.wait_for(ws.recv(), rem))
                if r.get("id") == mid:
                    return r
        async def sample():
            r = await send("Runtime.evaluate", {"expression": SAMPLE_JS, "returnByValue": True})
            try:
                return json.loads(r["result"]["result"]["value"])
            except Exception:
                return {"err": json.dumps(r)[:150]}
        await send("Page.enable")
        await send("Emulation.setEmulatedMedia", {"features": [{"name": "prefers-color-scheme", "value": "light"}]})

        for dom, url in SITES.items():
            try:
                await send("Page.navigate", {"url": url}, timeout=40)
                await asyncio.sleep(7)
                light = await sample()
                await send("Emulation.setEmulatedMedia", {"features": [{"name": "prefers-color-scheme", "value": "dark"}]})
                await asyncio.sleep(2)
                dark = await sample()
                ll = lum(light.get("effBg", [255,255,255,1])) if "err" not in light else None
                dl = lum(dark.get("effBg", [255,255,255,1])) if "err" not in dark else None
                flip = (ll is not None and dl is not None and ll > 0.55 and dl < 0.45 and (ll - dl) > 0.2)
                results[dom] = {"url": url, "title": dark.get("title", ""), "light_lum": round(ll,3) if ll is not None else None,
                                "dark_lum": round(dl,3) if dl is not None else None, "auto_dark": flip,
                                "meta": dark.get("metaColorScheme",""), "css": dark.get("cssColorScheme","")}
                print("%-18s %-6s light=%.2f dark=%.2f  %s" % (dom, "FLIP" if flip else "-", ll or -1, dl or -1, dark.get("title","")[:40]), flush=True)
            except Exception as e:
                results[dom] = {"url": url, "error": str(e)[:120]}
                print("%-18s ERROR %s" % (dom, str(e)[:80]), flush=True)
            await send("Emulation.setEmulatedMedia", {"features": [{"name": "prefers-color-scheme", "value": "light"}]})
    json.dump(results, open(OUT, "w"), ensure_ascii=False, indent=1)
    print("saved", OUT)

asyncio.run(main())
