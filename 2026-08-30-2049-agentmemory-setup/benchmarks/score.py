import json,os,re,glob,urllib.request
SP=os.path.dirname(os.path.abspath(__file__))
MEM=os.path.expanduser("~/.claude/projects/-home-desmond/memory")
QS=json.load(open(f"{SP}/queries.json"))
desc={}
for fp in glob.glob(f"{MEM}/*.md"):
    slug=os.path.basename(fp)[:-3]
    if slug=="MEMORY": continue
    t=open(fp,encoding="utf-8").read()
    m=re.search(r'^description:\s*(.*)$',t,re.M)
    desc[slug]=(m.group(1).strip().strip('"').strip("'") if m else slug)
def search(q,limit=3):
    req=urllib.request.Request("http://127.0.0.1:3111/agentmemory/smart-search",
        data=json.dumps({"query":q,"limit":limit}).encode(),headers={"Content-Type":"application/json"})
    return [r.get("title","") for r in json.load(urllib.request.urlopen(req,timeout=120)).get("results",[])]
r1=r3=0
for item in QS:
    titles=search(item["q"])
    golds=[desc[g][:28] for g in item["gold"] if g in desc]
    hit=[i for i,t in enumerate(titles) if any(g and g in t for g in golds)]
    if hit and hit[0]==0: r1+=1
    if hit: r3+=1
n=len(QS)
print(json.dumps({"R@1":round(r1/n*100),"R@3":round(r3/n*100),"n":n}))
