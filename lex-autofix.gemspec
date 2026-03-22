# frozen_string_literal: true

require_relative 'lib/legion/extensions/autofix/version'

Gem::Specification.new do |spec|
  spec.name          = 'lex-autofix'
  spec.version       = Legion::Extensions::Autofix::VERSION
  spec.authors       = ['LegionIO']
  spec.email         = ['admin@legionio.dev']
  spec.summary       = 'Autonomous error fix agent for LegionIO'
  spec.description   = 'Subscribes to legion.logging exchange, triages errors via LLM, and opens PRs with fixes'
  spec.homepage      = 'https://github.com/LegionIO/lex-autofix'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.4'

  spec.files         = Dir['lib/**/*', 'README.md', 'CHANGELOG.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'legion-llm', '>= 0.3'
  spec.add_dependency 'lex-github', '>= 0.2'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
