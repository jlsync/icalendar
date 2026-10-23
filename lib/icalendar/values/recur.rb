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

      def initialize(value, *args)
        if value.is_a? ::Icalendar::Values::Recur
          super value.value, *args
        else
          super Parts.new(**parse_fields(value)), *args
        end
      end

      def valid?
        return false if frequency.nil?
        return false if !self.until.nil? && !count.nil?
        true
      end

      def value_ical
        v = value
        builder = ["FREQ=#{v.frequency}"]
        builder << "UNTIL=#{v.until}" unless v.until.nil?
        builder << "COUNT=#{v.count}" unless v.count.nil?
        builder << "INTERVAL=#{v.interval}" unless v.interval.nil?
        builder << "BYSECOND=#{v.by_second.join ','}" unless v.by_second.nil?
        builder << "BYMINUTE=#{v.by_minute.join ','}" unless v.by_minute.nil?
        builder << "BYHOUR=#{v.by_hour.join ','}" unless v.by_hour.nil?
        builder << "BYDAY=#{v.by_day.join ','}" unless v.by_day.nil?
        builder << "BYMONTHDAY=#{v.by_month_day.join ','}" unless v.by_month_day.nil?
        builder << "BYYEARDAY=#{v.by_year_day.join ','}" unless v.by_year_day.nil?
        builder << "BYWEEKNO=#{v.by_week_number.join ','}" unless v.by_week_number.nil?
        builder << "BYMONTH=#{v.by_month.join ','}" unless v.by_month.nil?
        builder << "BYSETPOS=#{v.by_set_position.join ','}" unless v.by_set_position.nil?
        builder << "WKST=#{v.week_start}" unless v.week_start.nil?
        builder.join ';'
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

      def parse_fields(value)
        {
          frequency: (value =~ PARSE_FIELDS_FREQUENCY_REGEX ? $1.upcase : nil),
          until: (value =~ PARSE_FIELDS_UNTIL_REGEX ? $1 : nil),
          count: (value =~ PARSE_FIELDS_COUNT_REGEX ? $1.to_i : nil),
          interval: (value =~ PARSE_FIELDS_INTERVAL_REGEX ? $1.to_i : nil),
          by_second: (value =~ PARSE_FIELDS_BY_SECOND_REGEX ? $1.split(',').map { |i| i.to_i } : nil),
          by_minute: (value =~ PARSE_FIELDS_BY_MINUTE_REGEX ? $1.split(',').map { |i| i.to_i } : nil),
          by_hour: (value =~ PARSE_FIELDS_BY_HOUR_REGEX ? $1.split(',').map { |i| i.to_i } : nil),
          by_day: (value =~ PARSE_FIELDS_BY_DAY_REGEX ? $1.split(',') : nil),
          by_month_day: (value =~ PARSE_FIELDS_BY_MONTH_DAY_REGEX ? $1.split(',') : nil),
          by_year_day: (value =~ PARSE_FIELDS_BY_YEAR_DAY_REGEX ? $1.split(',') : nil),
          by_week_number: (value =~ PARSE_FIELDS_BY_WEEK_NUMBER_REGEX ? $1.split(',') : nil),
          by_month: (value =~ PARSE_FIELDS_BY_MONTH_REGEX ? $1.split(',').map { |i| i.to_i } : nil),
          by_set_position: (value =~ PARSE_FIELDS_BY_SET_POSITON_REGEX ? $1.split(',') : nil),
          week_start: (value =~ PARSE_FIELDS_BY_WEEK_START_REGEX ? $1.upcase : nil)
        }
      end
    end
  end
end
