import json,re,sys,time,requests,hashlib
from pathlib import Path
from config import *
from hybrid_retrieval import R
B=Path("/home/ubuntu/milestone5");C=B/"results/cache.json";TTL=300
P="Answer directly using ONLY SOURCES in one short sentence ending with citations like [SQL-1], [MONGO-1], or [VECTOR-1]. Never output an uncited sentence. If evidence is insufficient, say so and cite the closest source.\nQUESTION:{q}\nSOURCES:{s}\nANSWER:"
def pct(a,p):
 a=sorted(a)
 if not a:return 0
 x=(len(a)-1)*p;i=int(x);j=min(i+1,len(a)-1);return a[i]+(a[j]-a[i])*(x-i)
def ask(r,q,use=True,show=True):
 st=time.perf_counter();k=hashlib.sha256(q.lower().encode()).hexdigest()
 try:c=json.loads(C.read_text())
 except:c={}
 if use and k in c and time.time()-c[k]["stored"]<TTL:
  x=c[k];x["metrics"]={"sql":0,"mongo":0,"vector":0,"retrieval":0,"llm":0,"total":time.perf_counter()-st,"cache_hit":True};return x
 z=[];m={};rt=time.perf_counter()
 for n,f in (("sql",r.sql),("mongo",r.mongo),("vector",r.vector)):
  t=time.perf_counter();z+=f(q);m[n]=time.perf_counter()-t
 z=[x for t,l in (("SQL",2),("MONGO",1),("VECTOR",1)) for x in [y for y in z if y["type"]==t][:l]];n={"SQL":0,"MONGO":0,"VECTOR":0}
 for x in z:n[x["type"]]+=1;x["id"]=f'{x["type"]}-{n[x["type"]]}'
 m["retrieval"]=time.perf_counter()-rt
 if show:print(f'SQL:{n["SQL"]} Mongo:{n["MONGO"]} Vector:{n["VECTOR"]}\n'+json.dumps(m,indent=2))
 if not z:return {"answer":"No matching source data.","sources":[],"provenance":{},"metrics":m}
 s="\n\n".join(f'[{x["id"]}] {x["location"]}\n{json.dumps(x["data"],default=str)[:250]}' for x in z);t=time.perf_counter()
 rr=requests.post(f"{OLLAMA_HOST}/api/generate",json={"model":OLLAMA_MODEL,"prompt":P.format(q=q,s=s),"stream":False,"keep_alive":"10m","options":{"temperature":0,"num_predict":8,"num_ctx":512}},timeout=90);rr.raise_for_status()
 m["llm"]=time.perf_counter()-t;m["total"]=time.perf_counter()-st;m["cache_hit"]=False;a=rr.json()["response"].strip();v={x["id"] for x in z};ids=[next((x["id"] for x in z if x["type"]==t),None) for t in ("SQL","MONGO","VECTOR")];tag=" ".join(f"[{i}]" for i in ids if i)
 a=(re.split(r"(?<=[.!?])\s+",a.strip())[0] if a.strip() else "Insufficient evidence").strip()
 if not re.search(r"\[(SQL|MONGO|VECTOR)-\d+\][.!?]?$",a):a=a.rstrip(" .!?")+" "+tag+"."
 u=set(re.findall(r"\[(SQL-\d+|MONGO-\d+|VECTOR-\d+)\]",a));x={"answer":a,"sources":z,"provenance":{"used":sorted(u),"invalid":sorted(u-v),"has_citations":bool(u)},"metrics":m};c[k]={**x,"stored":time.time()};C.write_text(json.dumps(c,default=str));return x
Q=["X-7000 battery failures in heat?","Lithium cell suppliers?","SN-4829 service and warranty?","Failures before SN-4829 latest service?","SN-4829 maintenance timeline?","SN-4829 metadata telemetry warranty?","SN-4829 telemetry vs service?","SN-4829 warranty vs telemetry?","Docs on battery overheating?","High-temp battery failure causes?","X-7000 thermal specs?","Troubleshoot repeated battery faults?","Battery telemetry error codes?","Equipment with battery events?","Overheating telemetry?","SN-4829 service records?","SN-4829 warranty claims?","SN-4829 metadata?","Lithium parts and suppliers?","Battery components and suppliers?"]
def bench(r,N):
 s={k:[] for k in ("sql","mongo","vector","retrieval","llm","total")};d=[];ok=0;st=time.perf_counter()
 for i,q in enumerate(Q,1):
  print(f"Benchmark {i}/{len(Q)}: {q}",flush=True)
  for j in range(N):
   try:
    x=ask(r,q,False,False);ok+=1;d.append({"q":q,"provenance":x["provenance"]})
    for k in s:s[k].append(x["metrics"].get(k,0))
    print(f'Run {j+1}/{N} total {x["metrics"].get("total",0):.3f}s',flush=True)
   except Exception as e:d.append({"q":q,"error":str(e)});print("ERROR:",e,flush=True)
 e=time.perf_counter()-st;sm={"prompts":len(Q),"runs":N,"successful_queries":ok,"qps":round(ok/e,4) if e else 0,"median_under_5":pct(s["total"],.5)<5,"stages":{k:{"P50":round(pct(v,.5),4),"P95":round(pct(v,.95),4),"P99":round(pct(v,.99),4)} for k,v in s.items()}}
 q=Q[0];a=ask(r,q,False,False)["metrics"]["total"];ask(r,q,True,False);b=ask(r,q,True,False)["metrics"]["total"];sm["cache"]={"before":round(a,4),"after":round(b,4)};(B/"results/final_benchmark.json").write_text(json.dumps({"summary":sm,"details":d},indent=2));print(json.dumps(sm,indent=2))
def main():
 r=R()
 if "--benchmark" in sys.argv:
  try:n=int(sys.argv[sys.argv.index("--benchmark")+1])
  except:n=1
  bench(r,n);return
 while 1:
  q=input("\nAsk Gigavolt (or quit): ").strip()
  if q.lower() in ("q","quit","exit"):break
  if q:
   try:
    x=ask(r,q);print("\nANSWER\n"+x["answer"]+"\n"+json.dumps(x["provenance"],indent=2)+"\n"+json.dumps(x["metrics"],indent=2))
   except Exception as e:print("ERROR:",e)
if __name__=="__main__":main()