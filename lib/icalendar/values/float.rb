# frozen_string_literal: true

module Icalendar
  module Values

    class Float < Value

      def initialize(value, params = ::Icalendar::Value::EMPTY_HASH, context = ::Icalendar::Value::EMPTY_HASH)
        super value.to_f, params, context
      end

      def value_ical
        value.to_s
      end

    end

  end
end
