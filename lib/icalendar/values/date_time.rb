# frozen_string_literal: true

require 'date'
require_relative 'helpers/time_with_zone'

module Icalendar
  module Values

    class DateTime < Value
      include Helpers::TimeWithZone

      FORMAT = '%Y%m%dT%H%M%S'
      UTC_FORMAT = '%Y%m%dT%H%M%SZ'

      def initialize(value, params = {}, context = ::Icalendar::Value::EMPTY_HASH)
        if value.is_a? ::String
          if value.end_with? 'Z'
            params = params.dup if params.frozen?
            params['tzid'] = 'UTC'
          end

          begin
            parsed_date = parse_date_time(value)
          rescue ::ArgumentError => e
            raise FormatError.new("Failed to parse \"#{value}\" - #{e.message}")
          end

          super parsed_date, params, context
        elsif value.respond_to? :to_datetime
          super value.to_datetime, params, context
        else
          super
        end
      end

      def value_ical
        if tz_utc
          value.strftime UTC_FORMAT
        else
          value.strftime FORMAT
        end
      end

      def <=>(other)
        if other.is_a?(::Icalendar::Values::Date) || other.is_a?(::Icalendar::Values::DateTime)
          value_ical <=> other.value_ical
        else
          nil
        end
      end

      def utc?
        value.respond_to?(:utc?) ? value.utc? : value.to_time.utc?
      end

      class FormatError < ::ArgumentError
      end

      private

      def parse_date_time(value)
        len = value.bytesize
        if (len == 15 || (len == 16 && value.getbyte(15) == 90)) &&
           value.getbyte(8) == 84 &&
           value.encoding.ascii_compatible?
          b0 = value.getbyte(0) - 48
          b1 = value.getbyte(1) - 48
          b2 = value.getbyte(2) - 48
          b3 = value.getbyte(3) - 48
          b4 = value.getbyte(4) - 48
          b5 = value.getbyte(5) - 48
          b6 = value.getbyte(6) - 48
          b7 = value.getbyte(7) - 48
          b9 = value.getbyte(9) - 48
          b10 = value.getbyte(10) - 48
          b11 = value.getbyte(11) - 48
          b12 = value.getbyte(12) - 48
          b13 = value.getbyte(13) - 48
          b14 = value.getbyte(14) - 48
          if (b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7 | b9 | b10 | b11 | b12 | b13 | b14) >= 0 &&
             b0 <= 9 && b1 <= 9 && b2 <= 9 && b3 <= 9 && b4 <= 9 && b5 <= 9 && b6 <= 9 && b7 <= 9 &&
             b9 <= 9 && b10 <= 9 && b11 <= 9 && b12 <= 9 && b13 <= 9 && b14 <= 9 &&
             (second = b13 * 10 + b14) < 60
            return ::DateTime.new(
              b0 * 1000 + b1 * 100 + b2 * 10 + b3,
              b4 * 10 + b5,
              b6 * 10 + b7,
              b9 * 10 + b10,
              b11 * 10 + b12,
              second
            )
          end
        end
        ::DateTime.strptime(value, FORMAT)
      end
    end

  end
end
