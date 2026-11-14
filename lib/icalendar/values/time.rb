# frozen_string_literal: true

require 'date'
require_relative 'helpers/time_with_zone'

module Icalendar
  module Values

    class Time < Value
      include Helpers::TimeWithZone

      FORMAT = '%H%M%S'
      UTC_FORMAT = '%H%M%SZ'

      def initialize(value, params = {}, context = ::Icalendar::Value::EMPTY_HASH)
        if value.is_a? ::String
          if value.end_with? 'Z'
            params = params.dup if params.frozen?
            params['tzid'] = 'UTC'
          end
          super ::DateTime.strptime(value, FORMAT).to_time, params, context
        elsif value.respond_to? :to_time
          super value.to_time, params, context
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

    end

  end
end
