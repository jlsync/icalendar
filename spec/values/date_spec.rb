require 'spec_helper'

describe Icalendar::Values::Date do

  subject { described_class.new value, params }
  let(:value) { '20140209' }
  let(:params) { {} }

  describe "#==" do
    let(:other) { described_class.new value }

    it "is equivalent to another Icalendar::Values::Date" do
      expect(subject).to eq other
    end

    context "differing params" do
      let(:params) { {"x-custom-param": "param-value"} }

      it "is no longer equivalent" do
        expect(subject).not_to eq other
      end
    end
  end

  describe 'date parsing boundaries' do
    it 'parses valid leap day dates' do
      date = described_class.new '20240229'
      expect(date.value).to eq ::Date.new(2024, 2, 29)
    end

    it 'raises FormatError on invalid leap day and out-of-range dates' do
      %w[20230229 20241301 20240132 2024010a].each do |bad|
        expect { described_class.new(bad) }.to raise_error(Icalendar::Values::Date::FormatError)
      end
    end

    it 'accepts frozen params like Value::EMPTY_HASH without raising FrozenError' do
      date = described_class.new('20240229', Icalendar::Value::EMPTY_HASH)
      expect(date.value).to eq ::Date.new(2024, 2, 29)
    end
  end
end
