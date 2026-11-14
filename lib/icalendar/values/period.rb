# frozen_string_literal: true

module Icalendar
  module Values

    class Period < Value

      PERIOD_LAST_PART_REGEX = /\A[+-]?P.+\z/.freeze

      def initialize(value, params = ::Icalendar::Value::EMPTY_HASH, context = ::Icalendar::Value::EMPTY_HASH)
        parts = value.split '/'
        period_start = ::Icalendar::Values::DateTime.new parts.first
        if parts.last =~ PERIOD_LAST_PART_REGEX
          period_end = ::Icalendar::Values::Duration.new parts.last
        else
          period_end = ::Icalendar::Values::DateTime.new parts.last
        end
        super [period_start, period_end], params, context
      end

      def value_ical
        if value.size == 2
          "#{value[0].value_ical}/#{value[1].value_ical}"
        else
          value.map { |v| v.value_ical }.join '/'
        end
      end

      def period_start
        first
      end

      def period_start=(v)
        value[0] = v.is_a?(::Icalendar::Values::DateTime) ? v : ::Icalendar::Values::DateTime.new(v)
      end

      def explicit_end
        last.is_a?(::Icalendar::Values::DateTime) ? last : nil
      end

      def explicit_end=(v)
        value[1] = v.is_a?(::Icalendar::Values::DateTime) ? v : ::Icalendar::Values::DateTime.new(v)
      end

      def duration
        last.is_a?(::Icalendar::Values::Duration) ? last : nil
      end

      def duration=(v)
        value[1] = v.is_a?(::Icalendar::Values::Duration) ? v : ::Icalendar::Values::Duration.new(v)
      end
    end
  end
end
