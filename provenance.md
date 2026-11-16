# Source Provenance

The RAG prompt requires generated factual output to include source identifiers such as `[SQL-1]`, `[MONGO-1]`, and `[VECTOR-1]`. The pipeline records:

- `used`: source IDs cited in the answer
- `invalid`: cited IDs that were not part of the retrieved context
- `has_citations`: whether at least one valid source-style citation appears

This validates citation-ID traceability to retrieved context. It is not a full semantic fact-checker, so claims should still be reviewed against the underlying source records when performing a formal provenance audit.
