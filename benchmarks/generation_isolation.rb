# frozen_string_literal: true

# Isolated generation ablations: one workload/mode/library per fresh process.
# MANIFEST=/tmp/variants.json JSON_OUTPUT=/tmp/results.json SAMPLES=10 \
#   EXPECTED_RUBY=4.0.9 REQUIRE_YJIT=1 RUBYOPT=--yjit \
#   bundle exec ruby benchmarks/generation_isolation.rb
#
# Manifest: {"baseline":{"lib":"/base/lib","source":"revision"},
#   "variants":{"text":{"lib":"/text/lib","cases":["escaped/render"]}}}
# Optional manifest "iterations" maps workload/mode to fixed counts (20..500).
# CALIBRATION_INPUT=/tmp/prior-results.json reuses prior calibrated counts.
# EVENTS (100), SAMPLES (10), WARMUP (40), TARGET_SECONDS (0.2), SEED (12345)
# configure the run. All CPU measurements run sequentially; use RUBYOPT to set
# worker flags. Each pair alternates AB/BA across rounds; this is not ABBA.
require_relative 'generation_comparison'
require 'time'

module GenerationIsolation
  BATCH_SIZE = 16
  MIN_ITERATIONS = 20
  MAX_ITERATIONS = 500
  COUNTERS = %i[total_allocated_objects count minor_gc_count major_gc_count].freeze

  def self.source(library)
    library = File.realpath(library)
    raise ArgumentError, "Missing #{library}/icalendar.rb" unless File.file?(File.join(library, 'icalendar.rb'))
    digest = Digest::SHA256.new
    files = Dir[File.join(library, '**', '*.rb')].sort
    files.each { |file| digest << file.delete_prefix(library + '/') << "\0" << File.binread(file) << "\0" }
    { 'lib' => library, 'sha256' => digest.hexdigest, 'ruby_files' => files.size }
  end

  def self.load_library(library)
    library = File.realpath(library)
    $LOAD_PATH.unshift(library)
    require 'icalendar'
    loaded = $LOADED_FEATURES.select { |path| path.match?(%r{/lib/icalendar(?:/|\.rb\z)}) }
    loaded << Icalendar::Component.instance_method(:to_ical).source_location.first
    identical_versions = []
    wrong = loaded.uniq.reject do |path|
      canonical = File.realpath(path)
      next true if canonical.start_with?(library + File::SEPARATOR)
      # bundle/setup evaluates the checkout's gemspec, which requires version.rb
      # before our worker selects a library. Permit only this metadata file,
      # and only after comparing its complete bytes with the selected version.
      if canonical.end_with?('/lib/icalendar/version.rb') &&
          File.binread(canonical) == File.binread(File.join(library, 'icalendar', 'version.rb'))
        identical_versions << canonical
        true
      else
        false
      end
    end
    raise "Loaded files outside selected library: #{wrong.join(', ')}" unless wrong.empty?
    identical_versions
  end

  def self.runtime
    yjit = defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enabled?) ? RubyVM::YJIT.enabled? : false
    if ENV['EXPECTED_RUBY'] && RUBY_VERSION != ENV.fetch('EXPECTED_RUBY')
      raise "Expected Ruby #{ENV.fetch('EXPECTED_RUBY')}, running #{RUBY_VERSION}"
    end
    raise 'YJIT is required; set RUBYOPT=--yjit for workers' if ENV['REQUIRE_YJIT'] == '1' && !yjit
    {
      'ruby' => RUBY_DESCRIPTION, 'version' => RUBY_VERSION, 'engine' => RUBY_ENGINE,
      'platform' => RUBY_PLATFORM, 'executable' => File.realpath(RbConfig.ruby),
      'yjit' => yjit, 'rubyopt' => ENV['RUBYOPT'],
      'gems' => Gem.loaded_specs.transform_values(&:version).transform_values(&:to_s)
    }
  end

  def self.run_case(config, iterations)
    workload, mode = config.fetch('case').split('/')
    build = -> { GenerationComparison.build_calendar(workload, config.fetch('events')) }
    expected = build.call.to_ical.freeze
    calendar = build.call if mode == 'render'
    config.fetch('warmup').times do
      output = (mode == 'render' ? calendar : build.call).to_ical
      raise 'Output changed during warmup' unless output == expected
    end
    totals = { 'wall_seconds' => 0.0, 'cpu_seconds' => 0.0 }
    COUNTERS.each { |key| totals[key.to_s] = 0 }
    remaining = iterations
    GC.start
    while remaining.positive?
      count = [remaining, BATCH_SIZE].min
      calendars = Array.new(count) { build.call } if mode == 'fresh'
      outputs = Array.new(count)
      operation = case mode
      when 'render' then ->(_i) { calendar.to_ical }
      when 'fresh' then ->(i) { calendars[i].to_ical }
      when 'build' then ->(_i) { build.call.to_ical }
      else raise ArgumentError, "Unknown mode: #{mode}"
      end
      gc_before = GC.stat(:count)
      minor_before = GC.stat(:minor_gc_count)
      major_before = GC.stat(:major_gc_count)
      objects_before = GC.stat(:total_allocated_objects)
      wall = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
      count.times { |i| outputs[i] = operation.call(i) }
      cpu_elapsed = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu
      wall_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall
      objects_after = GC.stat(:total_allocated_objects)
      gc_after = GC.stat(:count)
      minor_after = GC.stat(:minor_gc_count)
      major_after = GC.stat(:major_gc_count)
      totals['wall_seconds'] += wall_elapsed
      totals['cpu_seconds'] += cpu_elapsed
      totals['total_allocated_objects'] += objects_after - objects_before
      totals['count'] += gc_after - gc_before
      totals['minor_gc_count'] += minor_after - minor_before
      totals['major_gc_count'] += major_after - major_before
      # Retain the bounded batch until validation; comparisons and hashing are
      # outside the measured intervals. Check every output, including the first.
      outputs.each_with_index do |output, i|
        unless output == expected && output.encoding == expected.encoding
          raise "Output mismatch at iteration #{iterations - remaining + i + 1}"
        end
      end
      remaining -= count
      calendars = outputs = operation = nil
    end
    totals.merge(
      'iterations' => iterations, 'verified_outputs' => iterations,
      'wall_seconds_per_calendar' => totals['wall_seconds'] / iterations,
      'cpu_seconds_per_calendar' => totals['cpu_seconds'] / iterations,
      'objects_per_calendar' => totals['total_allocated_objects'].fdiv(iterations),
      'output' => { 'sha256' => Digest::SHA256.hexdigest(expected), 'bytes' => expected.bytesize,
                    'encoding' => expected.encoding.name }
    )
  end

  def self.worker(library, config, iterations)
    load_library(library)
    metadata = runtime
    result = run_case(config, iterations)
    # Check again after running the fixture, in case it lazily required a file.
    identical_versions = load_library(library)
    origin = source(library).merge('identical_preloaded_version_files' => identical_versions)
    puts JSON.generate('runtime' => metadata, 'source' => origin, 'measurement' => result)
  end

  def self.capture(library, config, iterations)
    output, error, status = Open3.capture3(
      RbConfig.ruby, __FILE__, '--worker', library, JSON.generate(config), iterations.to_s
    )
    raise "Worker failed for #{config.fetch('case')} (#{library}):\n#{error}\n#{output}" unless status.success?
    JSON.parse(output)
  end

  def self.checkpoint(path, report)
    File.write(path + '.tmp', JSON.pretty_generate(report) + "\n")
    File.rename(path + '.tmp', path)
  end

  def self.check_worker(report, result, label, key)
    report['runtime'] ||= result.fetch('runtime')
    raise 'Worker runtimes differ' unless report.fetch('runtime') == result.fetch('runtime')
    unless report.fetch('sources').fetch(label).fetch('sha256') == result.fetch('source').fetch('sha256')
      raise "Source changed while measuring #{label}"
    end
    signature = result.fetch('measurement').fetch('output')
    report['outputs'][key] ||= signature
    raise "Output differs across workers for #{key}" unless report['outputs'].fetch(key) == signature
  end

  def self.iterations(value)
    count = Integer(value)
    raise ArgumentError, 'Iterations must be between 20 and 500' unless (MIN_ITERATIONS..MAX_ITERATIONS).cover?(count)
    count
  end

  def self.run
    manifest_path = File.realpath(ENV.fetch('MANIFEST'))
    output_path = File.expand_path(ENV.fetch('JSON_OUTPUT'))
    input_paths = [manifest_path, ENV['CALIBRATION_INPUT']].compact.map { |path| File.realpath(path) }
    if input_paths.include?(output_path) || (File.exist?(output_path) && input_paths.include?(File.realpath(output_path)))
      raise ArgumentError, 'JSON_OUTPUT must not overwrite the manifest or calibration input'
    end
    manifest = JSON.parse(File.read(manifest_path))
    variants = manifest.fetch('variants')
    raise ArgumentError, 'At least one named variant is required' if variants.empty? || variants.key?('baseline')
    definitions = { 'baseline' => manifest.fetch('baseline') }.merge(variants)
    sources = definitions.transform_values { |item| source(item.fetch('lib')).merge('description' => item['source']) }
    pairs = variants.flat_map do |name, item|
      cases = item.fetch('cases')
      raise ArgumentError, "Empty or duplicate cases for #{name}" if cases.empty? || cases.uniq != cases
      cases.map do |key|
        workload, mode, extra = key.split('/')
        unless GenerationComparison::WORKLOADS.include?(workload) && GenerationComparison::MODES.include?(mode) && extra.nil?
          raise ArgumentError, "Unknown case #{key}"
        end
        [name, key]
      end
    end.sort
    config = {
      'events' => GenerationComparison.positive_integer('EVENTS', 100),
      'samples' => GenerationComparison.positive_integer('SAMPLES', 10),
      'warmup' => GenerationComparison.positive_integer('WARMUP', 40),
      'target_seconds' => Float(ENV.fetch('TARGET_SECONDS', '0.2')),
      'batch_size' => BATCH_SIZE, 'seed' => Integer(ENV.fetch('SEED', '12345')),
      'min_iterations' => MIN_ITERATIONS, 'max_iterations' => MAX_ITERATIONS
    }
    raise ArgumentError, 'TARGET_SECONDS must be finite and positive' unless config['target_seconds'].finite? && config['target_seconds'].positive?
    report = {
      'status' => 'running', 'started_at' => Time.now.utc.iso8601, 'manifest' => manifest,
      'manifest_path' => manifest_path, 'config' => config, 'sources' => sources,
      'calibration' => {}, 'outputs' => {}, 'pairs' => [],
      'harness_sha256' => Digest::SHA256.file(__FILE__).hexdigest,
      'fixtures_sha256' => Digest::SHA256.file(File.join(__dir__, 'generation_comparison.rb')).hexdigest
    }
    checkpoint(output_path, report)
    previous = JSON.parse(File.read(ENV.fetch('CALIBRATION_INPUT'))) if ENV['CALIBRATION_INPUT']
    if previous
      %w[events warmup batch_size].each do |key|
        raise "Calibration #{key} differs" unless previous.fetch('config').fetch(key) == config.fetch(key)
      end
      raise 'Calibration baseline source differs' unless previous.fetch('sources').fetch('baseline')['sha256'] == sources.fetch('baseline')['sha256']
      report['runtime'] = previous.fetch('runtime')
      report['calibration_input'] = File.realpath(ENV.fetch('CALIBRATION_INPUT'))
    end
    pairs.map(&:last).uniq.sort.each do |key|
      explicit = manifest.fetch('iterations', {})[key]
      prior = previous && previous.fetch('calibration').fetch(key)
      raise "Explicit iterations disagree with prior calibration for #{key}" if explicit && prior && iterations(explicit) != prior.fetch('iterations')
      if explicit || prior
        count = iterations(explicit || prior.fetch('iterations'))
        report['calibration'][key] = { 'iterations' => count, 'origin' => explicit ? 'manifest' : 'prior_run' }
      else
        result = capture(sources.fetch('baseline').fetch('lib'), config.merge('case' => key), MIN_ITERATIONS)
        check_worker(report, result, 'baseline', key)
        seconds = result.fetch('measurement').fetch('wall_seconds_per_calendar')
        count = [[(config['target_seconds'] / seconds).ceil, MIN_ITERATIONS].max, MAX_ITERATIONS].min
        report['calibration'][key] = { 'iterations' => count, 'origin' => 'baseline', 'probe' => result }
      end
      checkpoint(output_path, report)
      warn "Calibrated #{key}: #{report['calibration'][key]['iterations']} iterations"
    end
    config.fetch('samples').times do |round|
      pairs.shuffle(random: Random.new(config.fetch('seed') + round)).each do |name, key|
        order = round.even? ? ['baseline', name] : [name, 'baseline']
        count = report.fetch('calibration').fetch(key).fetch('iterations')
        pair = { 'round' => round + 1, 'variant' => name, 'case' => key, 'order' => order, 'iterations' => count }
        order.each do |label|
          result = capture(sources.fetch(label).fetch('lib'), config.merge('case' => key), count)
          check_worker(report, result, label, key)
          pair[label == 'baseline' ? 'baseline' : 'candidate'] = result
        end
        report.fetch('pairs') << pair
        checkpoint(output_path, report)
        before, after = %w[baseline candidate].map { |label| pair.fetch(label).fetch('measurement') }
        warn format('Round %d/%d %-12s %-20s wall %.3fx CPU %.3fx objects %.1f -> %.1f',
                    round + 1, config['samples'], name, key,
                    before['wall_seconds'] / after['wall_seconds'], before['cpu_seconds'] / after['cpu_seconds'],
                    before['objects_per_calendar'], after['objects_per_calendar'])
      end
    end
    report['status'] = 'completed'
    report['completed_at'] = Time.now.utc.iso8601
    checkpoint(output_path, report)
    puts "Saved #{report['pairs'].length} verified sample pairs to #{output_path}"
  rescue StandardError => error
    if report && output_path
      report['status'] = 'failed'
      report['error'] = "#{error.class}: #{error.message}"
      checkpoint(output_path, report)
    end
    raise
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.first == '--worker'
    GenerationIsolation.worker(ARGV.fetch(1), JSON.parse(ARGV.fetch(2)), Integer(ARGV.fetch(3)))
  else
    GenerationIsolation.run
  end
end
