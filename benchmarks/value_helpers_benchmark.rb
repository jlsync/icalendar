# frozen_string_literal: true

require 'benchmark'

ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift File.join(ROOT, 'lib')

require 'icalendar'

ITERATIONS = Integer(ENV.fetch('ITERATIONS', 200_000))

def benchmark_value_type(iterations)
  klass = Icalendar::Values::Text
  iterations.times { klass.value_type }
end

def benchmark_array_params(iterations)
  timezone_store = Icalendar::TimezoneStore.new
  array_value = Icalendar::Values::Helpers::Array.new(
    %w[20240301T120000Z 20240401T120000Z 20240501T120000Z],
    Icalendar::Values::DateTime,
    { 'tzid' => ['US/Mountain'] },
    timezone_store: timezone_store,
    delimiter: ','
  )
  iterations.times { array_value.params_ical }
end

puts "Running #{ITERATIONS} iterations"
Benchmark.bm(25) do |bm|
  bm.report('Value.value_type') { benchmark_value_type(ITERATIONS) }
  bm.report('Array#params_ical') { benchmark_array_params(ITERATIONS) }
end
