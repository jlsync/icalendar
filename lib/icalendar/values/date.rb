# frozen_string_literal: true

require 'date'

module Icalendar
  module Values

    class Date < Value
      FORMAT = '%Y%m%d'

      def initialize(value, params = {}, context = ::Icalendar::Value::EMPTY_HASH)
        params = params.dup if params.frozen?
        params.delete 'tzid'
        params.delete :tzid
        if value.is_a? ::String
          begin
            parsed_date = parse_date(value)
          rescue ::ArgumentError => e
            raise FormatError.new("Failed to parse \"#{value}\" - #{e.message}")
          end

          super parsed_date, params, context
        elsif value.respond_to? :to_date
          super value.to_date, params, context
        else
          super
        end
      end

      def value_ical
        value.strftime FORMAT
      end

      def <=>(other)
        if other.is_a?(::Icalendar::Values::Date) || other.is_a?(::Icalendar::Values::DateTime)
          value_ical <=> other.value_ical
        else
          nil
        end
      end

      class FormatError < ::ArgumentError
      end

      private

      def parse_date(value)
        if value.bytesize == 8 && value.encoding.ascii_compatible?
          b0 = value.getbyte(0) - 48
          b1 = value.getbyte(1) - 48
          b2 = value.getbyte(2) - 48
          b3 = value.getbyte(3) - 48
          b4 = value.getbyte(4) - 48
          b5 = value.getbyte(5) - 48
          b6 = value.getbyte(6) - 48
          b7 = value.getbyte(7) - 48
          if (b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7) >= 0 &&
             b0 <= 9 && b1 <= 9 && b2 <= 9 && b3 <= 9 && b4 <= 9 && b5 <= 9 && b6 <= 9 && b7 <= 9
            return ::Date.new(
              b0 * 1000 + b1 * 100 + b2 * 10 + b3,
              b4 * 10 + b5,
              b6 * 10 + b7
            )
          end
        end
        ::Date.strptime(value, FORMAT)
      end
    end

  end
end
