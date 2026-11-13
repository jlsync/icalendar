# frozen_string_literal: true


require 'delegate'
require 'icalendar/downcased_hash'

module Icalendar

  class Value < ::SimpleDelegator

    EMPTY_HASH = {}.freeze

    attr_accessor :ical_params, :context

    def initialize(value, params = EMPTY_HASH, context = EMPTY_HASH)
      @ical_params = ::Icalendar::DowncasedHash(params)
      @context = ::Icalendar::DowncasedHash(context)
      super value
    end

    def ical_param(key, value)
      @ical_params[key] = value
      @params_cached = false
    end

    def value
      __getobj__
    end

    def to_ical(default_type)
      ical_param 'value', self.value_type if needs_value_type?(default_type)
      "#{params_ical}:#{value_ical}"
    end

    def params_ical
      return @serialized_params if @params_cached
      @serialized_params = if ical_params.empty?
        nil
      else
        buf = ::String.new(';')
        first = true
        ical_params.each do |name, value|
          buf << ';' unless first
          first = false
          append_param_ical(buf, name, value)
        end
        buf
      end
      @params_cached = true
      @serialized_params
    end

    VALUE_TYPE_GSUB_REGEX_1 = /\A.*::/.freeze
    VALUE_TYPE_GSUB_REGEX_2 = /(?<!\A)[A-Z]/.freeze

    def self.value_type
      @value_type ||= name.gsub(VALUE_TYPE_GSUB_REGEX_1, '').gsub(VALUE_TYPE_GSUB_REGEX_2, '-\0').upcase
    end

    def value_type
      self.class.value_type
    end

    def ==(other)
      if other.is_a?(::Icalendar::Value)
        super(other.value) && ical_params == other.ical_params
      else
        super
      end
    end

    private

    def needs_value_type?(default_type)
      self.class != default_type
    end

    def append_param_ical(buf, name, param_value)
      name_str = name.to_s
      buf << (name_str.include?('_') ? name_str.tr('_', '-').upcase : name_str.upcase) << '='
      if param_value.is_a? ::Array
        param_value.each_with_index do |v, idx|
          buf << ',' if idx > 0
          append_escaped_param_value(buf, v)
        end
      else
        append_escaped_param_value(buf, param_value)
      end
    end

    def append_escaped_param_value(buf, value)
      s = value.to_s
      v = s.include?('"') ? s.gsub('"', "'") : s
      if v.match?(ESCAPE_PARAM_VALUE_REGEX)
        buf << '"' << v << '"'
      else
        buf << v
      end
    end

    def param_ical(name, param_value)
      buf = ::String.new
      append_param_ical(buf, name, param_value)
      buf
    end

    ESCAPE_PARAM_VALUE_REGEX = /[;:,]/.freeze

    def escape_param_value(value)
      s = value.to_s
      v = s.include?('"') ? s.gsub('"', "'") : s
      v.match?(ESCAPE_PARAM_VALUE_REGEX) ? %("#{v}") : v
    end

  end

end

# helpers; not actual iCalendar value types
require_relative 'values/helpers/array'
require_relative 'values/date_or_date_time'

# iCalendar value types
require_relative 'values/binary'
require_relative 'values/boolean'
require_relative 'values/date'
require_relative 'values/date_time'
require_relative 'values/duration'
require_relative 'values/float'
require_relative 'values/integer'
require_relative 'values/period'
require_relative 'values/recur'
require_relative 'values/text'
require_relative 'values/time'
require_relative 'values/uri'
require_relative 'values/utc_offset'

# further refine above classes
require_relative 'values/cal_address'
