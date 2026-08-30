import json,glob,os,re,time,urllib.request,math,sys

MEM=os.path.expanduser("~/.claude/projects/-home-desmond/memory")
SP=os.path.dirname(os.path.abspath(__file__))
QS=json.load(open(f"{SP}/queries.json"))

def load_docs():
    docs=[]
    for fp in sorted(glob.glob(f"{MEM}/*.md")):
        slug=os.path.basename(fp)[:-3]
        if slug=="MEMORY": continue
        t=open(fp,encoding="utf-8").read()
        m=re.search(r'^description:\s*(.*)$',t,re.M)
        desc=(m.group(1).strip().strip('"').strip("'") if m else slug)
        body=re.sub(r'^---.*?^---\s*','',t,flags=re.S|re.M)
        docs.append((slug, f"{desc}\n\n{body}"[:4000]))
    return docs

def embed(model, texts, batch=8):
    out=[]
    for i in range(0,len(texts),batch):
        req=urllib.request.Request("http://127.0.0.1:11434/v1/embeddings",
            data=json.dumps({"model":model,"input":texts[i:i+batch]}).encode(),
            headers={"Content-Type":"application/json"})
        r=json.load(urllib.request.urlopen(req,timeout=900))
        out+= [d["embedding"] for d in r["data"]]
    return out

def norm(v):
    n=math.sqrt(sum(x*x for x in v)) or 1.0
    return [x/n for x in v]

PREFIX=os.environ.get("QPREFIX","")

def run(model):
    docs=load_docs(); slugs=[s for s,_ in docs]
    t0=time.time(); D=[norm(v) for v in embed(model,[d for _,d in docs])]; t_idx=time.time()-t0
    t0=time.time(); Q=[norm(v) for v in embed(model,[PREFIX+q["q"] for q in QS])]; t_q=(time.time()-t0)/len(QS)
    r1=r3=r5=0; mrr=0.0; misses=[]
    for qi,qv in enumerate(Q):
        scores=sorted(((sum(a*b for a,b in zip(qv,dv)),slugs[i]) for i,dv in enumerate(D)),reverse=True)
        ranked=[s for _,s in scores]; gold=set(QS[qi]["gold"])
        rank=next((k+1 for k,s in enumerate(ranked) if s in gold), None)
        if rank:
            mrr+=1/rank
            if rank<=1: r1+=1
            if rank<=3: r3+=1
            if rank<=5: r5+=1
        if not rank or rank>3: misses.append((QS[qi]["q"], ranked[0], rank))
    n=len(QS)
    return {"model":model+("+instruct" if PREFIX else ""),"dims":len(D[0]),"R@1":r1/n,"R@3":r3/n,"R@5":r5/n,
            "MRR":mrr/n,"index_s":t_idx,"query_ms":t_q*1000,"misses":misses}

if __name__=="__main__":
    res=[]
    for m in sys.argv[1:]:
        sys.stderr.write(f"--- {m} ---\n"); sys.stderr.flush()
        try: res.append(run(m))
        except Exception as e: sys.stderr.write(f"FAIL {m}: {e}\n")
    print(json.dumps(res,ensure_ascii=False,indent=1))
