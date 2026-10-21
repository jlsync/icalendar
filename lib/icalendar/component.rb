# frozen_string_literal: true

require 'securerandom'

module Icalendar

  class Component
    include HasProperties
    include HasComponents

    attr_reader :name
    attr_reader :ical_name
    attr_accessor :parent

    def self.parse(source)
      _parse source
    rescue ArgumentError
      source.rewind if source.respond_to?(:rewind)
      _parse Parser.clean_bad_wrapping(source)
    end

    def initialize(name, ical_name = nil)
      @name = name
      @ical_name = ical_name || "V#{name.upcase}"
      super()
    end

    def new_uid
      SecureRandom.uuid
    end

    COLON = ':'
    CRLF = "\r\n"

    def to_ical(buffer = nil)
      buffer ||= String.new
      buffer << "BEGIN:#{ical_name}\r\n"
      append_ical_properties(buffer)
      append_ical_components(buffer)
      buffer << "END:#{ical_name}\r\n"
      buffer
    end

    private

    def append_ical_property(buffer, wire_name, value, default_type)
      if value.is_a?(Icalendar::Value) && value.class.instance_method(:to_ical).owner == Icalendar::Value
        value.ical_param('value', value.send(:value_type)) if value.send(:needs_value_type?, default_type)
        params = value.params_ical
        val = value.value_ical
        if params
          if wire_name.bytesize + params.bytesize + 1 + val.bytesize <= Icalendar::MAX_LINE_LENGTH
            buffer << wire_name << params << COLON << val << CRLF
            return
          end
          buffer << ical_fold(wire_name + params + COLON + val) << CRLF
        else
          if wire_name.bytesize + 1 + val.bytesize <= Icalendar::MAX_LINE_LENGTH
            buffer << wire_name << COLON << val << CRLF
            return
          end
          buffer << ical_fold(wire_name + COLON + val) << CRLF
        end
      else
        append_ical_line(buffer, wire_name, value.to_ical(default_type))
      end
    end

    def append_ical_properties(buffer)
      self.class.renderable_properties.each do |metadata|
        value = __send__(metadata.reader)
        next if value.nil?
        if metadata.multi
          next if value.empty?
          value.each do |part|
            append_ical_property(buffer, metadata.wire_name, part, metadata.default_type)
          end
        else
          append_ical_property(buffer, metadata.wire_name, value, metadata.default_type)
        end
      end

      return if custom_properties.empty?
      custom_properties.each do |prop, values|
        next if values.nil? || values.empty?

        wire_name = ical_prop_name(prop)
        default_type = self.class.default_property_types[prop]
        values.each do |custom_value|
          append_ical_property(buffer, wire_name, custom_value, default_type)
        end
      end
    end

    def append_ical_line(buffer, wire_name, value_ical)
      if wire_name.bytesize + value_ical.bytesize <= Icalendar::MAX_LINE_LENGTH
        buffer << wire_name << value_ical << CRLF
      else
        buffer << ical_fold(wire_name + value_ical) << CRLF
      end
    end

    def ical_prop_name(prop_name)
      prop_name.delete_prefix('ip_').tr('_', '-').upcase
    end

    ICAL_FOLD_LONG_LINE_SCAN_REGEX = /\P{M}\p{M}*/u.freeze

    def ical_fold(long_line, indent = "\x20")
      # rfc2445 says:
      # Lines of text SHOULD NOT be longer than 75 octets, excluding the line
      # break. Long content lines SHOULD be split into a multiple line
      # representations using a line "folding" technique. That is, a long
      # line can be split between any two characters by inserting a CRLF
      # immediately followed by a single linear white space character (i.e.,
      # SPACE, US-ASCII decimal 32 or HTAB, US-ASCII decimal 9). Any sequence
      # of CRLF followed immediately by a single linear white space character
      # is ignored (i.e., removed) when processing the content type.
      #
      # Note the useage of "octets" and "characters": a line should not be longer
      # than 75 octets, but you need to split between characters, not bytes.
      # This is challanging with Unicode composing accents, for example.

      return long_line if long_line.bytesize <= Icalendar::MAX_LINE_LENGTH

      if long_line.ascii_only?
        return fold_ascii(long_line, indent)
      end

      folded = String.new(capacity: long_line.bytesize + 64)
      bytes = 0
      indent_bytesize = indent.bytesize
      long_line.scan(ICAL_FOLD_LONG_LINE_SCAN_REGEX) do |c|
        c_bytes = c.bytesize
        if bytes + c_bytes > Icalendar::MAX_LINE_LENGTH
          folded << CRLF << indent
          bytes = indent_bytesize
        end
        folded << c
        bytes += c_bytes
      end
      folded
    end

    def fold_ascii(long_line, indent)
      max_line_length = Icalendar::MAX_LINE_LENGTH
      continuation_length = max_line_length - indent.bytesize
      continuation_length = 1 if continuation_length < 1
      size = long_line.bytesize
      folded = String.new(capacity: size + ((size / continuation_length) + 1) * (2 + indent.bytesize))

      folded << long_line.byteslice(0, max_line_length)
      offset = max_line_length
      while offset < size
        folded << CRLF << indent
        folded << long_line.byteslice(offset, continuation_length)
        offset += continuation_length
      end
      folded
    end

    def append_ical_components(buffer)
      self.class.components.each do |component_name|
        send(component_name).each do |component|
          append_ical_component(buffer, component)
        end
      end

      return if custom_components.empty?
      custom_components.each_value do |components|
        components.each do |component|
          append_ical_component(buffer, component)
        end
      end
    end

    def append_ical_component(buffer, component)
      serializer = component.method(:to_ical)
      if serializer.owner == Icalendar::Component || serializer.parameters.any? { |type, _| type == :req || type == :opt || type == :rest }
        component.to_ical(buffer)
      else
        buffer << component.to_ical
      end
    end

    class << self
      private def _parse(source)
        parser = Parser.new(source)
        parser.component_class = self
        parser.parse
      end
    end
  end

end
