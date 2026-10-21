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

    it 'appends directly to an existing buffer when provided' do
      buffer = String.new("PRELUDE\r\n")
      component.append_custom_property 'summary', 'Test Event'
      result = component.to_ical(buffer)

      expect(result).to be buffer
      expect(buffer).to start_with "PRELUDE\r\nBEGIN:VTEST\r\n"
      expect(buffer).to end_with "END:VTEST\r\n"
    end

    it 'respects singleton to_ical overrides on property values' do
      component = described_class.new 'test'
      custom_value = Icalendar::Values::Text.new('original')
      def custom_value.to_ical(default_type = nil)
        ":OVERRIDDEN"
      end
      component.append_custom_property 'summary', custom_value

      expect(component.to_ical).to include "SUMMARY:OVERRIDDEN\r\n"
    end

    it 'supports Value subclasses whose value_ical returns a non-String' do
      int_value_class = Class.new(Icalendar::Value) do
        def self.value_type
          'INTEGER'
        end

        def value_ical
          42
        end
      end
      component = described_class.new 'test'
      component.append_custom_property 'count', int_value_class.new(42)

      expect(component.to_ical).to include "COUNT;VALUE=INTEGER:42\r\n"
    end

    it 'supports nested components with a zero-argument to_ical override' do
      subclass = Class.new(described_class) do
        def to_ical
          "BEGIN:VCUSTOM\r\nX-NAME:Custom\r\nEND:VCUSTOM\r\n"
        end
      end
      cal = Icalendar::Calendar.new
      cal.add_custom_component 'custom', subclass.new('custom')

      expect(cal.to_ical).to include "BEGIN:VCUSTOM\r\nX-NAME:Custom\r\nEND:VCUSTOM\r\n"
    end

    it 'supports nested components with a zero-argument singleton to_ical override' do
      cal = Icalendar::Calendar.new
      event = Icalendar::Event.new
      def event.to_ical
        "BEGIN:VEVENT\r\nSUMMARY:Singleton\r\nEND:VEVENT\r\n"
      end
      cal.add_event(event)

      expect(cal.to_ical).to include "BEGIN:VEVENT\r\nSUMMARY:Singleton\r\nEND:VEVENT\r\n"
    end

    it 'supports nested components with keyword-only to_ical overrides' do
      cal = Icalendar::Calendar.new
      event = Icalendar::Event.new
      def event.to_ical(format: nil)
        "BEGIN:VEVENT\r\nSUMMARY:Keyword\r\nEND:VEVENT\r\n"
      end
      cal.add_event(event)

      expect(cal.to_ical).to include "BEGIN:VEVENT\r\nSUMMARY:Keyword\r\nEND:VEVENT\r\n"
    end

    it 'supports nested components with legacy options hash to_ical overrides' do
      subclass = Class.new(described_class) do
        def to_ical(options = {})
          raise "Expected Hash, got #{options.class}" unless options.is_a?(Hash)
          "BEGIN:VOPTIONS\r\nX-NAME:Options\r\nEND:VOPTIONS\r\n"
        end
      end
      cal = Icalendar::Calendar.new
      cal.add_custom_component 'options', subclass.new('options')

      expect(cal.to_ical).to include "BEGIN:VOPTIONS\r\nX-NAME:Options\r\nEND:VOPTIONS\r\n"
    end

    it 'supports nested components with keyword buffer: nil to_ical overrides' do
      subclass = Class.new(described_class) do
        def to_ical(buffer: nil)
          "BEGIN:VBUFFERKW\r\nX-NAME:BufferKw\r\nEND:VBUFFERKW\r\n"
        end
      end
      cal = Icalendar::Calendar.new
      cal.add_custom_component 'bufferkw', subclass.new('bufferkw')

      expect(cal.to_ical).to include "BEGIN:VBUFFERKW\r\nX-NAME:BufferKw\r\nEND:VBUFFERKW\r\n"
    end

    it 'supports nested components with to_ical(buffer = nil) that returns a string without mutating buffer' do
      subclass = Class.new(described_class) do
        def to_ical(buffer = nil)
          "BEGIN:VRETURN\r\nX-NAME:Return\r\nEND:VRETURN\r\n"
        end
      end
      cal = Icalendar::Calendar.new
      cal.add_custom_component 'returning', subclass.new('returning')

      expect(cal.to_ical).to include "BEGIN:VRETURN\r\nX-NAME:Return\r\nEND:VRETURN\r\n"
    end

    it 'supports nested components implemented via method_missing' do
      dynamic_class = Class.new do
        attr_accessor :parent

        def method_missing(method_name, *args, &block)
          if method_name == :to_ical
            "BEGIN:VDYNAMIC\r\nX-NAME:Dynamic\r\nEND:VDYNAMIC\r\n"
          else
            super
          end
        end
      end
      cal = Icalendar::Calendar.new
      cal.add_custom_component 'dynamic', dynamic_class.new

      expect(cal.to_ical).to include "BEGIN:VDYNAMIC\r\nX-NAME:Dynamic\r\nEND:VDYNAMIC\r\n"
    end

    it 'supports Value subclasses with private value_ical or params_ical' do
      priv_value_class = Class.new(Icalendar::Value) do
        def self.value_type
          'PRIVATE'
        end

        private

        def value_ical
          'secret'
        end

        def params_ical
          ';KEY=val'
        end
      end
      component = described_class.new 'test'
      component.append_custom_property 'priv', priv_value_class.new('secret')

      expect(component.to_ical).to include "PRIV;KEY=val:secret\r\n"
    end

    it 'does not rescue NameError raised inside a component to_ical implementation' do
      broken_class = Class.new(described_class) do
        def to_ical
          NonExistentConstantForTest
        end
      end
      cal = Icalendar::Calendar.new
      cal.add_custom_component 'broken', broken_class.new('broken')

      expect { cal.to_ical }.to raise_error(NameError, /NonExistentConstantForTest/)
    end
  end
end
