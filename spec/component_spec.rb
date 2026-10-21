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
  end
end
