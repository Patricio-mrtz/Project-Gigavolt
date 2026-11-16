#!/bin/bash
set -e
exec > >(tee -a /var/log/final-milestone.log) 2>&1
export HOME=/root DEBIAN_FRONTEND=noninteractive TOKENIZERS_PARALLELISM=false OMP_NUM_THREADS=1
B=/home/ubuntu/milestone5;V=/opt/vector_env;F=$B/final
apt-get update -y;apt-get install -y awscli curl wget gnupg
aws s3 cp "s3://projectmilestone3/Project milestone 3.txt" /tmp/m3.sh
sed -i 's/\r$//' /tmp/m3.sh;chmod +x /tmp/m3.sh
python3 - <<'PY2'
from pathlib import Path
p=Path('/tmp/m3.sh')
s=p.read_text()
needle='bash /tmp/milestone1.sh'
replacement='''bash /tmp/milestone1.sh
systemctl enable mariadb || true
systemctl start mariadb || galera_new_cluster || true
sleep 3
echo "MariaDB restarted after nested M1"
'''
if 'MariaDB restarted after nested M1' not in s:
 if needle not in s: raise SystemExit('nested M1 call not found')
 s=s.replace(needle,replacement,1)
 p.write_text(s)
print('M3 patched')
PY2
bash /tmp/m3.sh
echo "M1-3 complete"
systemctl enable mariadb||true;systemctl start mariadb||galera_new_cluster||true;sleep 3
systemctl is-active mariadb||true
aws s3 cp "s3://milestone4.1/new 2.txt" /tmp/m4.sh
sed -i 's/\r$//' /tmp/m4.sh;chmod +x /tmp/m4.sh;bash /tmp/m4.sh
echo "M4 complete"
. /etc/os-release;C=$VERSION_CODENAME
curl -fsSL https://pgp.mongodb.com/server-9.asc|gpg --dearmor --yes -o /usr/share/keyrings/mongodb-server-9.gpg
echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-9.gpg] https://repo.mongodb.org/apt/ubuntu $C/mongodb-org/9.0 multiverse">/etc/apt/sources.list.d/mongodb-org-9.0.list
apt-get update -y;apt-get install -y mongodb-org mongodb-mongosh
systemctl enable --now mongod
curl -fsSL https://ollama.com/install.sh|sh
systemctl enable --now ollama
for i in {1..30};do curl -sf localhost:11434/api/tags>/dev/null&&break;sleep 1;done
ollama pull phi
"$V/bin/pip" install --no-cache-dir pymongo pymysql requests pypdf
mkdir -p "$F" "$B"/{results,logs,incoming/{telemetry,relational,docs}}
wget -qO "$B/incoming/telemetry/base.json" https://622.gomillion.org/data/telemetry_data.json
mariadb <<'SQL'
CREATE USER IF NOT EXISTS 'rag_reader'@'localhost' IDENTIFIED BY 'ragpass';
GRANT SELECT, INSERT ON gigavolt_erp.* TO 'rag_reader'@'localhost';FLUSH PRIVILEGES;
SQL
cat >"$B/config.py" <<'PY'
MONGO_URI="mongodb://127.0.0.1:27017";MONGO_DB="gigavolt_iot";MONGO_COLLECTION="telemetry"
MYSQL_HOST="127.0.0.1";MYSQL_USER="rag_reader";MYSQL_PASSWORD="ragpass";MYSQL_DB="gigavolt_erp"
CHROMA_PATH="/home/ubuntu/vector_milestone/chroma_db";CHROMA_COLLECTION="gigavolt_vectors"
EMBED_MODEL="all-MiniLM-L6-v2";OLLAMA_HOST="http://127.0.0.1:11434";OLLAMA_MODEL="phi";TOP_K=5
PY
cat >"$B/hybrid_retrieval.py" <<'PY'
import re,chromadb,pymysql
from pymongo import MongoClient
from sentence_transformers import SentenceTransformer
from config import *
class R:
 def __init__(s):
  s.m=MongoClient(MONGO_URI)[MONGO_DB][MONGO_COLLECTION]
  try:s.q=pymysql.connect(host=MYSQL_HOST,user=MYSQL_USER,password=MYSQL_PASSWORD,database=MYSQL_DB,cursorclass=pymysql.cursors.DictCursor,autocommit=True)
  except:s.q=None
  try:s.e=SentenceTransformer(EMBED_MODEL);s.v=chromadb.PersistentClient(path=CHROMA_PATH).get_collection(CHROMA_COLLECTION)
  except:s.e=s.v=None
 def terms(s,q):
  return [m.group() for p in (r"\bSN[-_ ]?\d+\b",r"\b[A-Z]{1,4}-\d{2,6}\b") if (m:=re.search(p,q,re.I))]
 def words(s,q):
  stop={"what","which","show","the","for","from","with","and","are","our","suppliers","supplier"}
  return [x for x in re.findall(r"[A-Za-z][\w-]{2,}",q.lower()) if x not in stop]
 def find(s,t,v,n=8):
  if not s.q or not v:return []
  with s.q.cursor() as c:c.execute(f"SHOW COLUMNS FROM `{t}`");cs=[x["Field"] for x in c.fetchall()]
  w=[];a=[]
  for x in v:w+=["("+" OR ".join(f"CAST(`{k}` AS CHAR) LIKE %s" for k in cs)+")"];a += [f"%{x}%"]*len(cs)
  with s.q.cursor() as c:c.execute(f"SELECT * FROM `{t}` WHERE "+" OR ".join(w)+f" LIMIT {n}",a);return c.fetchall()
 def sql(s,q):
  v=s.terms(q);o=[]
  try:eq=s.find("equipment_units",v)
  except:eq=[]
  o += [{"type":"SQL","location":"equipment_units","data":x} for x in eq];ids=[x for r in eq for k,x in r.items() if k.lower()=="equipment_id"]
  for t in ("service_logs","warranty_claims"):
   try:z=s.find(t,[str(x) for x in ids]+v)
   except:z=[]
   o += [{"type":"SQL","location":t,"data":x} for x in z]
  if any(x in q.lower() for x in ("supplier","lithium","cell","battery","part","component")):
   try:o += [{"type":"SQL","location":"parts_inventory","data":x} for x in s.find("parts_inventory",s.words(q),20)]
   except:pass
  return o[:20]
 def mongo(s,q):
  a=[];low=q.lower();sn=re.search(r"\bSN[-_ ]?\d+\b",q,re.I)
  if sn:a+=[{"equipment_id":{"$regex":sn.group(),"$options":"i"}}]
  p=[]
  if "battery" in low:p+=["battery"]
  if any(x in low for x in ("temperature","heat","thermal","overheat")):p+=["temp|heat|thermal"]
  if any(x in low for x in ("failure","error","fault")):p+=["fail|error|fault"]
  a += [{"_search_text":{"$regex":x,"$options":"i"}} for x in p]
  if not a:return []
  z=list(s.m.find({"$and":a},{"_id":0,"_search_text":0}).limit(8))
  if not z and p:z=list(s.m.find({"_search_text":{"$regex":"|".join(p),"$options":"i"}},{"_id":0,"_search_text":0}).limit(8))
  return [{"type":"MONGO","location":"telemetry","data":x} for x in z]
 def vector(s,q):
  if s.v is None or not s.v.count():return []
  e=s.e.encode(q,normalize_embeddings=True).tolist();z=s.v.query(query_embeddings=[e],n_results=min(TOP_K,s.v.count()),include=["documents","metadatas","distances"])
  return [{"type":"VECTOR","location":m.get("source_file","docs"),"data":{"chunk":m.get("chunk_index"),"similarity":round(1-float(d),4),"text":t}} for t,m,d in zip(z["documents"][0],z["metadatas"][0],z["distances"][0])]
PY
cat >"$B/rag_pipeline.py" <<'PY'
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
PY
cat >"$F/orchestrator.py" <<'PY'
import csv,hashlib,json,re,subprocess,sys,time
from pathlib import Path
import chromadb,pymysql
from pymongo import MongoClient
from sentence_transformers import SentenceTransformer
sys.path.insert(0,"/home/ubuntu/milestone5");from config import *
B=Path("/home/ubuntu/milestone5");D=[(B/"incoming/telemetry","mongo"),(B/"incoming/relational","sql"),(B/"incoming/docs","vector")];S=B/"results/state.json";Q=B/"results/quarantine.jsonl"
def h(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def state():
 try:return json.loads(S.read_text())
 except:return {"files":{}}
def bad(p,r,e):
 with Q.open("a") as f:f.write(json.dumps({"source":str(p),"reason":str(e),"row":r},default=str)+"\n")
def mongo(p):
 c=MongoClient(MONGO_URI)[MONGO_DB][MONGO_COLLECTION];t=p.read_text(errors="ignore").strip()
 try:x=json.loads(t)
 except json.JSONDecodeError:x=[json.loads(z) for z in t.splitlines() if z.strip()]
 x=next((v for v in x.values() if isinstance(v,list)),[x]) if isinstance(x,dict) else x;n=0
 for r in x:
  if not isinstance(r,dict):bad(p,r,"invalid");continue
  raw=json.dumps(r,sort_keys=True,default=str)
  for k,v in list(r.items()):
   z=re.sub(r"[^a-z0-9]","",k.lower())
   if z in ("equipmentid","serialnumber","unitid"):r["equipment_id"]=v
   if z in ("errorcode","faultcode"):r["error_code"]=v
   if z in ("timestamp","eventtime","datetime"):r["timestamp"]=v
  r["_ingest_hash"]=hashlib.sha256(raw.encode()).hexdigest();r["_search_text"]=raw.lower()[:20000];c.update_one({"_ingest_hash":r["_ingest_hash"]},{"$set":r},upsert=True);n+=1
 for k in ("timestamp","equipment_id","error_code","_ingest_hash"):c.create_index(k)
 return {"rows":n}
def sql(p):
 t=p.stem.lower()
 if t not in {"customers","equipment_units","service_logs","parts_inventory","warranty_claims"}:raise Exception("bad table filename")
 db=pymysql.connect(host=MYSQL_HOST,user=MYSQL_USER,password=MYSQL_PASSWORD,database=MYSQL_DB,autocommit=True);c=db.cursor();c.execute(f"SHOW COLUMNS FROM `{t}`");cols={x[0] for x in c.fetchall()};rows=list(csv.DictReader(p.open()));use=[x for x in rows[0] if x in cols] if rows else []
 if not use:raise Exception("no matching columns")
 n=0
 for r in rows:
  try:c.execute(f"INSERT IGNORE INTO `{t}` ("+",".join(f"`{x}`" for x in use)+") VALUES ("+",".join(["%s"]*len(use))+")",[r.get(x) or None for x in use]);n+=c.rowcount
  except Exception as e:bad(p,r,e)
 c.execute(f"ANALYZE TABLE `{t}`");return {"inserted":n}
def vector(p):
 if p.suffix.lower()==".pdf":
  from pypdf import PdfReader
  t="\n".join((x.extract_text() or "") for x in PdfReader(str(p)).pages)
 else:t=p.read_text(errors="ignore")
 w=t.split();docs=[" ".join(w[i:i+256]) for i in range(0,len(w),206) if w[i:i+256]]
 if not docs:raise Exception("no text")
 fh=h(p);ids=[hashlib.sha256(f"{fh}:{i}".encode()).hexdigest() for i in range(len(docs))];m=[{"source_file":p.name,"chunk_index":i,"file_hash":fh} for i in range(len(docs))];e=SentenceTransformer(EMBED_MODEL).encode(docs,normalize_embeddings=True).tolist();c=chromadb.PersistentClient(path=CHROMA_PATH).get_or_create_collection(CHROMA_COLLECTION)
 try:c.delete(where={"source_file":p.name})
 except:pass
 c.upsert(ids=ids,documents=docs,metadatas=m,embeddings=e);return {"chunks":len(docs)}
def health():
 z={}
 for n in ("mariadb","mongod","ollama"):
  ok=subprocess.run(["systemctl","is-active","--quiet",n]).returncode==0
  if not ok:subprocess.run(["systemctl","restart",n]);time.sleep(2);ok=subprocess.run(["systemctl","is-active","--quiet",n]).returncode==0
  z[n]=ok
 if not all(z.values()):raise Exception(str(z))
 return z
def main():
 s=state();o={"health":health(),"mongo":[],"sql":[],"vector":[],"errors":[]};F={"mongo":mongo,"sql":sql,"vector":vector}
 for d,k in D:
  for p in d.glob("*"):
   if not p.is_file():continue
   x=h(p)
   if s["files"].get(str(p))==x:continue
   try:o[k].append({"file":p.name,**F[k](p)});s["files"][str(p)]=x
   except Exception as e:o["errors"].append({"file":str(p),"error":str(e)})
 S.write_text(json.dumps(s,indent=2));(B/"results/last_pipeline_run.json").write_text(json.dumps(o,indent=2));print(json.dumps(o,indent=2))
 if o["errors"]:sys.exit(1)
if __name__=="__main__":main()
PY
chown -R ubuntu:ubuntu "$B"
"$V/bin/python" -m py_compile "$B"/{config.py,hybrid_retrieval.py,rag_pipeline.py} "$F/orchestrator.py"
sudo -u ubuntu env PYTHONPATH="$B" "$V/bin/python" "$F/orchestrator.py"
echo "MILESTONE 6 READY"
