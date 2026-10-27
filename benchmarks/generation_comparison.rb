# frozen_string_literal: true

# Compare this checkout with another checkout's lib directory, using identical
# dependencies and fresh processes. No calendar parsing is included.
#
#   BASELINE_LIB=/tmp/icalendar-baseline/lib bundle exec ruby benchmarks/generation_comparison.rb
#
# EVENTS, ITERATIONS, SAMPLES and WARMUP control the run size. WORKLOADS and MODES
# accept comma-separated subsets. Set JSON_OUTPUT to save all individual samples.
# Ruby CLI flags are not inherited by workers; use RUBYOPT='--disable-yjit' (or
# RUBYOPT='--yjit') to control both the parent and every measured worker.
require 'digest'
require 'json'
require 'open3'
require 'rbconfig'

module GenerationComparison
  WORKLOADS = %w[simple rich escaped ascii unicode parameters recurrence timezone].freeze
  MODES = %w[render fresh build].freeze

  def self.positive_integer(name, default)
    number = Integer(ENV.fetch(name, default))
    raise ArgumentError, "#{name} must be positive" unless number.positive?
    number
  end

  def self.selection(name, choices)
    selected = ENV.fetch(name, choices.join(',')).split(',')
    unless selected.any? && (selected - choices).empty?
      raise ArgumentError, "#{name} must contain names from #{choices.join(',')}"
    end
    selected
  end

  def self.build_calendar(workload, events)
    calendar = Icalendar::Calendar.new
    start = Time.utc(2024, 1, 1, 12)
    events.times do |i|
      calendar.event do |event|
        event.uid = "event-#{i}@example.com"
        event.dtstamp = Icalendar::Values::DateTime.new(start, 'tzid' => 'UTC')
        event.dtstart = start + i * 3600
        event.dtend = start + (i + 1) * 3600
        event.summary = "Event #{i}"

        case workload
        when 'rich'
          event.description = "Description #{i}"
          event.location = "1000 Main St #{i}"
          event.categories = %w[Alpha Beta Gamma]
          event.url = "https://example.com/#{i}"
          event.attendee = [
            Icalendar::Values::CalAddress.new("mailto:person#{i}@example.com"),
            Icalendar::Values::CalAddress.new("mailto:person#{i + 1}@example.com")
          ]
          event.rrule = Icalendar::Values::Recur.new('FREQ=DAILY;COUNT=5')
        when 'escaped'
          event.description = "Meeting, notes; follow-up\nC:\\files\\agenda\n" * 20
        when 'ascii'
          event.description = 'Long description with ordinary ASCII text. ' * 40
        when 'unicode'
          event.description = "会議 café e\u0301 🙂 — " * 40
        when 'parameters'
          event.dtstart = Icalendar::Values::Date.new(Date.new(2024, 1, 1) + i)
          event.dtend = Icalendar::Values::Date.new(Date.new(2024, 1, 2) + i)
          event.summary = Icalendar::Values::Text.new("Event #{i}", 'language' => 'en')
          event.attendee = Icalendar::Values::CalAddress.new(
            "mailto:person#{i}@example.com",
            'cn' => %(Person #{i}, "Guest"), 'role' => 'REQ-PARTICIPANT',
            'member' => ['mailto:team@example.com', 'mailto:group@example.com']
          )
        when 'recurrence'
          event.dtend = nil
          event.duration = Icalendar::Values::Duration.new('PT1H30M')
          event.rrule = Icalendar::Values::Recur.new(
            'FREQ=MONTHLY;COUNT=24;INTERVAL=2;BYDAY=MO,WE,FR;BYHOUR=9,14;BYMINUTE=0,30;BYSECOND=0;BYSETPOS=1,-1;WKST=MO'
          )
          event.alarm do |alarm|
            alarm.description = "Reminder #{i}"
            alarm.trigger = Icalendar::Values::Duration.new('-PT15M')
            alarm.duration = Icalendar::Values::Duration.new('PT5M')
            alarm.repeat = 2
          end
        when 'timezone'
          # A VTIMEZONE-heavy export: one definition per ten events, each with
          # standard/daylight offsets and recurrence rules. No timezone lookup
          # or expansion is required to serialize these definitions.
          if (i % 10).zero?
            calendar.timezone do |zone|
              zone.tzid = "Benchmark/Zone-#{i / 10}"
              zone.standard do |standard|
                standard.dtstart = DateTime.new(2024, 10, 27, 3)
                standard.tzoffsetfrom = '+0200'
                standard.tzoffsetto = '+0100'
                standard.tzname = 'STANDARD'
                standard.rrule = Icalendar::Values::Recur.new('FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10')
              end
              zone.daylight do |daylight|
                daylight.dtstart = DateTime.new(2024, 3, 31, 2)
                daylight.tzoffsetfrom = '+0100'
                daylight.tzoffsetto = '+0200'
                daylight.tzname = 'DAYLIGHT'
                daylight.rrule = Icalendar::Values::Recur.new('FREQ=YEARLY;BYDAY=-1SU;BYMONTH=3')
              end
            end
          end
        end
      end
    end
    calendar
  end

  def self.measure(iterations)
    output = nil
    GC.start
    allocated_before = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    iterations.times { |i| output = yield(i) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocated = GC.stat(:total_allocated_objects) - allocated_before
    {
      'seconds_per_calendar' => elapsed / iterations,
      'objects_per_calendar' => allocated.fdiv(iterations),
      'bytes' => output.bytesize,
      'sha256' => Digest::SHA256.hexdigest(output)
    }
  end

  def self.worker(library, config)
    library = File.realpath(library)
    $LOAD_PATH.unshift(library)
    require 'icalendar'
    loaded_from = Icalendar::Component.instance_method(:to_ical).source_location.first
    unless File.realpath(loaded_from).start_with?(library + File::SEPARATOR)
      abort "Loaded the wrong library: #{loaded_from}"
    end

    results = {}
    config['workloads'].each do |workload|
      config['modes'].each do |mode|
        # Warm method/JIT code before measuring, even for the first-render case.
        warm = build_calendar(workload, config['events'])
        config['warmup'].times { warm.to_ical }

        result = case mode
        when 'render'
          measure(config['iterations']) { warm.to_ical }
        when 'fresh'
          calendars = Array.new(config['iterations']) { build_calendar(workload, config['events']) }
          measure(config['iterations']) { |i| calendars[i].to_ical }
        when 'build'
          measure(config['iterations']) { build_calendar(workload, config['events']).to_ical }
        end
        results["#{workload}/#{mode}"] = result
        calendars = nil
      end
    end
    yjit = if defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enabled?)
      RubyVM::YJIT.enabled?
    end
    puts JSON.generate('runtime' => { 'ruby' => RUBY_DESCRIPTION, 'yjit' => yjit }, 'results' => results)
  end

  def self.median(values)
    sorted = values.sort
    middle = sorted.length / 2
    sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
  end

  def self.compare(config)
    libraries = {
      'baseline' => File.expand_path(ENV.fetch('BASELINE_LIB')),
      'candidate' => File.expand_path('../lib', __dir__)
    }
    libraries.each_value do |library|
      raise ArgumentError, "No icalendar.rb in #{library}" unless File.file?(File.join(library, 'icalendar.rb'))
    end
    results = { 'baseline' => [], 'candidate' => [] }
    runtime = nil
    config['samples'].times do |sample|
      order = sample.even? ? libraries.keys : libraries.keys.reverse
      order.each do |label|
        output, error, status = Open3.capture3(
          RbConfig.ruby, __FILE__, '--worker', libraries.fetch(label), JSON.generate(config)
        )
        abort "#{label} worker failed:\n#{error}\n#{output}" unless status.success?
        worker = JSON.parse(output)
        runtime ||= worker.fetch('runtime')
        abort 'Worker Ruby/JIT configurations differ' unless worker.fetch('runtime') == runtime
        results.fetch(label) << worker.fetch('results')
      end
      warn "Completed sample pair #{sample + 1}/#{config['samples']}"
    end

    # Also compare across samples and modes so changing clocks, random IDs or
    # lazy initialization cannot silently invalidate the output comparison.
    config['workloads'].each do |workload|
      signatures = results.values.flatten.flat_map do |sample|
        config['modes'].map do |mode|
          sample.fetch("#{workload}/#{mode}").values_at('bytes', 'sha256')
        end
      end
      abort "Output mismatch for #{workload}" unless signatures.uniq.length == 1
    end

    puts runtime.fetch('ruby')
    yjit_status = runtime.fetch('yjit').nil? ? 'unavailable' : (runtime.fetch('yjit') ? 'enabled' : 'disabled')
    puts "Worker YJIT: #{yjit_status}"
    puts "#{config['events']} events; #{config['iterations']} calendars/sample; #{config['samples']} sample pairs"
    puts 'Medians; GC enabled. render = warmed objects; fresh = first render; build = construction + render.'
    puts format('%-20s %11s %11s %10s %14s %14s', 'Workload/mode', 'Before ms', 'After ms', 'Speedup', 'Before objects', 'After objects')
    results.fetch('baseline').first.each_key do |key|
      before, after = %w[baseline candidate].map do |label|
        %w[seconds_per_calendar objects_per_calendar].map do |metric|
          median(results.fetch(label).map { |sample| sample.fetch(key).fetch(metric) })
        end
      end
      puts format('%-20s %11.3f %11.3f %9.2fx %14.1f %14.1f', key,
                  before[0] * 1000, after[0] * 1000, before[0] / after[0], before[1], after[1])
    end
    puts 'Output bytes and SHA-256 agree for every workload, mode and sample.'
    if ENV['JSON_OUTPUT']
      File.write(ENV.fetch('JSON_OUTPUT'), JSON.pretty_generate(
        'ruby' => runtime.fetch('ruby'), 'runtime' => runtime,
        'libraries' => libraries, 'config' => config, 'samples' => results
      ) + "\n")
    end
  end
end

if $PROGRAM_NAME == __FILE__ && ARGV.first == '--worker'
  GenerationComparison.worker(ARGV.fetch(1), JSON.parse(ARGV.fetch(2)))
elsif $PROGRAM_NAME == __FILE__
  GenerationComparison.compare(
    'events' => GenerationComparison.positive_integer('EVENTS', 100),
    'iterations' => GenerationComparison.positive_integer('ITERATIONS', 20),
    'samples' => GenerationComparison.positive_integer('SAMPLES', 5),
    'warmup' => GenerationComparison.positive_integer('WARMUP', 10),
    'workloads' => GenerationComparison.selection('WORKLOADS', GenerationComparison::WORKLOADS),
    'modes' => GenerationComparison.selection('MODES', GenerationComparison::MODES)
  )
end
