# Search quality evaluation

Run: `swift run ClippyChecks --eval` (add `--llm` for the on-device-model stages, `--misses` to list failures).
Data: `Sources/ClippyChecks/EvalData.swift` — 40 realistic clips (commands, URLs, code, errors, JSON, addresses, phones,
emails, notes), 40 *paraphrased* queries ("start my containers" for `docker compose up -d`), and 6 unrelated queries that
must return nothing. Measured on Apple silicon, macOS 26+, October 2026. The LLM stages are live and non-deterministic (±1–2 queries).

| Pipeline | Top-1 | Top-3 | MRR | Unrelated queries returning junk |
|---|---|---|---|---|
| Embeddings only — sentence model, raw text | 22% | 40% | 0.34 | 6/6 |
| Embeddings only — sentence model, category-labelled text | 25% | 38% | 0.37 | 6/6 |
| Embeddings only — contextual (transformer) model | 18–22% | 35% | 0.31–0.35 | 6/6 |
| Intent + keywords (no embeddings) | 65% | 72% | 0.69 | 1/6 |
| Hybrid: intent + keywords + sentence embeddings | 70% | 78% | 0.73 | 1/6 |
| Hybrid + contextual embeddings | 68% | 75% | 0.73 | 6/6 |
| Hybrid + on-device LLM expand + select (trust) | 78% | 78% | 0.78 | 0/6 |
| Hybrid + on-device LLM expand + select (soft) | 75% | 88% | 0.80 | 6/6 |
| **Shipped: hybrid + LLM expand + select (balanced)** | **80%** | **88%** | **0.82** | **0/6** |

## What we learned
- Apple's embeddings alone are not good enough for terse clipboard items (≈1 in 4 correct). The contextual model did not help
  and made false positives worse, so it is **not** used.
- Deterministic intent parsing (type words like *link/command/address*, time words, literal keywords) does most of the work.
- The on-device language model closes the *paraphrase* gap (it knows `kill -9`/`lsof` for “kill whatever is using port 3000”)
  in two bounded ways: it suggests related search words, and it picks among **numbered real candidates**. It cannot invent
  an item. “Balanced” keeps its picks first and only appends *strong* deterministic matches.
- Latency: instant hybrid results first; the model refinement lands a few seconds later and is skipped if you already moved the selection.

## Known misses (80% is not 100%)
“log into the production server” (ssh), “regex for validating emails”, “google office location”, “weekday 3am schedule”
(cron). These need world knowledge a small on-device model sometimes lacks. The set is small and written by the developer;
treat the numbers as directional, and extend `EvalData` with real (anonymised) queries before trusting them.

## Resource use (measured, installed release build)
Idle: ~24–33 MB footprint, 0% CPU. Embedding model loads on demand and is released after 60 s idle.
