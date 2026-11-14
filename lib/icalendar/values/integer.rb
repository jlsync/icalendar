# frozen_string_literal: true

module Icalendar
  module Values

    class Integer < Value

      def initialize(value, params = ::Icalendar::Value::EMPTY_HASH, context = ::Icalendar::Value::EMPTY_HASH)
        super value.to_i, params, context
      end

      def value_ical
        value.to_s
      end

    end

  end
end
