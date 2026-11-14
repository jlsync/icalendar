# frozen_string_literal: true

module Icalendar
  module Values

    class Duration < Value
      Parts = ::Struct.new(:past, :weeks, :days, :hours, :minutes, :seconds, keyword_init: true)

      def initialize(value, params = ::Icalendar::Value::EMPTY_HASH, context = ::Icalendar::Value::EMPTY_HASH)
        if value.is_a? ::Icalendar::Values::Duration
          super value.value, params, context
        else
          super parse_parts(value), params, context
        end
      end

      def past?
        value.past
      end

      def value_ical
        v = value
        if v.weeks > 0
          buf = ::String.new
          buf << '-' if past?
          buf << 'P' << v.weeks.to_s << 'W'
          return buf
        end
        buf = ::String.new
        buf << '-' if past?
        buf << 'P'
        buf << v.days.to_s << 'D' if v.days > 0
        if v.hours > 0 || v.minutes > 0 || v.seconds > 0
          buf << 'T'
          buf << v.hours.to_s << 'H' if v.hours > 0
          buf << v.minutes.to_s << 'M' if v.minutes > 0
          buf << v.seconds.to_s << 'S' if v.seconds > 0
        end
        buf
      end

      private

      DURATION_PAST_REGEX = /\A([+-])P/.freeze
      DURATION_WEEKS_REGEX = /(\d+)W/.freeze
      DURATION_DAYS_REGEX = /(\d+)D/.freeze
      DURATION_HOURS_REGEX = /(\d+)H/.freeze
      DURATION_MINUTES_REGEX = /(\d+)M/.freeze
      DURATION_SECONDS_REGEX = /(\d+)S/.freeze

      def parse_parts(value)
        Parts.new(
          past: (value =~ DURATION_PAST_REGEX ? $1 == '-' : false),
          weeks: (value =~ DURATION_WEEKS_REGEX ? $1.to_i : 0),
          days: (value =~ DURATION_DAYS_REGEX ? $1.to_i : 0),
          hours: (value =~ DURATION_HOURS_REGEX ? $1.to_i : 0),
          minutes: (value =~ DURATION_MINUTES_REGEX ? $1.to_i : 0),
          seconds: (value =~ DURATION_SECONDS_REGEX ? $1.to_i : 0)
        )
      end

      def parse_fields(value)
        parse_parts(value).to_h
      end
    end

  end
end
