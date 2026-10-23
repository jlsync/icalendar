require 'spec_helper'

describe Icalendar::Value do
  # Values are SimpleDelegators, so Object is not among their ancestors: an unqualified
  # top-level constant in a value method goes through Delegator.const_missing on every call.
  def value_const_misses(&block)
    delegator_const_misses(&block).select do |receiver, _name|
      # Skips Delegator's own `when Object` lookup in the standard library and other gems' delegators.
      receiver.is_a?(Module) && receiver <= Icalendar::Value
    end
  end

  def build_values
    [
      Icalendar::Values::Text.new('text', 'x-list' => %w[a b]),
      Icalendar::Values::Boolean.new('TRUE'),
      Icalendar::Values::Float.new('1.5'),
      Icalendar::Values::Integer.new('2'),
      Icalendar::Values::Binary.new('aGVsbG8='),
      Icalendar::Values::Binary.new('hello'),
      Icalendar::Values::Date.new('20240101'),
      Icalendar::Values::DateTime.new('20240101T120000Z'),
      Icalendar::Values::DateTime.new('20240101T120000', 'tzid' => 'America/New_York'),
      Icalendar::Values::DateOrDateTime.new('20240101').call,
      Icalendar::Values::DateOrDateTime.new('20240101T120000').call,
      Icalendar::Values::DateOrDateTime.new('20240101'),
      Icalendar::Values::DateOrDateTime.new('20240101T120000Z'),
      Icalendar::Values::Time.new('120000'),
      Icalendar::Values::Duration.new(Icalendar::Values::Duration.new('P1D')),
      Icalendar::Values::Period.new('20240101T000000Z/P1D'),
      Icalendar::Values::Period.new('20240101T000000Z/20240102T000000Z'),
      Icalendar::Values::Recur.new(Icalendar::Values::Recur.new('FREQ=DAILY;COUNT=2')),
      Icalendar::Values::UtcOffset.new(Icalendar::Values::UtcOffset.new('+0100')),
      Icalendar::Values::Uri.new('https://example.com/'),
      Icalendar::Values::CalAddress.new('mailto:someone@example.com'),
      Icalendar::Values::Helpers::Array.new(
        [Icalendar::Values::Helpers::Array.new(%w[a], Icalendar::Values::Text), %w[b], Icalendar::Values::Text.new('c'), 'd'],
        Icalendar::Values::Text
      )
    ]
  end

  def exercise(values)
    values.each { |value| value.to_ical Icalendar::Values::Text }
    expect(values.first == values.first.dup).to be true
    date, date_time = values[6], values[7]
    expect(date <=> date_time).to eq(-1)
    expect(date_time <=> date).to eq 1
    period = values[15]
    period.period_start = '20240102T000000Z'
    period.explicit_end = '20240103T000000Z'
    period.duration = 'PT1H'
    period.duration
    period.explicit_end
  end

  it 'records a const_missing from a value class (positive control)' do
    value_class = Class.new(Icalendar::Values::Text)
    # A string body gives the method the class's own lexical scope, as in lib/.
    value_class.class_eval 'def value_ical; Comparable && super; end', __FILE__, __LINE__
    misses = value_const_misses { value_class.new('x').value_ical }
    expect(misses).to include [value_class, :Comparable]
  end

  it 'constructs, compares and renders every value type without Delegator.const_missing' do
    misses = value_const_misses { exercise build_values }
    expect(misses).to be_empty
  end

  it 'falls back from DATE-TIME to DATE without Delegator.const_missing' do
    parsed = nil
    misses = value_const_misses do
      parsed = Icalendar::Values::DateOrDateTime.new('20240101').call
      expect { Icalendar::Values::DateTime.new('2024') }.to raise_error Icalendar::Values::DateTime::FormatError
      expect { Icalendar::Values::Date.new('x') }.to raise_error Icalendar::Values::Date::FormatError
    end
    expect(parsed).to be_a Icalendar::Values::Date
    expect(misses).to be_empty
  end

  it 'parses and re-renders every fixture without Delegator.const_missing' do
    original = Icalendar.logger
    paths = Dir[File.join(__dir__, 'fixtures', '*.ics')].sort
    expect(paths).not_to be_empty
    # Read as UTF-8 so the example does not depend on the process locale.
    sources = paths.to_h { |path| [File.basename(path), File.read(path, encoding: 'UTF-8')] }
    invalid = sources.delete 'invalid_nesting.ics'
    Icalendar.logger = Icalendar::Logger.new File::NULL
    rendered = nil
    misses = value_const_misses do
      rendered = sources.transform_values do |source|
        # A few fixtures hold a bare VEVENT rather than a VCALENDAR.
        component_class = source.start_with?('BEGIN:VEVENT') ? Icalendar::Event : Icalendar::Calendar
        component_class.parse(source).map(&:to_ical)
      end
      expect { Icalendar::Calendar.parse invalid }.to raise_error Icalendar::Parser::ParseError
    end
    expect(rendered).to all(satisfy { |_name, output| output.any? })
    expect(misses).to be_empty
  ensure
    Icalendar.logger = original
  end

  it 'loads the value classes without Delegator.const_missing' do
    # Class bodies run once at require time, so load the gem in a fresh process.
    script = <<~RUBY
      misses = []
      TracePoint.new(:call) do |tp|
        next unless tp.method_id == :const_missing && tp.defined_class == Delegator.singleton_class
        misses << "\#{tp.self}::\#{tp.binding.local_variable_get(tp.parameters.dig(0, 1))}" if tp.self.name.to_s.start_with?('Icalendar::')
      end.enable { require 'icalendar' }
      puts misses
    RUBY
    output = IO.popen([RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), '-e', script], err: File::NULL, &:read)
    expect($?).to be_success
    expect(output.lines).to be_empty
  end
end
