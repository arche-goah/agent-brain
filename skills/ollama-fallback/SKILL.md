---
name: ollama-fallback
description: Local Claude Code setup with Ollama + Qwen3 Coder as a backup on rate limits, or privacy mode for NDA client code.
triggers:
  - ollama
  - qwen
  - lokales modell
  - local model
  - rate limit
  - privacy mode
  - claude code lokal
  - claude code local
  - free claude code
  - offline ai
---

# Ollama Fallback

Local Claude Code setup with Ollama + Qwen3 Coder. Setup per the **taki.gpt** reel (DW6kjNrNBXm).

## Status (2026-04-11)
- **Ollama installed:** YES — v0.20.5 (`brew install ollama`)
- **Path:** `/opt/homebrew/bin/ollama`
- **Models pulled:**
  - `qwen2.5-coder:latest` (4.7 GB) — smoke test PASSED
  - `gemma3:latest` — pulling in the background (Apache 2.0, top 3 open source 2026)
- **Service:** localhost:11434
- **Env var configured:** TBD — see Step 3

## Model recommendation 2026 (from two video imports of 2026-04 (reports not in repo))

| Use case | Model | Why |
|----------|-------|-----|
| Coding in general | `qwen2.5-coder` | proven, fast |
| Complex logic / reasoning | `gemma3` (Gemma 4 when available) | top 3 open source, ~Sonnet 4.6 level, **Apache 2.0** |
| ClientCo (NDA) | `gemma3` | Apache 2.0 = commercial use without restrictions |
| Quick drafts | `qwen2.5-coder` | lower VRAM |

**Source:** Sebastian Kauffmann DE tutorial ("sebastian-kauffmann-gemma4-claude-code" (Instagram, 2026-04-11 — import report not in repo))

## When to use
- **Rate limit hit** — Anthropic API limit reached
- **Privacy mode** — ClientCo client code (NDA, no Anthropic servers)
- **Experiment sessions** — without burning credits
- **Offline work** — travel / on the road without internet

## Setup (3 steps)

### Step 1: Verify Ollama
```bash
ollama --version
# If missing: brew install ollama  (app: brew install --cask ollama)
```
The service runs on `http://localhost:11434`.

### Step 2: Pull a model
```bash
ollama pull qwen2.5-coder    # 8GB, safer start
# or
ollama pull qwen3-coder       # 16GB+ if the machine is strong enough
ollama run qwen2.5-coder "Write hello world"
```

### Step 3: Claude Code routing
Add to `.env`:
```
ANTHROPIC_BASE_URL=http://localhost:11434/v1
ANTHROPIC_API_KEY=ollama-local
```
Per session: `ANTHROPIC_BASE_URL=http://localhost:11434/v1 claude`

## Decision Tree
| Situation | Tool |
|-----------|------|
| Normal work | Anthropic Sonnet 4.6 |
| Complex, max quality | Anthropic Opus 4.6 |
| Rate limit | Ollama Qwen3 Coder |
| ClientCo NDA | Ollama (mandatory) |
| Travel, offline | Ollama (mandatory) |
| Token saving | Ollama |

## Reference
**Source:** "taki-gpt-claude-code-local-ollama" (Instagram, 2026-04-10 — import report not in repo)
**Ollama:** https://ollama.com
