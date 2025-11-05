# frozen_string_literal: true

require 'benchmark'

ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift File.join(ROOT, 'lib')

require 'icalendar'

EVENTS = Integer(ENV.fetch('EVENTS', 200))
ITERATIONS = Integer(ENV.fetch('ITERATIONS', 200))

def build_calendar(count)
  cal = Icalendar::Calendar.new
  count.times do |i|
    cal.event do |event|
      t = Time.utc(2024, 1, 1, 12, 0, 0) + i * 3600
      event.dtstart = t
      event.dtend = t + 3600
      event.summary = "Event #{i}"
      event.description = "Description #{i}"
      event.location = "1000 Main St #{i}"
      event.categories = %w[Alpha Beta Gamma]
      event.url = "https://example.com/#{i}"
      event.attendee = [
        Icalendar::Values::CalAddress.new("mailto:person#{i}@example.com"),
        Icalendar::Values::CalAddress.new("mailto:person#{i + 1}@example.com")
      ]
      event.rrule = Icalendar::Values::Recur.new("FREQ=DAILY;COUNT=5")
    end
  end
  cal
end

calendar = build_calendar(EVENTS)
puts "Rendering calendar with #{EVENTS} events, #{ITERATIONS} iterations"
Benchmark.bm(25) do |bm|
  bm.report('Calendar#to_ical') do
    ITERATIONS.times { calendar.to_ical }
  end
end
