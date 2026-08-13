---
name: firecrawl-web
description: "Fetch web content, take screenshots, extract structured data, search the web, and crawl documentation sites. Use when the user needs current web information, asks to scrape a URL, wants a screenshot, needs to extract specific data from a page, or wants to learn about a framework or library."
allowed-tools: ["Bash", "Read", "Write"]
---

# Firecrawl Web Skill

This skill provides web access through Firecrawl's API.

## COST DISCLAIMER (READ FIRST)

Firecrawl is a PAID service. Each page fetched consumes credits from your plan:
- `markdown`, `extract`, `screenshot`: ~1 credit per page
- `crawl`: 1 credit per page crawled (multiply by `--limit`)
- `search`: 1 credit per query + 1 credit per result fetched

ALWAYS set `--limit` on `crawl` to avoid burning through quota.
ALWAYS estimate credit usage before running crawl jobs > 10 pages.

## CHEAPER ALTERNATIVE: defuddle

For simple markdown extraction from a single URL (articles, blog posts, docs pages),
use the `defuddle` skill first. It is FREE (local CLI, no API cost) and handles 90%
of "just give me the clean text" use cases.

Decision tree:
- Single URL, clean text wanted → `defuddle` (FREE)
- Need screenshot / JS-rendered content → `firecrawl-web screenshot`
- Need structured data extraction via schema → `firecrawl-web extract`
- Need search engine results → `firecrawl-web search`
- Need to crawl entire doc site → `firecrawl-web crawl`
- Need dynamic content behind JS / SPA → `firecrawl-web markdown`

## API Key Setup

Firecrawl requires an API key. Store in `.env` at project root:

```bash
# .env (NEVER commit this file)
FIRECRAWL_API_KEY=fc-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Check if key is set before running commands:

```bash
if [ -z "$FIRECRAWL_API_KEY" ]; then
  echo "ERROR: FIRECRAWL_API_KEY not set. Add to .env and source it."
  exit 1
fi
```

Load from `.env` in bash sessions:

```bash
set -a; source .env; set +a
```

Get a key at https://www.firecrawl.dev/ — free tier includes 500 credits.

## Script Location

All commands use the bundled script (installed alongside the skill):
`~/.claude/skills/firecrawl-web/fc.py`

## Bash Discipline

ALWAYS use these patterns in bash examples (run from the repo root):

```bash
# Enable nullglob so empty globs expand to nothing (not literal pattern)
shopt -s nullglob

# Always mkdir -p before writing output
mkdir -p docs/research/scrapes

# Repo-relative paths keep output inside the project
OUTPUT_DIR="docs/research/scrapes"
```

## Rate Limit Handling

Firecrawl free tier: 10 requests/minute. Paid tiers vary. On HTTP 429:

```bash
# Retry with exponential backoff
for attempt in 1 2 3; do
  if python3 ~/.claude/skills/firecrawl-web/fc.py markdown "$URL"; then
    break
  fi
  sleep $((attempt * 15))
done
```

For batch operations, pace requests:

```bash
shopt -s nullglob
URLS=(url1 url2 url3)
for url in "${URLS[@]}"; do
  python3 ~/.claude/skills/firecrawl-web/fc.py markdown "$url"
  sleep 7  # ~8 req/min, safe under 10/min limit
done
```

## Getting Page Content

Fetch any webpage as clean markdown:

```bash
shopt -s nullglob
mkdir -p docs/research/scrapes
python3 ~/.claude/skills/firecrawl-web/fc.py markdown "https://example.com" \
  > docs/research/scrapes/example.md
```

For cleaner output without navigation and footers:

```bash
python3 ~/.claude/skills/firecrawl-web/fc.py markdown "https://example.com" --main-only
```

## Taking Screenshots

Capture a full-page screenshot:

```bash
shopt -s nullglob
mkdir -p docs/research/screenshots
python3 ~/.claude/skills/firecrawl-web/fc.py screenshot "https://example.com" \
  -o docs/research/screenshots/page.png
```

## Extracting Structured Data

Extract specific data using a JSON schema. Create a schema file first:

```json
{
  "type": "object",
  "properties": {
    "title": {"type": "string"},
    "price": {"type": "number"},
    "features": {"type": "array", "items": {"type": "string"}}
  }
}
```

Then extract:

```bash
shopt -s nullglob
mkdir -p config/firecrawl-schemas
python3 ~/.claude/skills/firecrawl-web/fc.py extract "https://example.com/product" \
  --schema config/firecrawl-schemas/product.json
```

Add a prompt for better accuracy:

```bash
python3 ~/.claude/skills/firecrawl-web/fc.py extract "https://example.com/product" \
  --schema config/firecrawl-schemas/product.json \
  --prompt "Extract the main product details"
```

## Searching the Web

Search for current information:

```bash
python3 ~/.claude/skills/firecrawl-web/fc.py search "Python 3.13 new features"
```

Limit results (each result = 1 credit):

```bash
python3 ~/.claude/skills/firecrawl-web/fc.py search "latest React documentation" --limit 3
```

## Crawling Documentation

WARNING: Crawl jobs can consume many credits fast. Always set `--limit`.

Crawl a documentation site to learn about a new framework:

```bash
shopt -s nullglob
mkdir -p docs/research/crawls
python3 ~/.claude/skills/firecrawl-web/fc.py crawl "https://docs.newframework.dev" --limit 30
```

Save pages to a directory:

```bash
shopt -s nullglob
OUTPUT_DIR="docs/research/crawls/example"
mkdir -p "$OUTPUT_DIR"
python3 ~/.claude/skills/firecrawl-web/fc.py crawl "https://docs.example.com" \
  --limit 50 --output "$OUTPUT_DIR"
```

Each page costs one credit. Set a reasonable limit to avoid burning through your quota.

## Cross-References

- `defuddle` skill — FREE local alternative for single-page markdown extraction
- `.claude/skills/ffmpeg-batch/SKILL.md` — same repo-relative path discipline
- `.env` — stores `FIRECRAWL_API_KEY` (gitignored)
