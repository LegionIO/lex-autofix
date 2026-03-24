# Changelog

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
