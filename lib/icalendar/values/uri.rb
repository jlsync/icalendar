# frozen_string_literal: true

require 'uri'

module Icalendar
  module Values

    class Uri < Value
      CONTROL_BYTES_REGEX = /[\x00-\x1F\x7F]/.freeze

      def initialize(value, params = ::Icalendar::Value::EMPTY_HASH, context = ::Icalendar::Value::EMPTY_HASH)
        parsed = ::URI.parse(value) rescue value
        super parsed, params, context
      end

      def value_ical
        value.to_s.gsub(CONTROL_BYTES_REGEX) { |char| "%%%02X" % char.ord }
      end
    end

  end
end
