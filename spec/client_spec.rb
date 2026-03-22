# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/autofix/client'

RSpec.describe Legion::Extensions::Autofix::Client do
  subject(:client) do
    described_class.new(
      github_token: 'ghp_test',
      github_org:   'LegionIO',
      checkout_dir: '/tmp/autofix'
    )
  end

  describe '#initialize' do
    it 'stores constructor kwargs in opts' do
      expect(client.opts).to eq(
        github_token: 'ghp_test',
        github_org:   'LegionIO',
        checkout_dir: '/tmp/autofix'
      )
    end
  end

  describe '#settings' do
    it 'returns options hash' do
      expect(client.settings).to eq({ options: client.opts })
    end
  end

  describe 'runner inclusion' do
    it 'responds to batch_triage from Triage runner' do
      expect(client).to respond_to(:batch_triage)
    end

    it 'responds to check_github from Diagnose runner' do
      expect(client).to respond_to(:check_github)
    end

    it 'responds to attempt_fix from Fix runner' do
      expect(client).to respond_to(:attempt_fix)
    end

    it 'responds to ship from Ship runner' do
      expect(client).to respond_to(:ship)
    end
  end
end
