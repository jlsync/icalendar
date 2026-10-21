# frozen_string_literal: true

module Icalendar
  module Values
    class Text < Value
      UNESCAPE_GSUB_REGEX = /\\[\\,;nN]/.freeze
      UNESCAPES = {
        '\\\\' => '\\',
        '\\,' => ',',
        '\\;' => ';',
        '\\n' => "\n",
        '\\N' => "\n"
      }.freeze

      def initialize(value, *args)
        # One left-to-right pass keeps unescape the exact inverse of value_ical; \n and \N are newline.
        value = if value.is_a?(String)
          value.include?('\\') ? value.gsub(UNESCAPE_GSUB_REGEX, UNESCAPES) : value.dup
        else
          value.gsub(UNESCAPE_GSUB_REGEX, UNESCAPES)
        end
        super value, *args
      end

      VALUE_ICAL_ESCAPE_REGEX = /\\|;|,|\r?\n/.freeze
      VALUE_ICAL_ESCAPES = {
        "\\" => "\\\\",
        ";" => "\\;",
        "," => "\\,",
        "\n" => "\\n",
        "\r\n" => "\\n"
      }.freeze

      def value_ical
        if value.is_a?(String)
          if value.match?(VALUE_ICAL_ESCAPE_REGEX)
            value.gsub(VALUE_ICAL_ESCAPE_REGEX, VALUE_ICAL_ESCAPES)
          else
            value.dup
          end
        else
          value.gsub(VALUE_ICAL_ESCAPE_REGEX, VALUE_ICAL_ESCAPES)
        end
      end
    end
  end
end
