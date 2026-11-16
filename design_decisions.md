# Design Decisions and Trade-offs

- **MariaDB** stores normalized relational enterprise data such as equipment, service logs, parts, and warranty claims.
- **MongoDB** stores flexible IoT telemetry and supports indexed lookups by timestamp, equipment ID, and error code.
- **ChromaDB** stores document embeddings for semantic similarity retrieval.
- **SentenceTransformer `all-MiniLM-L6-v2`** provides local embedding generation with modest compute requirements.
- **Ollama + Phi** keeps generation local to the EC2 environment, but CPU inference is the main latency bottleneck in the measured benchmark.
- **SHA-256 file hashes** prevent unchanged files from being reprocessed, supporting incremental updates.
- **Five-minute response caching** reduces repeated-query latency.
- **Context limits** keep only the strongest SQL, MongoDB, and vector results and shorten source text to reduce LLM processing overhead. This trades some response detail for lower latency.
- **Service health checks** attempt to restart MariaDB, MongoDB, or Ollama before processing if a service is inactive.
- **Quarantine logging** captures bad relational rows instead of silently losing them.
