# frozen_string_literal: true

require 'icalendar/timezone_store'
require 'stringio'

module Icalendar

  class Parser
    attr_writer :component_class, :parse_depth_limit
    attr_reader :source, :strict, :timezone_store, :verbose
    attr_accessor :parse_depth

    CLEAN_BAD_WRAPPING_GSUB_REGEX = /\r?\n[ \t]/.freeze

    def self.clean_bad_wrapping(source)
      content = if source.respond_to? :read
        source.read
      elsif source.respond_to? :to_s
        source.to_s
      else
        msg = 'Icalendar::Parser.clean_bad_wrapping must be called with a String or IO object'
        Icalendar.fatal msg
        fail ArgumentError, msg
      end
      encoding = content.encoding
      content.force_encoding(Encoding::ASCII_8BIT)
      content.gsub(CLEAN_BAD_WRAPPING_GSUB_REGEX, "").force_encoding(encoding)
    end

    def initialize(source, strict = false, verbose = false)
      if source.respond_to? :gets
        @source = source
      elsif source.respond_to? :to_s
        @source = StringIO.new source.to_s, 'r'
      else
        msg = 'Icalendar::Parser.new must be called with a String or IO object'
        Icalendar.fatal msg
        fail ArgumentError, msg
      end
      read_in_data
      @strict = strict
      @verbose = verbose
      @parse_depth = 0
      @timezone_store = TimezoneStore.new
    end

    def parse
      components = []
      while (fields = next_fields)
        component = component_class.new
        if fields[:name] == 'begin' && fields[:value].casecmp?(component.ical_name)
          components << parse_component(component)
        end
      end
      components
    end

    def parse_property(component, fields = nil)
      fields = next_fields if fields.nil?
      prop_name = case fields[:name]
                  when 'class', 'method', 'name' then "ip_#{fields[:name]}"
                  else fields[:name]
                  end
      multi_property = component.class.multiple_property? prop_name
      prop_value = wrap_property_value component, fields, multi_property
      begin
        method_name = if multi_property
          "append_#{prop_name}"
        else
          "#{prop_name}="
        end
        component.send method_name, prop_value
      rescue NoMethodError => nme
        if strict?
          Icalendar.logger.error "No method \"#{method_name}\" for component #{component}"
          raise nme
        else
          Icalendar.logger.warn "No method \"#{method_name}\" for component #{component}. Appending to custom." if verbose?
          component.append_custom_property prop_name, prop_value
        end
      end
    end

    # An even number of backslashes leaves the following delimiter unescaped.
    WRAP_PROPERTY_VALUE_DELIMETER_REGEX = /(?<!\\)(?:\\\\)*([,;])/.freeze
    WRAP_PROPERTY_VALUE_SPLIT_REGEX = /(?<!\\)(?:\\\\)*([;,])/.freeze


    def wrap_property_value(component, fields, multi_property)
      klass = get_wrapper_class component, fields
      if wrap_in_array? klass, fields[:value], multi_property
        delimiter = fields[:value].match(WRAP_PROPERTY_VALUE_DELIMETER_REGEX)[1]
        Icalendar::Values::Helpers::Array.new split_property_value(fields[:value]),
                                     klass,
                                     fields[:params],
                                     delimiter: delimiter,
                                     timezone_store: timezone_store
      else
        klass.new fields[:value], fields[:params], timezone_store: timezone_store
      end
    rescue Icalendar::Values::DateTime::FormatError => fe
      raise fe if strict?
      fields[:params]['value'] = ['DATE']
      retry
    end

    WRAP_IN_ARRAY_REGEX_1 = /(?<!\\)(?:\\\\)*[,;]/.freeze
    WRAP_IN_ARRAY_REGEX_2 = /(?<!\\)(?:\\\\)*;/.freeze

    def wrap_in_array?(klass, value, multi_property)
      # Both wrap regexes require a delimiter, so skip them when there is none.
      return false unless value.is_a?(String) && (value.include?(',') || value.include?(';'))

      klass.value_type != 'RECUR' &&
        ((multi_property && value =~ WRAP_IN_ARRAY_REGEX_1) || value =~ WRAP_IN_ARRAY_REGEX_2)
    end

    GET_WRAPPER_CLASS_GSUB_REGEX = /(?:\A|-|\s+)(.)/.freeze

    def get_wrapper_class(component, fields)
      klass = component.class.default_property_types[fields[:name]]
      if !fields[:params]['value'].nil?
        klass_name = fields[:params].delete('value').first
        unless klass_name.upcase == klass.value_type
          klass_name = "Icalendar::Values::#{klass_name.downcase.gsub(GET_WRAPPER_CLASS_GSUB_REGEX) { |m| m[-1].upcase }}"
          begin
            klass = Object.const_get klass_name if Object.const_defined?(klass_name)
          rescue NameError => e
            Icalendar.logger.error "NameError trying to find value type for #{component.name} | #{fields[:name]}: #{e.message}"
            raise e if strict?
          end
        end
      end
      klass
    end

    def strict?
      !!@strict
    end

    def verbose?
      @verbose
    end

    private

    def split_property_value(value)
      parts = []
      start = 0
      value.scan(WRAP_PROPERTY_VALUE_SPLIT_REGEX) do
        delimiter = Regexp.last_match
        parts << value[start...delimiter.begin(1)]
        start = delimiter.end(1)
      end
      parts << value[start..-1]
      parts.pop while parts.last == ''
      parts
    end

    def component_class
      @component_class ||= Icalendar::Calendar
    end

    def parse_depth_limit
      # a valid ics file should only have 3 levels. Leaving some room for non-compliant custom components
      @parse_depth_limit ||= 5
    end

    def parse_component(component)
      self.parse_depth += 1
      raise ParseError.new("ics file nested too deeply") if parse_depth > parse_depth_limit
      while (fields = next_fields)
        if fields[:name] == 'end'
          klass_name = fields[:value].delete_prefix('V').capitalize
          timezone_store.store(component) if klass_name == 'Timezone'
          break
        elsif fields[:name] == 'begin'
          klass_name = fields[:value].delete_prefix('V').tr('-', '_').capitalize
          Icalendar.logger.debug { "Adding component #{klass_name}" }
          if Object.const_defined? "Icalendar::#{klass_name}"
            component.add_component parse_component(Object.const_get("Icalendar::#{klass_name}").new)
          elsif Object.const_defined? "Icalendar::Timezone::#{klass_name}"
            component.add_component parse_component(Object.const_get("Icalendar::Timezone::#{klass_name}").new)
          else
            component.add_custom_component klass_name, parse_component(Component.new klass_name.downcase, fields[:value])
          end
        else
          parse_property component, fields
        end
      end
      self.parse_depth -= 1
      component
    end

    def read_in_data
      @data = source.gets and @data.chomp!
    end

    NEXT_FIELDS_WHITESPACE_REGEX = /\A\s*\z/.freeze

    def next_fields
      line = @data or return nil
      loop do
        read_in_data
        if @data.nil?
          break
        elsif @data.bytesize > 1 && @data.start_with?(' ', "\t")
          line << @data[1..]
        elsif @data.empty? || @data.match?(NEXT_FIELDS_WHITESPACE_REGEX)
          next
        else
          break
        end
      end
      parse_fields line
    end

    NAME = '[-a-zA-Z0-9]+'
    QSTR = '"[^"]*"'
    PTEXT = '[^";:,]*'
    PVALUE = "(?:#{QSTR}|#{PTEXT})"
    PARAM = "(#{NAME})=(#{PVALUE}(?:,#{PVALUE})*)"
    VALUE = '.*'
    LINE = "(?<name>#{NAME})(?<params>(?:;#{PARAM})*):(?<value>#{VALUE})"
    BAD_LINE = "(?<name>#{NAME})(?<params>(?:;#{PARAM})*)"
    LINE_REGEX = %r{#{LINE}}.freeze
    BAD_LINE_REGEX = %r{#{BAD_LINE}}.freeze
    PARAM_REGEX = %r{#{PARAM}}.freeze
    PVALUE_REGEX = %r{#{PVALUE}}.freeze
    PVALUE_GSUB_REGEX = /\A"|"\z/.freeze
    SIMPLE_LINE_NAME_REGEX = /\A[-a-zA-Z0-9]+\z/.freeze

    def parse_fields(input)
      debug = ::Logger::DEBUG >= Icalendar.logger.level

      unless debug
        colon = input.byteindex(':')
        if colon
          name = input.byteslice(0, colon)
          if name.match?(SIMPLE_LINE_NAME_REGEX)
            normalize_name!(name)
            return {
              name: name,
              params: {},
              value: input.byteslice(colon + 1, input.bytesize - colon - 1)
            }
          end
        end
      end

      if parts = LINE_REGEX.match(input)
        value = parts[:value]
      else
        parts = BAD_LINE_REGEX.match(input) unless strict?
        parts or fail ParseError, "Invalid iCalendar input line: #{input}"
        # Non-strict and bad line so use a value of empty string
        value = ''
      end

      params = {}
      parts[:params].scan PARAM_REGEX do |match|
        param_name = match[0].downcase
        params[param_name] ||= []
        match[1].scan PVALUE_REGEX do |param_value|
          if param_value.size > 0
            param_value = param_value.gsub(PVALUE_GSUB_REGEX, '')
            params[param_name] << param_value
          end
        end
      end
      # Building the string to send to the logger is expensive.
      # Only do it if the logger is at the right log level.
      if debug
        Icalendar.logger.debug "Found fields: #{parts.inspect} with params: #{params.inspect}"
      end
      name = normalize_name!(parts[:name])
      {
        name: name,
        params: params,
        value: value
      }
    end

    # Property and component names are ASCII (they matched NAME above), so downcase!
    # is equivalent to tr!('A-Z', 'a-z') but avoids building a translation table.
    def normalize_name!(name)
      name.downcase!
      name.tr!('-', '_') if name.include?('-')
      name
    end

    class ParseError < RuntimeError
    end
  end
end
