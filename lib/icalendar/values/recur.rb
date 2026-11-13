# frozen_string_literal: true

module Icalendar
  module Values

    class Recur < Value
      NUM_LIST = '\d{1,2}(?:,\d{1,2})*'
      DAYNAME = 'SU|MO|TU|WE|TH|FR|SA'
      WEEKDAY = "(?:[+-]?\\d{1,2})?(?:#{DAYNAME})"
      MONTHDAY = '[+-]?\d{1,2}'
      YEARDAY = '[+-]?\d{1,3}'
      Parts = ::Struct.new(
        :frequency,
        :until,
        :count,
        :interval,
        :by_second,
        :by_minute,
        :by_hour,
        :by_day,
        :by_month_day,
        :by_year_day,
        :by_week_number,
        :by_month,
        :by_set_position,
        :week_start,
        keyword_init: true
      )

      def initialize(value, params = ::Icalendar::Value::EMPTY_HASH, context = ::Icalendar::Value::EMPTY_HASH)
        if value.is_a? ::Icalendar::Values::Recur
          super value.value, params, context
        else
          super parse_parts(value), params, context
        end
      end

      def valid?
        return false if frequency.nil?
        return false if !self.until.nil? && !count.nil?
        true
      end

      def value_ical
        v = value
        buf = ::String.new('FREQ=')
        buf << v.frequency.to_s
        buf << ';UNTIL=' << v.until.to_s unless v.until.nil?
        buf << ';COUNT=' << v.count.to_s unless v.count.nil?
        buf << ';INTERVAL=' << v.interval.to_s unless v.interval.nil?
        append_joined(buf, ';BYSECOND=', v.by_second) unless v.by_second.nil?
        append_joined(buf, ';BYMINUTE=', v.by_minute) unless v.by_minute.nil?
        append_joined(buf, ';BYHOUR=', v.by_hour) unless v.by_hour.nil?
        append_joined(buf, ';BYDAY=', v.by_day) unless v.by_day.nil?
        append_joined(buf, ';BYMONTHDAY=', v.by_month_day) unless v.by_month_day.nil?
        append_joined(buf, ';BYYEARDAY=', v.by_year_day) unless v.by_year_day.nil?
        append_joined(buf, ';BYWEEKNO=', v.by_week_number) unless v.by_week_number.nil?
        append_joined(buf, ';BYMONTH=', v.by_month) unless v.by_month.nil?
        append_joined(buf, ';BYSETPOS=', v.by_set_position) unless v.by_set_position.nil?
        buf << ';WKST=' << v.week_start.to_s unless v.week_start.nil?
        buf
      end

      private

      PARSE_FIELDS_FREQUENCY_REGEX = /FREQ=(SECONDLY|MINUTELY|HOURLY|DAILY|WEEKLY|MONTHLY|YEARLY)/i.freeze
      PARSE_FIELDS_UNTIL_REGEX = /UNTIL=([^;]*)/i.freeze
      PARSE_FIELDS_COUNT_REGEX = /COUNT=(\d+)/i.freeze
      PARSE_FIELDS_INTERVAL_REGEX = /INTERVAL=(\d+)/i.freeze
      PARSE_FIELDS_BY_SECOND_REGEX = /BYSECOND=(#{NUM_LIST})(?:;|\z)/i.freeze
      PARSE_FIELDS_BY_MINUTE_REGEX = /BYMINUTE=(#{NUM_LIST})(?:;|\z)/i.freeze
      PARSE_FIELDS_BY_HOUR_REGEX = /BYHOUR=(#{NUM_LIST})(?:;|\z)/i.freeze
      PARSE_FIELDS_BY_DAY_REGEX = /BYDAY=(#{WEEKDAY}(?:,#{WEEKDAY})*)(?:;|\z)/i.freeze
      PARSE_FIELDS_BY_MONTH_DAY_REGEX = /BYMONTHDAY=(#{MONTHDAY}(?:,#{MONTHDAY})*)(?:;|\z)/i.freeze
      PARSE_FIELDS_BY_YEAR_DAY_REGEX = /BYYEARDAY=(#{YEARDAY}(?:,#{YEARDAY})*)(?:;|\z)/i.freeze
      PARSE_FIELDS_BY_WEEK_NUMBER_REGEX = /BYWEEKNO=(#{MONTHDAY}(?:,#{MONTHDAY})*)(?:;|\z)/i.freeze
      PARSE_FIELDS_BY_MONTH_REGEX = /BYMONTH=(#{NUM_LIST})(?:;|\z)/i.freeze
      PARSE_FIELDS_BY_SET_POSITON_REGEX = /BYSETPOS=(#{YEARDAY}(?:,#{YEARDAY})*)(?:;|\z)/i.freeze
      PARSE_FIELDS_BY_WEEK_START_REGEX = /WKST=(#{DAYNAME})/i.freeze

      def append_joined(buf, prefix, list)
        buf << prefix
        list.each_with_index do |item, idx|
          buf << ',' if idx > 0
          buf << item.to_s
        end
      end

      def parse_parts(value)
        parts = Parts.new
        parts.frequency = $1.upcase if value =~ PARSE_FIELDS_FREQUENCY_REGEX
        parts.until = $1 if value =~ PARSE_FIELDS_UNTIL_REGEX
        parts.count = $1.to_i if value =~ PARSE_FIELDS_COUNT_REGEX
        parts.interval = $1.to_i if value =~ PARSE_FIELDS_INTERVAL_REGEX
        unless value.is_a?(::String) && !value.include?('B') && !value.include?('b')
          parts.by_second = $1.split(',').map(&:to_i) if value =~ PARSE_FIELDS_BY_SECOND_REGEX
          parts.by_minute = $1.split(',').map(&:to_i) if value =~ PARSE_FIELDS_BY_MINUTE_REGEX
          parts.by_hour = $1.split(',').map(&:to_i) if value =~ PARSE_FIELDS_BY_HOUR_REGEX
          parts.by_day = $1.split(',') if value =~ PARSE_FIELDS_BY_DAY_REGEX
          parts.by_month_day = $1.split(',') if value =~ PARSE_FIELDS_BY_MONTH_DAY_REGEX
          parts.by_year_day = $1.split(',') if value =~ PARSE_FIELDS_BY_YEAR_DAY_REGEX
          parts.by_week_number = $1.split(',') if value =~ PARSE_FIELDS_BY_WEEK_NUMBER_REGEX
          parts.by_month = $1.split(',').map(&:to_i) if value =~ PARSE_FIELDS_BY_MONTH_REGEX
          parts.by_set_position = $1.split(',') if value =~ PARSE_FIELDS_BY_SET_POSITON_REGEX
        end
        parts.week_start = $1.upcase if value =~ PARSE_FIELDS_BY_WEEK_START_REGEX
        parts
      end

      def parse_fields(value)
        parse_parts(value).to_h
      end
    end
  end
end
