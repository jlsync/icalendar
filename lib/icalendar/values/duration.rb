# frozen_string_literal: true

module Icalendar
  module Values

    class Duration < Value
      Parts = ::Struct.new(:past, :weeks, :days, :hours, :minutes, :seconds, keyword_init: true)

      def initialize(value, *args)
        if value.is_a? ::Icalendar::Values::Duration
          super value.value, *args
        else
          super Parts.new(**parse_fields(value)), *args
        end
      end

      def past?
        value.past
      end

      def value_ical
        v = value
        return "#{'-' if past?}P#{v.weeks}W" if v.weeks > 0
        builder = []
        builder << '-' if past?
        builder << 'P'
        builder << "#{v.days}D" if v.days > 0
        builder << 'T' if v.hours > 0 || v.minutes > 0 || v.seconds > 0
        builder << "#{v.hours}H" if v.hours > 0
        builder << "#{v.minutes}M" if v.minutes > 0
        builder << "#{v.seconds}S" if v.seconds > 0
        builder.join
      end

      private

      DURATION_PAST_REGEX = /\A([+-])P/.freeze
      DURATION_WEEKS_REGEX = /(\d+)W/.freeze
      DURATION_DAYS_REGEX = /(\d+)D/.freeze
      DURATION_HOURS_REGEX = /(\d+)H/.freeze
      DURATION_MINUTES_REGEX = /(\d+)M/.freeze
      DURATION_SECONDS_REGEX = /(\d+)S/.freeze

      def parse_fields(value)
        {
          past: (value =~ DURATION_PAST_REGEX ? $1 == '-' : false),
          weeks: (value =~ DURATION_WEEKS_REGEX ? $1.to_i : 0),
          days: (value =~ DURATION_DAYS_REGEX ? $1.to_i : 0),
          hours: (value =~ DURATION_HOURS_REGEX ? $1.to_i : 0),
          minutes: (value =~ DURATION_MINUTES_REGEX ? $1.to_i : 0),
          seconds: (value =~ DURATION_SECONDS_REGEX ? $1.to_i : 0)
        }
      end
    end

  end
end
