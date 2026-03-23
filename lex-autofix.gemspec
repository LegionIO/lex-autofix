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

  spec.add_dependency 'legion-cache',     '>= 1.3.11'
  spec.add_dependency 'legion-crypt',     '>= 1.4.9'
  spec.add_dependency 'legion-data',      '>= 1.4.17'
  spec.add_dependency 'legion-json',      '>= 1.2.1'
  spec.add_dependency 'legion-llm',       '>= 0.3.19'
  spec.add_dependency 'legion-logging',   '>= 1.3.2'
  spec.add_dependency 'legion-settings',  '>= 1.3.14'
  spec.add_dependency 'legion-transport', '>= 1.3.9'
  spec.add_dependency 'lex-github',       '>= 0.2'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
