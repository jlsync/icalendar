require 'spec_helper'

describe Icalendar::DowncasedHash do

  subject { described_class.new base }
  let(:base) { {'hello' => 'world'} }

  describe '#[]=' do
    it 'sets a new value' do
      subject['FOO'] = 'bar'
      expect(subject['foo']).to eq 'bar'
    end
  end

  describe '#[]' do
    it 'gets an already set value' do
      subject['foo'] = 'bar'
      expect(subject['FOO']).to eq 'bar'
    end

    it 'returns nil for any key when empty' do
      empty = described_class.new({})
      expect(empty['foo']).to be_nil
      expect(empty[:foo]).to be_nil
    end
  end

  describe '#has_key?' do
    it 'correctly identifies keys in the hash' do
      expect(subject.has_key? 'hello').to be true
      expect(subject.has_key? 'HELLO').to be true
    end

    it 'is false for any key when empty' do
      empty = described_class.new({})
      expect(empty.has_key? 'hello').to be false
      expect(empty.has_key? :hello).to be false
    end
  end

  describe '#delete' do
    context 'no block' do
      it 'removes the key' do
        subject.delete 'HELLO'
        expect(subject.has_key? 'hello').to be false
      end
    end
    context 'with a block' do
      it 'calls the block when the key is not found' do
        expect { |b| subject.delete 'nokey', &b }.to yield_with_args('nokey')
      end
    end
  end

  describe 'DowncasedHash()' do
    it 'returns self when passed an DowncasedHash' do
      expect(Icalendar::DowncasedHash(subject)).to be subject
    end

    it 'wraps a hash in an downcased hash' do
      expect(Icalendar::DowncasedHash(base)).to be_kind_of Icalendar::DowncasedHash
    end
  end
end
