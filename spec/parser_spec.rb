require 'spec_helper'

describe Icalendar::Parser do
  subject { described_class.new source, false }
  let(:source) { File.read File.join(File.dirname(__FILE__), 'fixtures', fn) }

  describe '#parse' do
    context 'reversed_timezone.ics' do
      let(:fn) { 'reversed_timezone.ics' }

      it 'correctly parses the event timezone' do
        event = subject.parse.first.events.first
        expect(event.dtstart.utc_offset).to eq -25200
      end
    end

    context 'single_event.ics' do
      let(:fn) { 'single_event.ics' }

      it 'returns an array of calendars' do
        parsed = subject.parse
        expect(parsed).to be_instance_of Array
        expect(parsed.count).to eq 1
        expect(parsed[0]).to be_instance_of Icalendar::Calendar
      end

      it 'properly splits multi-valued lines' do
        event = subject.parse.first.events.first
        expect(event.geo).to eq [37.386013,-122.0829322]
      end

      it 'saves params' do
        event = subject.parse.first.events.first
        expect(event.dtstart.ical_params).to eq('tzid' => ['US-Mountain'])
      end
    end
    context 'recurrence.ics' do
      let(:fn) { 'recurrence.ics' }
      it 'correctly parses the exdate array' do
        event = subject.parse.first.events.first
        ics = event.to_ical
        expect(ics).to match 'EXDATE;VALUE=DATE:20120323,20130323'
      end
    end
    context 'event.ics' do
      let(:fn) { 'event.ics' }

      before { subject.component_class = Icalendar::Event }

      it 'returns an array of events' do
        parsed = subject.parse
        expect(parsed).to be_instance_of Array
        expect(parsed.count).to be 1
        expect(parsed[0]).to be_instance_of Icalendar::Event
      end
    end
    context 'events.ics' do
      let(:fn) { 'two_events.ics' }

      before { subject.component_class = Icalendar::Event }

      it 'returns an array of events' do
        events = subject.parse
        expect(events.count).to be 2
        expect(events.first.uid).to eq("bsuidfortestabc123")
        expect(events.last.uid).to eq("uid-1234-uid-4321")
      end
    end
    context 'tzid_search.ics' do
      let(:fn) { 'tzid_search.ics' }

      it 'correctly sets the weird tzid' do
        parsed = subject.parse
        event = parsed.first.events.first
        expect(event.dtstart.utc).to eq Time.parse("20180104T150000Z")
      end
    end
    context 'custom_component.ics' do
      let(:fn) { 'custom_component.ics' }

      it 'correctly handles custom named components' do
        parsed = subject.parse
        calendar = parsed.first
        expect(calendar.custom_component('x_event_series').size).to eq 1
        expect(calendar.custom_component('X-EVENT-SERIES').size).to eq 1
      end
    end
  end

  describe '#parse with escaped property delimiters' do
    { 'categories' => ',', 'description' => ';' }.each do |property, delimiter|
      context property do
        backslash = "\\"
        {
          'an unescaped delimiter' => ["A#{delimiter}B", ['A', 'B']],
          'a leading empty value' => ["#{delimiter}A", ['', 'A']],
          'an empty value between delimiters' => ["A#{delimiter}#{delimiter}B", ['A', '', 'B']],
          'trailing empty values' => ["A#{delimiter}#{delimiter}", ['A']],
          'an escaped delimiter' => ["A#{backslash}#{delimiter}B", "A#{delimiter}B"],
          'a delimiter after an escaped backslash' => ["A#{backslash * 2}#{delimiter}B", ["A#{backslash}", 'B']],
          'an escaped delimiter after an escaped backslash' => ["A#{backslash * 3}#{delimiter}B", "A#{backslash}#{delimiter}B"],
          'a delimiter after two escaped backslashes' => ["A#{backslash * 4}#{delimiter}B", ["A#{backslash * 2}", 'B']],
          'an escaped delimiter before an unescaped delimiter' => ["A#{backslash}#{delimiter}B#{delimiter}C", ["A#{delimiter}B", 'C']]
        }.each do |description, (encoded, expected)|
          context "with #{description}" do
            let(:source) do
              "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n#{property.upcase}:#{encoded}\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
            end

            it 'preserves the decoded values and their boundaries' do
              event = subject.parse.first.events.first
              parsed = event.public_send(property)
              parsed = parsed.first if property == 'categories'

              expect(parsed.value).to eq expected
            end
          end
        end
      end
    end

    context 'with a non-ASCII property name' do
      let(:source) do
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:test\r\n" \
          "BEGIN:VEVENT\r\nUID:1\r\nDTSTAMP:20240101T000000Z\r\n" \
          "X-CAFÉ:ok\r\nSUMMARY:still parsed\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
      end

      it 'does not raise and still parses the remaining properties' do
        expect(subject.parse.first.events.first.summary.value).to eq 'still parsed'
      end
    end

    context 'with mixed-case and hyphenated names' do
      let(:source) do
        "Begin:vCalendar\r\nVERSION:2.0\r\nPRODID:test\r\n" \
          "begin:VEVENT\r\nuid:1\r\nDtStamp:20240101T000000Z\r\n" \
          "Last-Modified:20240102T000000Z\r\nX-Custom-Prop;Some-Param=1:ok\r\nEND:vevent\r\nend:VCALENDAR\r\n"
      end

      it 'normalizes property and component names' do
        event = subject.parse.first.events.first
        expect(event.last_modified.value_ical).to eq '20240102T000000Z'
        expect(event.x_custom_prop.first.value).to eq 'ok'
        expect(event.x_custom_prop.first.ical_params['some-param']).to eq ['1']
      end
    end

    # An ASCII-only source so these examples do not depend on the process locale.
    logging_source = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:test\r\n" \
      "BEGIN:VEVENT\r\nUID:1\r\nDTSTAMP:20240101T000000Z\r\nDTSTART:20240102T090000Z\r\n" \
      "SUMMARY:logged\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

    context 'with a logger at debug level' do
      let(:sink) { StringIO.new }
      let(:source) { logging_source }

      around do |example|
        original = Icalendar.logger
        Icalendar.logger = Icalendar::Logger.new sink, ::Logger::DEBUG
        example.run
      ensure
        Icalendar.logger = original
      end

      it 'still writes the debug messages' do
        subject.parse
        expect(sink.string).to include 'Adding component Event'
        expect(sink.string).to match(/Plan a - parsing|Ignoring timezone/)
      end
    end

    context 'with a duck-typed logger that only accepts a message argument' do
      let(:logger_class) do
        Class.new do
          attr_accessor :level
          attr_reader :messages

          def initialize(level)
            @level = level
            @messages = []
          end

          %w[debug info warn error fatal].each_with_index do |severity, index|
            define_method(severity) { |message| @messages << message }
            define_method("#{severity}?") { index >= @level }
          end
        end
      end
      let(:source) { logging_source }

      around do |example|
        original = Icalendar.logger
        example.run
      ensure
        Icalendar.logger = original
      end

      it 'parses and receives the debug messages at debug level' do
        Icalendar.logger = logger_class.new ::Logger::DEBUG
        subject.parse
        expect(Icalendar.logger.messages).to include 'Adding component Event'
        expect(Icalendar.logger.messages.grep(/Plan a - parsing|Ignoring timezone/)).not_to be_empty
      end

      it 'parses without logging at warn level' do
        Icalendar.logger = logger_class.new ::Logger::WARN
        expect(subject.parse.first.events.size).to eq 1
        expect(Icalendar.logger.messages).to be_empty
      end

      it 'falls back to a numeric level when the logger has no severity predicates' do
        predicate_free = Class.new(logger_class) do
          %w[debug? info? warn? error? fatal?].each { |predicate| undef_method predicate }
        end

        Icalendar.logger = predicate_free.new ::Logger::DEBUG
        expect(Icalendar.logger).not_to respond_to(:debug?)
        subject.parse
        expect(Icalendar.logger.messages).to include 'Adding component Event'

        Icalendar.logger = predicate_free.new ::Logger::WARN
        described_class.new(source, false).parse
        expect(Icalendar.logger.messages).to be_empty
      end

      it 'parses with a bare logger that has neither predicates nor a numeric level' do
        bare = Class.new do
          attr_reader :messages

          def initialize
            @messages = []
          end

          def level
            :debug
          end

          %w[debug info warn error fatal].each do |severity|
            define_method(severity) { |message| @messages << message }
          end
        end
        Icalendar.logger = bare.new
        expect(subject.parse.first.events.first.summary.value).to eq 'logged'
        expect(Icalendar.logger.messages).to include 'Adding component Event'
      end
    end
  end

  describe '#parse with invalid nesting' do
    let(:fn) { 'invalid_nesting.ics' }

    it 'raises a ParseError' do
      expect { subject.parse }.to raise_error Icalendar::Parser::ParseError
    end
  end

  describe '#parse with bad line' do
    let(:fn) { 'single_event_bad_line.ics' }

    it 'returns an array of calendars' do
      parsed = subject.parse
      expect(parsed).to be_instance_of Array
      expect(parsed.count).to eq 1
      expect(parsed[0]).to be_instance_of Icalendar::Calendar
    end

    it 'properly splits multi-valued lines' do
      event = subject.parse.first.events.first
      expect(event.geo).to eq [37.386013,-122.0829322]
    end

    it 'saves params' do
      event = subject.parse.first.events.first
      expect(event.dtstart.ical_params).to eq('tzid' => ['US-Mountain'])
    end
  end

  describe 'missing date value parameter' do
    let(:fn) { 'single_event_bad_dtstart.ics' }

    it 'falls back to date type for dtstart' do
      event = subject.parse.first.events.first
      expect(event.dtstart).to be_kind_of Icalendar::Values::Date
    end
  end

  describe 'completely bad location value' do
    let(:fn) { 'single_event_bad_location.ics' }

    it 'falls back to string type for location' do
      event = subject.parse.first.events.first
      expect(event.location).to be_kind_of Icalendar::Values::Text
      expect(event.location.value).to eq "1000 Main St Example, State 12345"
    end
  end

  describe 'custom properties with tzid' do
    let(:fn) { 'tz_store_param_bug.ics' }

    it 'parses without error' do
      expect(subject.parse.first).to be_a Icalendar::Calendar
    end

    it 'can be output to ics and re-parsed without error' do
      cal = subject.parse.first
      new_cal = Icalendar::Parser.new(cal.to_ical, false).parse.first
      expect(new_cal).to be_a Icalendar::Calendar
    end
  end
end
