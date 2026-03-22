# lex-autofix

Autonomous error fix agent for LegionIO. Subscribes to the `legion.logging` RabbitMQ exchange, batches and triages errors via LLM, manages GitHub issues, and opens PRs with automated code fixes.

## Installation

Add to your Gemfile:

```ruby
gem 'lex-autofix'
```

## Configuration

| Setting | Default | Purpose |
|---------|---------|---------|
| `autofix.batch.window_seconds` | 300 | Time window before batch flush |
| `autofix.batch.count_threshold` | 3 | Error count per group to trigger flush |
| `autofix.llm.max_retries` | 3 | Max LLM fix attempts before issue-only |
| `autofix.github.token` | nil | GitHub PAT (supports `vault://`) |
| `autofix.github.org` | LegionIO | GitHub org for operations |
| `autofix.checkout_dir` | ~/.legionio/autofix/ | Temp directory for checkouts |

## License

MIT
