#!/bin/bash
set -e
exec > >(tee -a /var/log/milestone4.log) 2>&1

export DEBIAN_FRONTEND=noninteractive
export TMPDIR=/var/tmp
export TOKENIZERS_PARALLELISM=false
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1

BASE=/home/ubuntu/vector_milestone

# ============================================================
# MEMORY - 2 GB SWAP
# ============================================================

if ! swapon --show | grep -q "/swapfile"; then

    if [ ! -f /swapfile ]; then

        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile

    fi

    swapon /swapfile

fi

grep -q "^/swapfile " /etc/fstab || \
echo '/swapfile none swap sw 0 0' >> /etc/fstab

echo "Memory:"
free -h


# ============================================================
# MILESTONE 4 SETUP
# ============================================================

apt-get update -y

apt-get install -y \
wget \
unzip \
python3-pip \
python3-venv

python3 -m venv /opt/vector_env

/opt/vector_env/bin/pip install \
--no-cache-dir \
-U pip

/opt/vector_env/bin/pip install \
--no-cache-dir \
torch \
--extra-index-url https://download.pytorch.org/whl/cpu

/opt/vector_env/bin/pip install \
--no-cache-dir \
sentence-transformers \
'chromadb>=1.0,<2' \
pypdf \
numpy \
pandas \
matplotlib \
jupyter


# ============================================================
# DOWNLOAD PROFESSOR DATA
# ============================================================

mkdir -p "$BASE/data"

cd "$BASE"

wget -O UnstructuredData.zip \
https://622.gomillion.org/data/UnstructuredData.zip

unzip -o \
UnstructuredData.zip \
-d "$BASE/data"


# ============================================================
# VECTOR SCRIPT
# ============================================================

cat > "$BASE/vector_milestone.py" <<'PY'
import argparse
import hashlib
import re
import time

from datetime import datetime, timezone
from pathlib import Path

import chromadb
import numpy as np
import pandas as pd

from pypdf import PdfReader
from sentence_transformers import SentenceTransformer


BASE = Path("/home/ubuntu/vector_milestone")

DATA = BASE / "data"

DB = BASE / "chroma_db"

COLLECTION = "gigavolt_vectors"

MODEL = "all-MiniLM-L6-v2"

CHUNK_SIZE = 256

OVERLAP = 50

M = 16

EF_CONSTRUCTION = 100

EF_SEARCH = 50

K = 5


QUERIES = [
    "What are common equipment failures?",
    "How is overheating diagnosed or resolved?",
    "What maintenance is recommended for equipment?",
    "What warranty or service issues are described?",
    "What actions are taken to fix technical problems?"
]


# ============================================================
# LOAD MODEL
# ============================================================

def load_model():

    return SentenceTransformer(
        MODEL
    )


# ============================================================
# DOCUMENT DISCOVERY
# ============================================================

def documents():

    allowed = {
        ".pdf",
        ".txt",
        ".md"
    }

    return sorted(

        p for p in DATA.rglob("*")

        if p.is_file()

        and p.suffix.lower() in allowed

    )


# ============================================================
# DOCUMENT READING
# ============================================================

def read_document(path):

    try:

        if path.suffix.lower() == ".pdf":

            output = []

            with path.open("rb") as file:

                reader = PdfReader(file)

                for page in reader.pages:

                    text = page.extract_text() or ""

                    if text.strip():

                        output.append(text)

            return "\n".join(output)

        return path.read_text(
            encoding="utf-8",
            errors="ignore"
        )

    except Exception as error:

        print(
            f"WARNING: {path}: {error}"
        )

        return ""


# ============================================================
# SENTENCE SPLITTING
# ============================================================

def sentences(text):

    text = re.sub(
        r"\s+",
        " ",
        text
    ).strip()

    return [

        sentence.strip()

        for sentence in re.split(
            r"(?<=[.!?])\s+",
            text
        )

        if sentence.strip()

    ]


# ============================================================
# TOKEN COUNT
# ============================================================

def token_count(
    text,
    tokenizer
):

    return len(

        tokenizer.encode(

            text,

            add_special_tokens=True,

            truncation=False

        )

    )


# ============================================================
# LONG SENTENCE SPLITTING
# ============================================================

def split_long(
    sentence,
    tokenizer
):

    ids = tokenizer.encode(

        sentence,

        add_special_tokens=False,

        truncation=False

    )

    size = CHUNK_SIZE - 2

    step = size - OVERLAP

    pieces = []

    for start in range(
        0,
        len(ids),
        step
    ):

        part = ids[
            start:start + size
        ]

        if not part:

            break

        text = tokenizer.decode(

            part,

            skip_special_tokens=True

        ).strip()

        if text:

            pieces.append(text)

        if start + size >= len(ids):

            break

    return pieces


# ============================================================
# SENTENCE-AWARE CHUNKING
# ============================================================

def chunk_text(
    text,
    tokenizer
):

    all_sentences = []

    for sentence in sentences(text):

        if token_count(
            sentence,
            tokenizer
        ) <= CHUNK_SIZE:

            all_sentences.append(
                sentence
            )

        else:

            all_sentences.extend(

                split_long(
                    sentence,
                    tokenizer
                )

            )

    chunks = []

    current = []

    for sentence in all_sentences:

        candidate = " ".join(
            current + [sentence]
        )

        if (
            current
            and token_count(
                candidate,
                tokenizer
            ) > CHUNK_SIZE
        ):

            chunks.append(
                " ".join(current)
            )

            overlap = []

            for old in reversed(current):

                overlap.insert(
                    0,
                    old
                )

                if token_count(
                    " ".join(overlap),
                    tokenizer
                ) >= OVERLAP:

                    break

            current = overlap

            while (
                current
                and token_count(
                    " ".join(
                        current + [sentence]
                    ),
                    tokenizer
                ) > CHUNK_SIZE
            ):

                current.pop(0)

        current.append(
            sentence
        )

    if current:

        chunks.append(
            " ".join(current)
        )

    return chunks


# ============================================================
# BUILD CHUNKS + METADATA
# ============================================================

def make_chunks(
    embedder
):

    tokenizer = embedder.tokenizer

    result = []

    timestamp = datetime.now(
        timezone.utc
    ).isoformat()

    files = documents()

    if not files:

        raise RuntimeError(
            "No supported documents found."
        )

    print(
        f"Documents found: {len(files)}"
    )

    for path in files:

        text = read_document(
            path
        )

        if not text.strip():

            continue

        parts = chunk_text(
            text,
            tokenizer
        )

        source = hashlib.sha1(
            str(path).encode()
        ).hexdigest()[:8]

        for index, content in enumerate(
            parts
        ):

            result.append({

                "id":
                    f"{source}_{index}",

                "text":
                    content,

                "source_file":
                    path.name,

                "chunk_index":
                    index,

                "token_count":
                    token_count(
                        content,
                        tokenizer
                    ),

                "timestamp":
                    timestamp

            })

        print(
            f"{path.name}: "
            f"{len(parts)} chunks"
        )

    if not result:

        raise RuntimeError(
            "No chunks created."
        )

    print(
        f"Total chunks: "
        f"{len(result)}"
    )

    print(
        f"Sample: "
        f"{result[0]['source_file']} | "
        f"{result[0]['token_count']} tokens"
    )

    print(
        result[0]["text"][:400]
    )

    return result


# ============================================================
# CHROMADB
# ============================================================

def client():

    return chromadb.PersistentClient(
        path=str(DB)
    )


def create_collection():

    chroma = client()

    try:

        chroma.delete_collection(
            COLLECTION
        )

    except Exception:

        pass

    return chroma.create_collection(

        name=COLLECTION,

        configuration={

            "hnsw": {

                "space":
                    "cosine",

                "ef_construction":
                    EF_CONSTRUCTION,

                "ef_search":
                    EF_SEARCH,

                "max_neighbors":
                    M

            }

        }

    )


def get_collection():

    return client().get_collection(
        COLLECTION
    )


# ============================================================
# EMBEDDINGS + VECTOR INGESTION
# ============================================================

def build():

    embedder = load_model()

    chunks = make_chunks(
        embedder
    )

    collection = create_collection()

    batch = 8

    for start in range(
        0,
        len(chunks),
        batch
    ):

        part = chunks[
            start:start + batch
        ]

        texts = [

            chunk["text"]

            for chunk in part

        ]

        embeddings = embedder.encode(

            texts,

            normalize_embeddings=True,

            show_progress_bar=False,

            batch_size=8

        )

        collection.add(

            ids=[

                chunk["id"]

                for chunk in part

            ],

            documents=texts,

            embeddings=
                embeddings.tolist(),

            metadatas=[

                {

                    "source_file":
                        chunk["source_file"],

                    "chunk_index":
                        chunk["chunk_index"],

                    "token_count":
                        chunk["token_count"],

                    "timestamp":
                        chunk["timestamp"]

                }

                for chunk in part

            ]

        )

        print(

            f"Stored "

            f"{min(start + batch, len(chunks))}"

            f"/{len(chunks)}"

        )

    print(
        f"Collection: {COLLECTION}"
    )

    print(
        f"Chunks: {collection.count()}"
    )

    print(
        f"HNSW M={M}, "
        f"ef_construction={EF_CONSTRUCTION}, "
        f"ef_search={EF_SEARCH}"
    )

    return collection, embedder


# ============================================================
# VECTOR SEARCH
# ============================================================

def search(
    collection,
    embedder,
    query
):

    vector = embedder.encode(

        query,

        normalize_embeddings=True

    )

    return collection.query(

        query_embeddings=[
            vector.tolist()
        ],

        n_results=min(
            K,
            collection.count()
        ),

        include=[
            "documents",
            "metadatas",
            "distances"
        ]

    )


# ============================================================
# EXACT SEARCH FOR RECALL
# ============================================================

def exact(
    collection,
    vector
):

    data = collection.get(
        include=[
            "embeddings"
        ]
    )

    ids = np.array(
        data["ids"]
    )

    vectors = np.asarray(
        data["embeddings"],
        dtype=np.float32
    )

    if len(vectors) == 0:

        return []

    vectors /= np.clip(

        np.linalg.norm(
            vectors,
            axis=1,
            keepdims=True
        ),

        1e-12,

        None

    )

    vector = np.asarray(
        vector,
        dtype=np.float32
    )

    vector /= max(
        np.linalg.norm(vector),
        1e-12
    )

    scores = vectors @ vector

    top = np.argsort(
        -scores
    )[:min(K, len(ids))]

    return ids[top].tolist()


# ============================================================
# HNSW BENCHMARK
# ============================================================

def benchmark(
    collection,
    embedder,
    runs=10
):

    rows = []

    count = collection.count()

    for ef in [
        10,
        50,
        100
    ]:

        collection.modify(

            configuration={

                "hnsw": {

                    "ef_search":
                        ef

                }

            }

        )

        for query in QUERIES:

            vector = embedder.encode(

                query,

                normalize_embeddings=True

            )

            exact_ids = exact(
                collection,
                vector
            )

            collection.query(

                query_embeddings=[
                    vector.tolist()
                ],

                n_results=min(
                    K,
                    count
                )

            )

            for _ in range(runs):

                start = (
                    time.perf_counter()
                )

                result = collection.query(

                    query_embeddings=[
                        vector.tolist()
                    ],

                    n_results=min(
                        K,
                        count
                    ),

                    include=[
                        "distances"
                    ]

                )

                latency = (

                    time.perf_counter()
                    - start

                ) * 1000

                approx = (
                    result["ids"][0]
                )

                recall = (

                    len(

                        set(approx)

                        & set(exact_ids)

                    )

                    / max(
                        1,
                        len(exact_ids)
                    )

                )

                rows.append({

                    "ef_search":
                        ef,

                    "query":
                        query,

                    "latency_ms":
                        latency,

                    "recall_at_5":
                        recall

                })

    collection.modify(

        configuration={

            "hnsw": {

                "ef_search":
                    EF_SEARCH

            }

        }

    )

    raw = pd.DataFrame(
        rows
    )

    summary = (

        raw

        .groupby(
            "ef_search"
        )

        .agg(

            median_latency_ms=(
                "latency_ms",
                "median"
            ),

            mean_latency_ms=(
                "latency_ms",
                "mean"
            ),

            p95_latency_ms=(

                "latency_ms",

                lambda values:
                    np.percentile(
                        values,
                        95
                    )

            ),

            mean_recall_at_5=(
                "recall_at_5",
                "mean"
            )

        )

        .reset_index()

    )

    raw.to_csv(
        BASE / "benchmark_raw.csv",
        index=False
    )

    summary.to_csv(
        BASE / "benchmark_summary.csv",
        index=False
    )

    print(
        summary.to_string(
            index=False
        )
    )

    return raw, summary


# ============================================================
# INTERACTIVE SEARCH
# ============================================================

def query_loop():

    collection = get_collection()

    embedder = load_model()

    print(
        f"Chunks indexed: "
        f"{collection.count()}"
    )

    print(
        "Type query, benchmark, stats, or quit"
    )

    while True:

        query = input(
            "\nQuery: "
        ).strip()

        if query.lower() in {
            "quit",
            "exit",
            "q"
        }:

            break

        if not query:

            continue

        if query.lower() == "stats":

            print(
                f"Chunks: "
                f"{collection.count()}"
            )

            continue

        if query.lower() == "benchmark":

            benchmark(
                collection,
                embedder
            )

            continue

        result = search(
            collection,
            embedder,
            query
        )

        for i,(document,metadata,distance) in enumerate(

            zip(

                result["documents"][0],

                result["metadatas"][0],

                result["distances"][0]

            ),

            1

        ):

            print(

                f"\n[{i}] "

                f"{metadata['source_file']} "

                f"| chunk "

                f"{metadata['chunk_index']} "

                f"| similarity "

                f"{1-float(distance):.3f}"

            )

            print(
                document[:350]
            )


# ============================================================
# COMMAND LINE
# ============================================================

def main():

    parser = argparse.ArgumentParser()

    parser.add_argument(

        "--mode",

        choices=[
            "build",
            "search",
            "benchmark",
            "all"
        ],

        default="all"

    )

    parser.add_argument(

        "--runs",

        type=int,

        default=10

    )

    args = parser.parse_args()

    if args.mode == "build":

        build()

    elif args.mode == "search":

        query_loop()

    elif args.mode == "benchmark":

        benchmark(

            get_collection(),

            load_model(),

            args.runs

        )

    else:

        collection, embedder = build()

        benchmark(

            collection,

            embedder,

            args.runs

        )

        query_loop()


if __name__ == "__main__":

    main()

PY


# ============================================================
# JUPYTER BENCHMARK NOTEBOOK
# ============================================================

cat > "$BASE/vector_benchmark.ipynb" <<'NB'
{
 "cells":[
  {
   "cell_type":"markdown",
   "metadata":{},
   "source":[
    "# Milestone 4 HNSW Benchmark"
   ]
  },
  {
   "cell_type":"code",
   "execution_count":null,
   "metadata":{},
   "outputs":[],
   "source":[
    "import pandas as pd\n",
    "summary=pd.read_csv('benchmark_summary.csv')\n",
    "summary"
   ]
  },
  {
   "cell_type":"code",
   "execution_count":null,
   "metadata":{},
   "outputs":[],
   "source":[
    "import pandas as pd\n",
    "import matplotlib.pyplot as plt\n",
    "raw=pd.read_csv('benchmark_raw.csv')\n",
    "raw.boxplot(column='latency_ms',by='ef_search')\n",
    "plt.suptitle('')\n",
    "plt.title('HNSW Query Latency')\n",
    "plt.xlabel('ef_search')\n",
    "plt.ylabel('Latency (ms)')\n",
    "plt.show()\n",
    "summary.plot(x='ef_search',y='mean_recall_at_5',marker='o',legend=False)\n",
    "plt.ylim(0,1.05)\n",
    "plt.title('Recall@5')\n",
    "plt.ylabel('Recall')\n",
    "plt.show()"
   ]
  }
 ],
 "metadata":{
  "kernelspec":{
   "display_name":"Python 3",
   "language":"python",
   "name":"python3"
  }
 },
 "nbformat":4,
 "nbformat_minor":5
}
NB


# ============================================================
# BUILD VECTOR DATABASE
# ============================================================

chown -R ubuntu:ubuntu \
"$BASE"

sudo -u ubuntu \
env HOME=/home/ubuntu \
TOKENIZERS_PARALLELISM=false \
OMP_NUM_THREADS=1 \
MKL_NUM_THREADS=1 \
/opt/vector_env/bin/python \
"$BASE/vector_milestone.py" \
--mode build


# ============================================================
# RUN BENCHMARK
# ============================================================

sudo -u ubuntu \
env HOME=/home/ubuntu \
TOKENIZERS_PARALLELISM=false \
OMP_NUM_THREADS=1 \
MKL_NUM_THREADS=1 \
/opt/vector_env/bin/python \
"$BASE/vector_milestone.py" \
--mode benchmark


# ============================================================
# COMPLETE
# ============================================================

echo
echo "============================================================"
echo "MILESTONE 4 COMPLETE"
echo "============================================================"

echo
echo "Memory:"
free -h

echo
echo "Dataset:"
echo "https://622.gomillion.org/data/UnstructuredData.zip"

echo
echo "Vector database:"
echo "$BASE/chroma_db"

echo
echo "Collection:"
echo "gigavolt_vectors"

echo
echo "Search:"
echo "cd $BASE"
echo "source /opt/vector_env/bin/activate"
echo "python vector_milestone.py --mode search"

echo
echo "Benchmark:"
echo "python vector_milestone.py --mode benchmark"

echo
echo "Files:"
echo "$BASE/vector_milestone.py"
echo "$BASE/vector_benchmark.ipynb"
echo "$BASE/benchmark_raw.csv"
echo "$BASE/benchmark_summary.csv"