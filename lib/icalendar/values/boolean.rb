# frozen_string_literal: true

module Icalendar
  module Values

    class Boolean < Value

      def initialize(value, params = ::Icalendar::Value::EMPTY_HASH, context = ::Icalendar::Value::EMPTY_HASH)
        super value.to_s.casecmp?('true'), params, context
      end

      def value_ical
        value ? 'TRUE' : 'FALSE'
      end

    end

  end
end
