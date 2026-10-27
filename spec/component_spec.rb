require 'spec_helper'

describe Icalendar::Component do
  describe '#to_ical line folding' do
    subject(:component) { described_class.new 'test' }

    def unfolded(ical)
      ical.gsub(/\r\n[ \t]/, '')
    end

    it 'folds long ASCII content into lines of at most 75 octets' do
      content = 'a' * 500
      component.append_custom_property 'x-long', content

      ical = component.to_ical

      expect(ical.split("\r\n")).to all(satisfy { |line| line.bytesize <= 75 })
      expect(unfolded(ical)).to include "X-LONG:#{content}\r\n"
    end

    it 'folds multi-byte content without splitting characters' do
      content = '日本語' * 100
      component.append_custom_property 'x-long', content

      ical = component.to_ical

      expect(ical.split("\r\n")).to all(satisfy { |line| line.bytesize <= 75 })
      expect(ical).to be_valid_encoding
      expect(unfolded(ical)).to include "X-LONG:#{content}\r\n"
    end

    it 'handles the 75-octet folding boundary' do
      [73, 74].each do |content_length|
        component = described_class.new 'test'
        content = 'a' * content_length
        component.append_custom_property 'x', content

        ical = component.to_ical

        expect(ical.split("\r\n")).to all(satisfy { |line| line.bytesize <= 75 })
        expect(unfolded(ical)).to include "X:#{content}\r\n"
      end
    end
  end

  describe 'generated property accessors' do
    let(:parent) { Class.new(described_class) { optional_property :tags } }
    let(:child) do
      Class.new(parent) do
        attr_reader :setter_calls

        def tags=(value)
          @setter_calls = (@setter_calls || 0) + 1
          super
        end
      end
    end

    it 'initializes a multi property through the possibly overridden setter' do
      component = child.new 'test'
      expect(component.tags).to eq []
      expect(component.setter_calls).to eq 1
      expect(component.tags).to eq []
      expect(component.setter_calls).to eq 1
    end

    [false, true].each do |single_line|
      context "with a #{single_line ? 'single-line' : 'ordinary'} multi-property setter" do
        let(:component_class) do
          Class.new(described_class) do
            optional_property :tags, Icalendar::Values::Text, false, false, single_line
          end
        end
        let(:component) { component_class.new 'test' }

        it 'preserves a value that overrides nil?' do
          value_class = Class.new(Icalendar::Values::Text) do
            def nil?
              true
            end
          end
          value = value_class.new 'present'
          component.tags = value

          expect(component.tags.size).to eq 1
          expect(component.tags.first).to equal value
        end

        it 'clears existing values without keeping a nil entry' do
          component.tags = 'present'
          component.tags = nil

          expect(component.tags).to eq []
        end

        it 'gives each instance its own mutable empty array' do
          other = component_class.new 'other'
          component.tags = nil
          other.tags = nil
          value = Icalendar::Values::Text.new 'added'

          component.tags << value

          expect(component.tags.first).to equal value
          expect(other.tags).to eq []
        end
      end
    end
  end
end
