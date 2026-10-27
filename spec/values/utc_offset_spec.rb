require 'spec_helper'

describe Icalendar::Values::UtcOffset do

  subject { described_class.new value }

  describe '#value_ical' do
    let(:value) { '-050000' }

    it 'does not output seconds unless required' do
      expect(subject.value_ical).to eq '-0500'
    end

    context 'with seconds' do
      let(:value) { '+023030' }
      specify { expect(subject.value_ical).to eq '+023030' }
    end

    it 'honours reader and sign overrides in subclasses' do
      custom_class = Class.new(described_class) do
        def hours; 7; end
        def minutes; 8; end
        def seconds; 9; end
        def behind?; false; end
      end
      offset = custom_class.new('-0500')

      expect(offset.value_ical).to eq '+070809'
      expect(offset.to_s).to eq '+07:08:09'
    end

    it 'honours delegated reader customization through method_missing' do
      custom_class = Class.new(described_class) do
        def method_missing(name, *args, &block)
          result = super
          name == :hours ? result + 1 : result
        end
      end
      offset = custom_class.new('+0500')

      expect(offset.value_ical).to eq '+0600'
      expect(offset.to_s).to eq '+06:00'
    end

    { value_ical: '-0500', to_s: '-05:00' }.each do |method, expected|
      it "returns a fresh mutable string from #{method}" do
        first = subject.public_send(method)
        second = subject.public_send(method)

        expect(first).to eq expected
        expect(second).to eq expected
        expect(first).not_to be_frozen
        expect(second).not_to equal first
        first.replace('changed output')
        expect(second).to eq expected
        expect(subject.public_send(method)).to eq expected
      end
    end
  end

  describe '#behind?' do
    context 'negative offset' do
      let(:value) { '-0500' }
      specify { expect(subject.behind?).to be true }
    end

    context 'positive offset' do
      let(:value) { '+0200' }
      specify { expect(subject.behind?).to be false }
    end

    context 'no offset' do
      let(:value) { '-0000' }
      specify { expect(subject.behind?).to be false }

      it 'does not allow override' do
        subject.behind = true
        expect(subject.behind?).to be false
      end

      it 'renders negative zero as positive zero' do
        expect(subject.value_ical).to eq '+0000'
        expect(subject.to_s).to eq '+00:00'
      end
    end
  end

  describe 'field access' do
    subject { described_class.new '-0530' }

    it 'is backed by a Struct of the offset parts' do
      expect(subject.value).to be_a Icalendar::Values::UtcOffset::Parts
      expect(subject.value.to_h).to eq(behind: true, hours: 5, minutes: 30, seconds: 0)
    end

    it 'writes parts through setters' do
      subject.minutes = 45
      expect(subject.value_ical).to eq '-0545'
    end

    it 'copies another offset' do
      expect(described_class.new(subject).value_ical).to eq '-0530'
    end

    it 'reads fields from a replacement delegate after rendering' do
      expect(subject.value_ical).to eq '-0530'
      expect(subject.to_s).to eq '-05:30'
      subject.__setobj__(described_class::Parts.new(behind: false, hours: 2, minutes: 30, seconds: 5))

      expect([subject.hours, subject.minutes, subject.seconds]).to eq [2, 30, 5]
      expect(subject.value_ical).to eq '+023005'
      expect(subject.to_s).to eq '+02:30:05'
    end

    it 'forwards blocks to readers on a replacement delegate' do
      parts_class = Class.new(described_class::Parts) do
        def hours
          block_given? ? yield(super) : super
        end
      end
      subject.__setobj__(parts_class.new(behind: false, hours: 5, minutes: 0, seconds: 0))

      expect(subject.hours { |hours| hours * 2 }).to eq 10
    end
  end
end
