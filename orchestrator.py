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