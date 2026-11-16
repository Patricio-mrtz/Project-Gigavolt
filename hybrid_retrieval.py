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