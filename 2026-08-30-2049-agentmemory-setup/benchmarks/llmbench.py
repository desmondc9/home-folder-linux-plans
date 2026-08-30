import json,os,re,time,urllib.request,urllib.error,sys
SP=os.path.dirname(os.path.abspath(__file__))
P=json.load(open(f"{SP}/providers.json"))

SYS="""You are a memory compression engine for an AI coding agent. Your job is to extract the essential information from a tool usage observation and compress it into structured data.

Output EXACTLY this XML format with no additional text:

<observation>
  <type>one of: file_read, file_write, file_edit, command_run, search, web_fetch, conversation, error, decision, discovery, subagent, notification, task, other</type>
  <title>Short descriptive title (max 80 chars)</title>
  <subtitle>One-line context (optional)</subtitle>
  <facts>
    <fact>Specific factual detail 1</fact>
  </facts>
  <narrative>2-3 sentence summary of what happened and why it matters</narrative>
  <concepts>
    <concept>technical concept or pattern</concept>
  </concepts>
  <files>
    <file>path/to/file</file>
  </files>
  <importance>1-10 scale, 10 being critical architectural decision</importance>
</observation>

Rules:
- Be concise but preserve ALL technically relevant details
- File paths must be exact"""

USER="""Observation: 用户编辑了 /home/desmond/.agentmemory/.env,把 EMBEDDING_PROVIDER 从 local 改成 openai,
并新增 OPENAI_EMBEDDING_BASE_URL=http://127.0.0.1:11434 指向本地 Ollama,模型 qwen3-embedding:4b,维度 2560。
随后重启 systemd user unit agentmemory.service,服务因持久化向量索引维度不匹配(1024 vs 2560)拒绝启动,
改用 AGENTMEMORY_DROP_STALE_INDEX=true 丢弃旧索引后启动成功。"""

REQUIRED=["type","title","narrative","concepts","importance"]

def post(url,hdr,body,timeout=180):
    req=urllib.request.Request(url,data=json.dumps(body).encode(),headers=hdr)
    return json.load(urllib.request.urlopen(req,timeout=timeout))

def openai_call(base,key,model,extra=None):
    b=base.rstrip('/')
    url=b+("/chat/completions" if re.search(r'/v\d+$',b) or b.endswith('/anthropic') else "/v1/chat/completions")
    body={"model":model,"max_tokens":900,"messages":[{"role":"system","content":SYS},{"role":"user","content":USER}]}
    if extra: body.update(extra)
    r=post(url,{"Content-Type":"application/json","Authorization":f"Bearer {key}"},body)
    return r["choices"][0]["message"].get("content") or "", r.get("usage",{})

def anthropic_call(base,key,model,extra=None):
    url=base.rstrip('/')+"/v1/messages"
    body={"model":model,"max_tokens":900,"system":SYS,"messages":[{"role":"user","content":USER}]}
    if extra: body.update(extra)
    r=post(url,{"Content-Type":"application/json","x-api-key":key,"anthropic-version":"2023-06-01"},body)
    txt="".join(b.get("text","") for b in r.get("content",[]) if b.get("type")=="text")
    return txt, r.get("usage",{})

def score(txt):
    if not txt.strip(): return 0,"空输出"
    have=[t for t in REQUIRED if re.search(rf'<{t}>.*?</{t}>',txt,re.S)]
    extra_prose = not txt.strip().startswith('<')
    return len(have)/len(REQUIRED), f"{len(have)}/{len(REQUIRED)} 标签" + ("(有多余文字)" if extra_prose else "")

def run(label,fn,*a,**kw):
    t0=time.time()
    try:
        txt,usage=fn(*a,**kw); dt=time.time()-t0
        s,note=score(txt)
        return {"provider":label,"ok":True,"schema":round(s*100),"note":note,"sec":round(dt,1),"usage":usage,"sample":txt.strip()[:110]}
    except urllib.error.HTTPError as e:
        return {"provider":label,"ok":False,"schema":0,"note":f"HTTP {e.code}: {e.read()[:120].decode(errors='replace')}","sec":round(time.time()-t0,1)}
    except Exception as e:
        return {"provider":label,"ok":False,"schema":0,"note":str(e)[:130],"sec":round(time.time()-t0,1)}
