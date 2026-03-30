# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/extensions/autofix/helpers/temp_checkout'

RSpec.describe Legion::Extensions::Autofix::Helpers::TempCheckout do
  let(:tmpdir) { Dir.mktmpdir('autofix_spec_') }
  subject(:checkout) { described_class.new(base_dir: tmpdir) }

  after { FileUtils.rm_rf(tmpdir) }

  describe '#initialize' do
    it 'creates the base directory if it does not exist' do
      new_dir = File.join(tmpdir, 'nested', 'autofix')
      described_class.new(base_dir: new_dir)
      expect(File.directory?(new_dir)).to be(true)
    end
  end

  describe '#clone' do
    context 'when git clone succeeds and branch creation succeeds' do
      before do
        allow(subject).to receive(:system).with('git', 'clone', '--depth', '1', 'https://example.com/repo.git',
                                                anything).and_return(true)
        allow(subject).to receive(:system).with('git', '-C', anything, 'checkout', '-b',
                                                'fix-branch').and_return(true)
      end

      it 'returns success: true with a path under base_dir' do
        result = checkout.clone(repo_url: 'https://example.com/repo.git', branch: 'fix-branch')
        expect(result[:success]).to be(true)
        expect(result[:path]).to start_with(tmpdir)
      end
    end

    context 'when git clone fails' do
      before do
        allow(subject).to receive(:system).with('git', 'clone', '--depth', '1', anything,
                                                anything).and_return(false)
      end

      it 'returns success: false with a reason' do
        result = checkout.clone(repo_url: 'https://example.com/repo.git', branch: 'fix-branch')
        expect(result[:success]).to be(false)
        expect(result[:reason]).to eq('git clone failed')
      end
    end

    context 'when git clone succeeds but branch creation fails' do
      before do
        allow(subject).to receive(:system).with('git', 'clone', '--depth', '1', anything,
                                                anything).and_return(true)
        allow(subject).to receive(:system).with('git', '-C', anything, 'checkout', '-b',
                                                anything).and_return(false)
      end

      it 'returns success: false with a reason' do
        result = checkout.clone(repo_url: 'https://example.com/repo.git', branch: 'fix-branch')
        expect(result[:success]).to be(false)
        expect(result[:reason]).to eq('git checkout -b failed')
      end
    end
  end

  describe '#cleanup' do
    context 'with a real directory inside base_dir' do
      let(:dir_to_remove) { File.join(tmpdir, 'some_checkout') }

      before { FileUtils.mkdir_p(dir_to_remove) }

      it 'removes the directory and returns success: true' do
        result = checkout.cleanup(dir_to_remove)
        expect(result[:success]).to be(true)
        expect(File.exist?(dir_to_remove)).to be(false)
      end
    end

    context 'with a path outside base_dir' do
      it 'refuses to delete and returns success: false' do
        outside_path = Dir.mktmpdir('outside_')
        begin
          result = checkout.cleanup(outside_path)
          expect(result[:success]).to be(false)
          expect(result[:reason]).to eq('path is outside base_dir')
          expect(File.exist?(outside_path)).to be(true)
        ensure
          FileUtils.rm_rf(outside_path)
        end
      end
    end

    context 'with a path traversal attempt' do
      it 'refuses to delete a path resolved outside base_dir' do
        traversal = File.join(tmpdir, '..', 'escaped')
        result = checkout.cleanup(traversal)
        expect(result[:success]).to be(false)
        expect(result[:reason]).to eq('path is outside base_dir')
      end
    end
  end

  describe '#apply_edits' do
    let(:checkout_path) { File.join(tmpdir, 'repo') }

    before { FileUtils.mkdir_p(checkout_path) }

    context 'when old string is found in the file' do
      let(:file_path) { File.join(checkout_path, 'app.rb') }

      before { File.write(file_path, "def foo\n  bar\nend\n") }

      it 'replaces the old string with the new string' do
        edits = [{ 'file' => 'app.rb', 'old' => '  bar', 'new' => '  baz' }]
        result = checkout.apply_edits(checkout_path: checkout_path, edits: edits)
        expect(result[:success]).to be(true)
        expect(File.read(file_path)).to include('  baz')
        expect(File.read(file_path)).not_to include('  bar')
      end
    end

    context 'when the old string is not found in the file' do
      let(:file_path) { File.join(checkout_path, 'app.rb') }

      before { File.write(file_path, "def foo\n  bar\nend\n") }

      it 'returns success: false with a reason' do
        edits = [{ 'file' => 'app.rb', 'old' => 'nonexistent string', 'new' => 'replacement' }]
        result = checkout.apply_edits(checkout_path: checkout_path, edits: edits)
        expect(result[:success]).to be(false)
        expect(result[:reason]).to include('old string not found')
      end
    end

    context 'when the file does not exist' do
      it 'returns success: false with a reason' do
        edits = [{ 'file' => 'missing.rb', 'old' => 'anything', 'new' => 'replacement' }]
        result = checkout.apply_edits(checkout_path: checkout_path, edits: edits)
        expect(result[:success]).to be(false)
        expect(result[:reason]).to include('file not found')
      end
    end

    context 'with multiple edits where the second fails' do
      let(:file1) { File.join(checkout_path, 'a.rb') }

      before { File.write(file1, 'original content') }

      it 'stops on the first failure and returns success: false' do
        edits = [
          { 'file' => 'a.rb', 'old' => 'original content', 'new' => 'updated content' },
          { 'file' => 'missing.rb', 'old' => 'x', 'new' => 'y' }
        ]
        result = checkout.apply_edits(checkout_path: checkout_path, edits: edits)
        expect(result[:success]).to be(false)
        expect(result[:reason]).to include('file not found')
      end
    end
  end

  describe '#read_files' do
    let(:checkout_path) { File.join(tmpdir, 'repo') }

    before { FileUtils.mkdir_p(checkout_path) }

    it 'returns a hash of relative path to file content' do
      File.write(File.join(checkout_path, 'foo.rb'), 'puts :foo')
      result = checkout.read_files(checkout_path: checkout_path, file_paths: ['foo.rb'])
      expect(result['foo.rb']).to eq('puts :foo')
    end

    it 'skips missing files without raising' do
      File.write(File.join(checkout_path, 'exists.rb'), 'hello')
      result = checkout.read_files(checkout_path: checkout_path, file_paths: %w[exists.rb missing.rb])
      expect(result.keys).to contain_exactly('exists.rb')
    end

    it 'caps at 10 files and ignores extras' do
      11.times { |i| File.write(File.join(checkout_path, "file#{i}.rb"), "content#{i}") }
      paths = Array.new(11) { |i| "file#{i}.rb" }
      result = checkout.read_files(checkout_path: checkout_path, file_paths: paths)
      expect(result.size).to eq(10)
    end

    it 'returns an empty hash when no files exist' do
      result = checkout.read_files(checkout_path: checkout_path, file_paths: ['nope.rb'])
      expect(result).to eq({})
    end
  end
end
