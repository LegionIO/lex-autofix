# lex-autofix

Autonomous error fix agent for LegionIO. Subscribes to structured exception events from the `legion.logging` exchange, batches and deduplicates errors by fingerprint, triages them via LLM, manages GitHub issues, and opens PRs with automated code fixes.

## Architecture

```
legion.logging exchange
  legion.logging.exception.warn.#  ─┐
  legion.logging.exception.error.# ─┼─> autofix.ingest queue --> [LogConsumer] --> [BatchBuffer]
  legion.logging.exception.fatal.# ─┘                                                    │
                                                                                          ▼
                                                                               [Pipeline Runner]
                                                                          triage -> diagnose -> fix -> ship
```

### Event Payload

Each consumed message is a structured exception payload with the following fields:

| Field | Description |
|---|---|
| `exception_class` | Ruby exception class name (e.g. `NoMethodError`) |
| `message` | Exception message string |
| `backtrace` | Array of backtrace lines |
| `caller_file` | Source file where the exception originated |
| `caller_line` | Line number within `caller_file` |
| `caller_function` | Method name at the call site |
| `gem_name` | Name of the gem that raised the exception |
| `gem_version` | Version of that gem |
| `component_type` | Component type (runner, actor, helper, etc.) |
| `error_fingerprint` | Stable hash for deduplication across occurrences |
| `handled` | Whether the exception was caught and handled |
| `lex` | Extension name (used as suggested repo target) |
| `user` | Identity of the user or caller at the time of the error |
| `task_id` | Task ID if the error occurred within a task |
| `conversation_id` | Conversation ID if the error occurred during a chat session |

### BatchBuffer

Events are grouped by `error_fingerprint` (falling back to `lex:exception_class` when no fingerprint is present). A flush is triggered when any group reaches `batch.count_threshold` events or the `batch.window_seconds` time window elapses.

### Pipeline

`handle_log_event` checks the fingerprint cache before buffering:

- `autofix:wip:<fingerprint>` — a fix is in progress; skip
- `autofix:fixed:<fingerprint>` — already resolved; skip

On flush, the pipeline runs: **triage** (LLM clusters actionable vs transient errors) → **diagnose** (search or create a GitHub issue) → **fix** (`Fix` runner extracts file paths from `caller_file` and `backtrace`, applies LLM-generated edits, validates with rspec + rubocop) → **ship** (commit, push branch, open PR).

Only active when `Legion::LLM.started?` returns true.

## Installation

Add to your Gemfile:

```ruby
gem 'lex-autofix'
```

## Configuration

| Setting | Default | Purpose |
|---|---|---|
| `autofix.batch.window_seconds` | `300` | Time window before batch flush |
| `autofix.batch.count_threshold` | `3` | Error count per group to trigger flush |
| `autofix.llm.max_retries` | `3` | Max LLM fix attempts before issue-only |
| `autofix.github.token` | `nil` | GitHub PAT (supports `vault://`) |
| `autofix.github.org` | `LegionIO` | GitHub org for issue and PR operations |
| `autofix.checkout_dir` | `~/.legionio/autofix/` | Temp directory for repo checkouts |

## License

MIT
