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
        # A plain, validly encoded String with no backslash has nothing to unescape, so skip the
        # regex pass and copy it instead; the copy keeps the stored string isolated from the caller
        # just as gsub did. Anything else (String subclasses that may override gsub, other objects,
        # invalid byte sequences) takes the original path so behaviour and errors are unchanged.
        value = if value.instance_of?(::String) && value.valid_encoding? && !value.include?('\\')
          value.dup
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
        value.gsub(VALUE_ICAL_ESCAPE_REGEX, VALUE_ICAL_ESCAPES)
      end
    end
  end
end
