# Benchmark Analysis

The final benchmark evaluates 20 RAG prompts and reports P50, P95, and P99 latency for SQL, MongoDB, vector search, combined retrieval, LLM generation, and total response time.

The measured results show that retrieval is comparatively fast while Ollama/Phi generation is the primary bottleneck. The measured total P50 latency is above the assignment's five-second target on the tested EC2 environment. Caching significantly improves repeated-query response time.

To reproduce the benchmark:

```bash
cd /home/ubuntu/milestone5
source /opt/vector_env/bin/activate
python rag_pipeline.py --benchmark 1
```

The current pipeline writes the full benchmark output to `results/final_benchmark.json`.
