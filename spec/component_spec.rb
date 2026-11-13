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

        it 'maps arrays with new_property: true cleanly' do
          new_prop_class = Class.new(described_class) do
            optional_property :items, Icalendar::Values::Text, false, true, single_line
          end
          instance = new_prop_class.new 'test'
          nested = Icalendar::Values::Helpers::Array.new(%w[c d], Icalendar::Values::Text, {}, { 'delimiter' => ';' })
          instance.items = ['a', ['b', 'e'], nested]

          ical = instance.to_ical
          expect(ical).to include('ITEMS;VALUE=TEXT:a')
          if single_line
            expect(instance.items.first.value.first.ical_params).to eq('value' => 'TEXT')
          else
            expect(instance.items.first.ical_params).to eq('value' => 'TEXT')
          end
        end
      end
    end

    it 'tracks dynamic additions and in-place replacements to property lists' do
      custom = Class.new(described_class)
      expect(custom.multiple_property?('tags')).to be false
      expect(custom.property_writer('tags')).to be_nil

      custom.multiple_properties << 'tags'
      expect(custom.multiple_property?('tags')).to be true
      expect(custom.property_writer('tags')).to eq :append_tags

      custom.multiple_properties.filter! { false }
      expect(custom.multiple_property?('tags')).to be false
      expect(custom.property_writer('tags')).to be_nil

      custom.single_properties << 'aa'
      expect(custom.property_writer('aa')).to eq :aa=
      custom.single_properties[0] = 'zz'
      expect(custom.single_property?('aa')).to be false
      expect(custom.single_property?('zz')).to be true
      expect(custom.property_writer('zz')).to eq :zz=
    end

    it 'parses with a frozen component subclass without raising FrozenError' do
      frozen_event = Class.new(Icalendar::Component) do
        optional_single_property :summary, Icalendar::Values::Text
      end
      frozen_event.freeze
      frozen_event.property_writer('summary')

      empty_frozen = Class.new(Icalendar::Component)
      empty_frozen.freeze
      expect(empty_frozen.single_property?('summary')).to be false
      expect(empty_frozen.multiple_property?('tags')).to be false
      expect(empty_frozen.property_writer('summary')).to be_nil
    end

    it 'coerces non-String ical_name in to_ical' do
      expect(described_class.new('event', :VEVENT).to_ical).to eq "BEGIN:VEVENT\r\nEND:VEVENT\r\n"
    end

    it 'preserves delimiter context and does not leak UTC tzid when assigning DateTime multi-property arrays directly' do
      event = Icalendar::Event.new
      event.exdate = %w[20240101T120000Z 20240102T120000]

      expect(event.exdate.map(&:tz_utc)).to eq [true, false]
      expect(event.exdate.last.ical_params).to be_empty
      expect(event.exdate.first.context['delimiter']).to eq ','
    end

    it 'refreshes Binary params_ical after replacing ical_params' do
      binary = Icalendar::Values::Binary.new('abc')
      binary.to_ical(Icalendar::Values::Binary)
      binary.ical_params = { 'value' => 'BINARY', 'encoding' => 'BASE64', 'x-foo' => 'bar' }
      expect(binary.to_ical(Icalendar::Values::Binary)).to include(';X-FOO=bar:')
    end

    it 'folds non-ASCII combining grapheme lines at 75 octets cleanly' do
      text = "e\u0301" * 40 # each grapheme is 3 UTF-8 bytes
      folded = Icalendar::Event.new.send(:ical_fold, text)
      lines = folded.split("\r\n")

      expect(lines.all? { |line| line.bytesize <= Icalendar::MAX_LINE_LENGTH }).to be true
      expect(folded.gsub("\r\n ", '')).to eq text
    end
  end
end
