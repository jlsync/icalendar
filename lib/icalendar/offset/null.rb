# frozen_string_literal: true

module Icalendar
  class Offset
    class Null < Offset
      def valid?
        true
      end

      def normalized_value
        # plan d - just ignore the tzid
        if ::Logger::INFO >= Icalendar.logger.level
          Icalendar.logger.info("Ignoring timezone #{tzid} for time #{value}")
        end
        nil
      end
    end
  end
end
