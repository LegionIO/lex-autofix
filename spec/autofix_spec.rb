# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Autofix do
  describe '.remote_invocable?' do
    it 'returns false to enforce local-only dispatch' do
      expect(described_class.remote_invocable?).to be false
    end
  end

  describe '.llm_required?' do
    it 'returns true' do
      expect(described_class.llm_required?).to be true
    end
  end
end
