# Project Gigavolt — Milestone 6

End-to-end orchestration and RAG pipeline for Project Gigavolt. The project automates data ingestion, incremental processing, relational/document/vector storage, hybrid retrieval, provenance-aware RAG generation, caching, health recovery, and benchmarking.

## Video

https://youtu.be/Kfh-bvY1gts

## Architecture

See [`docs/architecture.md`](docs/architecture.md) and [`docs/architecture.mmd`](docs/architecture.mmd).

## Repository Structure

```text
project-gigavolt-milestone6/
├── README.md
├── user_data/
│   └── milestone6_user_data.sh
├── src/
│   ├── config.py
│   ├── hybrid_retrieval.py
│   ├── rag_pipeline.py
│   └── orchestrator.py
├── aws_dependencies/
│   ├── milestone1_bucket_script.sh
│   ├── milestone3_combined_script.sh
│   ├── milestone4_vector_script.sh
│   └── S3_BUCKETS.md
├── benchmark/
│   ├── prompts.txt
│   ├── benchmark_results.json
│   └── benchmark_analysis.md
├── docs/
│   ├── architecture.md
│   ├── architecture.mmd
│   ├── deployment.md
│   ├── design_decisions.md
│   ├── provenance.md
│   └── Milestone_6_Report.pdf
├── examples/
│   ├── telemetry_sample.json
│   ├── parts_inventory_sample.csv
│   ├── battery_thermal_guide.txt
│   ├── preventive_maintenance.txt
│   └── battery_component_specs.txt
├── requirements.txt
└── .gitignore
```

## Core Pipeline

1. Detect new or changed files.
2. Compare SHA-256 hashes to avoid reprocessing unchanged files.
3. Validate and route incoming data.
4. Load relational CSV data into MariaDB.
5. Load telemetry JSON/NDJSON into MongoDB.
6. Chunk and embed TXT/PDF documents.
7. Upsert changed documents into ChromaDB.
8. Retrieve context across MariaDB, MongoDB, and ChromaDB.
9. Generate a grounded answer with Ollama/Phi.
10. Record provenance and per-stage latency metrics.

## Required S3 Resources

The original AWS deployment expects these S3 objects:

```text
s3://projectmilestone1bucket/bucket.txt
s3://projectmilestone3/Project milestone 3.txt
s3://milestone4.1/new 2.txt
```

The scripts represented by these objects are also included under `aws_dependencies/` for documentation and reproducibility.

## Quick Start on EC2

Use the final deployment script as EC2 User Data:

```text
user_data/milestone6_user_data.sh
```

After setup finishes:

```bash
cd /home/ubuntu/milestone5
source /opt/vector_env/bin/activate
python final/orchestrator.py
python rag_pipeline.py
python rag_pipeline.py --benchmark 1
```

A successful deployment ends with:

```text
MILESTONE 6 READY
```

## Incremental Processing

The orchestrator stores a SHA-256 hash for every processed file. A second run with unchanged inputs produces empty processing arrays instead of loading the same data again.

## Provenance

Answers use source IDs such as `[SQL-1]`, `[MONGO-1]`, and `[VECTOR-1]`. The pipeline records used citations, invalid citations, and whether citations were present. See `docs/provenance.md`.

## Benchmarking

The benchmark uses 20 evaluation prompts and reports P50, P95, P99, QPS, cache performance, and per-stage latency. The measured report shows retrieval is fast relative to local Phi generation; the tested EC2 environment did not achieve the target sub-five-second uncached median.

```bash
python rag_pipeline.py --benchmark 1
```

See `benchmark/benchmark_results.json` and `benchmark/benchmark_analysis.md`.

## Notes

- Graph database support is intentionally not included because it was not required for this submission.
- The included benchmark values are the measured values shown in the submitted Milestone 6 report. Re-run the benchmark on a new instance for fresh measurements.
