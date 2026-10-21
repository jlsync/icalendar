# frozen_string_literal: true

module Icalendar
  class Offset
    def self.build(value, params, timezone_store)
      return nil if params.nil? || params['tzid'].nil?

      tzid = Array(params['tzid']).first

      TYPES.each do |klass|
        offset = klass.new(tzid, value, timezone_store)
        return offset if offset.valid?
      end
      nil
    end

    def initialize(tzid, value, timezone_store)
      @tzid = tzid
      @value = value
      @timezone_store = timezone_store
    end

    def normalized_tzid
      Array(tzid)
    end

    private

    attr_reader :tzid, :value, :timezone_store

    def support_classes_defined?
      defined?(ActiveSupport::TimeZone) &&
        defined?(Icalendar::Values::Helpers::ActiveSupportTimeWithZoneAdapter)
    end

    # Whether a message at +severity+ should be built and logged. Prefer the logger's own
    # predicate (::Logger#debug? / #info?), fall back to a numeric #level, and otherwise log,
    # so loggers that only implement the positional severity methods behave as before.
    def log_enabled?(severity, predicate)
      logger = Icalendar.logger
      return logger.public_send(predicate) if logger.respond_to?(predicate)

      level = logger.level if logger.respond_to?(:level)
      level.is_a?(Integer) ? severity >= level : true
    end
  end
end

require_relative 'offset/active_support_exact'
require_relative 'offset/active_support_partial'
require_relative 'offset/null'
require_relative 'offset/time_zone_store'
require_relative 'offset/windows_to_iana'

module Icalendar
  class Offset
    TYPES = [
      ActiveSupportExact,
      TimeZoneStore,
      WindowsToIana,
      ActiveSupportPartial,
      Null
    ].freeze
  end
end
