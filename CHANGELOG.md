# Changelog

## [Unreleased]

## [0.1.7] - 2026-03-27

### Changed
- Update `Transport.additional_e_to_q` to emit three targeted bindings (`legion.logging.exception.warn.#`, `legion.logging.exception.error.#`, `legion.logging.exception.fatal.#`) instead of the broad `legion.#` catch-all
- Update `BatchBuffer#build_key` to use `error_fingerprint` as the group key when present, falling back to `lex:exception_class`
- Update `Pipeline#handle_log_event` to check fingerprint cache (`autofix:wip:` and `autofix:fixed:` keys via `Legion::Cache`) and skip buffering for in-progress or already-fixed errors
- Update `Fix#extract_file_paths` to strip `gem_path` prefix from `caller_file` and backtrace paths using new `strip_gem_prefix` helper
- All keys consumed from events are now flat (`caller_file`, `caller_line`, `gem_path`, `error_fingerprint`, `exception_class`) — no nested `:caller` or `:exception` sub-hashes

## [0.1.6] - 2026-03-25

### Added
- Add repo governance files: CODEOWNERS, dependabot.yml, and reusable CI workflows

## [0.1.5] - 2026-03-24

### Fixed
- Fix actor discovery: rename `module Actors` to `module Actor` (singular) to match framework convention
- Add explicit `runner_class` override to LogConsumer pointing to `Runners::Pipeline` where `handle_log_event` lives

## [0.1.4] - 2026-03-24

### Changed
- Add `caller:` identity parameter to `Legion::LLM.structured` call in `runners/triage.rb` (extension: lex-autofix, operation: triage)
- Add `caller:` identity and `intent: { capability: :reasoning }` parameters to `Legion::LLM.structured` call in `runners/fix.rb` (extension: lex-autofix, operation: fix)

## [0.1.3] - 2026-03-22

### Changed
- Add legion-cache, legion-crypt, legion-data, legion-json, legion-logging, legion-settings, and legion-transport as runtime dependencies
- Replace direct Legion::Logging calls with injected log helper (log.info/log.warn)
- Update spec_helper with real sub-gem helper stubs for standalone spec loading
- Update pipeline_spec Legion::Settings stub to include [] method for helper compatibility

## [0.1.2] - 2026-03-22

### Changed
- Updated `legion-llm` dependency constraint from `>= 0.3` to `>= 0.3.19`

## [0.1.1] - 2026-03-21

### Added
- CI workflow (reusable LegionIO CI + release)

## [0.1.0] - 2026-03-21

### Added
- Initial release: scaffold, batch buffer, triage, diagnose, fix, ship runners
