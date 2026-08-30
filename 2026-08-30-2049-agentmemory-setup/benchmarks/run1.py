from llmbench import *
import json,re,time
ENUM=set("file_read file_write file_edit command_run search web_fetch conversation error discovery subagent notification task other decision".split())
def full(label,base,key,model,extra):
    t0=time.time()
    try:
        b=base.rstrip('/'); url=b+("/chat/completions" if re.search(r'/v\d+$',b) else "/v1/chat/completions")
        body={"model":model,"max_tokens":4096,"messages":[{"role":"system","content":SYS},{"role":"user","content":USER}]}
        if extra: body.update(extra)
        h={"Content-Type":"application/json"}
        if key: h["Authorization"]=f"Bearer {key}"
        r=post(url,h,body,timeout=600); dt=time.time()-t0
        ch=r["choices"][0]; txt=ch["message"].get("content") or ""
        s,note=score(txt)
        ty=(re.search(r'<type>(.*?)</type>',txt,re.S) or [None,''])[1].strip()
        u=r.get("usage",{}) or {}
        return dict(p=label,ok=True,schema=round(s*100),sec=round(dt,1),fin=ch.get("finish_reason"),
                    enum=("OK" if ty in ENUM else f"BAD:{ty[:20]}"), out=u.get("completion_tokens"),
                    rsn=(u.get("completion_tokens_details") or {}).get("reasoning_tokens"),
                    pre=("OK" if txt.strip().startswith('<observation') else "有前言"))
    except Exception as e:
        return dict(p=label,ok=False,schema=0,sec=round(time.time()-t0,1),fin=str(e)[:70],enum="-",out=None,rsn=None,pre="-")
