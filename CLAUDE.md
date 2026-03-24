# lex-autofix: Autonomous Error Fix Agent

**Level 3 Documentation**
- **Parent**: `/Users/miverso2/rubymine/legion/extensions-agentic/CLAUDE.md`
- **Grandparent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

**Version**: 0.1.4

## What This Does

Subscribes to the `legion.logging` RabbitMQ exchange, batches error events, triages them via LLM, manages GitHub issues, and opens PRs with automated code fixes. Scoped to LegionIO org repos only.

## Architecture

```
legion.logging exchange --> [LogConsumer Actor] --> [BatchBuffer] --> [Pipeline Runner]
Pipeline: batch_triage --> check_github --> attempt_fix --> ship
```

## Key Files

| File | Purpose |
|---|---|
| `helpers/batch_buffer.rb` | In-memory buffer with time window + count threshold flush triggers |
| `helpers/prompts.rb` | LLM prompt templates and JSON schemas for triage and fix |
| `helpers/temp_checkout.rb` | Git clone, file read, edit application, cleanup |
| `runners/triage.rb` | LLM-based error clustering (actionable vs transient) |
| `runners/diagnose.rb` | GitHub issue search, create, comment |
| `runners/fix.rb` | LLM code generation, apply edits, rspec/rubocop validation |
| `runners/ship.rb` | Git commit, push, PR creation, cleanup |
| `runners/pipeline.rb` | Full orchestration: triage -> diagnose -> fix -> ship |
| `actors/log_consumer.rb` | Subscription actor on autofix.ingest queue |
| `transport.rb` | Cross-exchange binding: legion.logging -> autofix.ingest |
| `client.rb` | Standalone client including all runners |

## Dependencies

- `legion-cache` (>= 1.3.11) — sub-gem helper
- `legion-crypt` (>= 1.4.9) — sub-gem helper
- `legion-data` (>= 1.4.17) — sub-gem helper
- `legion-json` (>= 1.2.1) — sub-gem helper
- `legion-llm` (>= 0.3.19) — LLM calls for triage and fix generation
- `legion-logging` (>= 1.3.2) — sub-gem helper
- `legion-settings` (>= 1.3.14) — sub-gem helper
- `legion-transport` (>= 1.3.9) — sub-gem helper
- `lex-github` (>= 0.2) — GitHub issue and PR management

## Settings

| Setting | Default | Purpose |
|---------|---------|---------|
| `autofix.batch.window_seconds` | 300 | Time window before batch flush |
| `autofix.batch.count_threshold` | 3 | Error count per group to trigger flush |
| `autofix.llm.max_retries` | 3 | Max fix attempts before issue-only |
| `autofix.github.token` | nil | GitHub PAT (supports `vault://`) |
| `autofix.github.org` | LegionIO | GitHub org for operations |
| `autofix.checkout_dir` | ~/.legionio/autofix/ | Temp directory for checkouts |

## Design Doc

`docs/plans/2026-03-21-lex-autofix-design.md`
