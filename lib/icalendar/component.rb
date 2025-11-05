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

    def to_ical
      buffer = String.new
      buffer << "BEGIN:#{ical_name}\r\n"
      append_ical_properties(buffer)
      append_ical_components(buffer)
      buffer << "END:#{ical_name}\r\n"
      buffer
    end

    private

    def append_ical_properties(buffer)
      self.class.renderable_properties.each do |metadata|
        value = __send__(metadata.reader)
        next if value.nil?
        if metadata.multi
          next if value.empty?
          value.each do |part|
            buffer << ical_fold("#{metadata.wire_name}#{part.to_ical(metadata.default_type)}")
            buffer << "\r\n"
          end
        else
          buffer << ical_fold("#{metadata.wire_name}#{value.to_ical(metadata.default_type)}")
          buffer << "\r\n"
        end
      end

      return if custom_properties.empty?
      custom_properties.each do |prop, values|
        next if values.nil? || values.empty?

        wire_name = ical_prop_name(prop)
        default_type = self.class.default_property_types[prop]
        values.each do |custom_value|
          buffer << ical_fold("#{wire_name}#{custom_value.to_ical(default_type)}")
          buffer << "\r\n"
        end
      end
    end

    ICAL_PROP_NAME_GSUB_REGEX = /\Aip_/.freeze

    def ical_prop_name(prop_name)
      prop_name.gsub(ICAL_PROP_NAME_GSUB_REGEX, '').gsub('_', '-').upcase
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

      chars = long_line.scan(ICAL_FOLD_LONG_LINE_SCAN_REGEX) # split in graphenes
      folded = [String.new]
      bytes = 0
      indent_bytesize = indent.bytesize
      chars.each do |c|
        bytes += c.bytesize
        if bytes > Icalendar::MAX_LINE_LENGTH
          # Split here
          folded << indent.dup
          bytes = indent_bytesize + c.bytesize
        end
        folded[-1] << c
      end

      folded.join("\r\n")
    end

    def fold_ascii(long_line, indent)
      folded = String.new
      line_bytes = 0
      indent_bytesize = indent.bytesize
      long_line.each_byte do |byte|
        if line_bytes >= Icalendar::MAX_LINE_LENGTH
          folded << "\r\n"
          folded << indent
          line_bytes = indent_bytesize
        end
        folded << byte.chr
        line_bytes += 1
      end
      folded
    end

    def append_ical_components(buffer)
      self.class.components.each do |component_name|
        send(component_name).each do |component|
          buffer << component.to_ical
        end
      end

      return if custom_components.empty?
      custom_components.each_value do |components|
        components.each do |component|
          buffer << component.to_ical
        end
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
