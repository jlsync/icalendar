# frozen_string_literal: true

module Icalendar

  module HasProperties

    PropertyMetadata = Struct.new(:name, :reader, :wire_name, :default_type, :multi)
    PROPERTY_WIRE_NAME_GSUB_REGEX = /\Aip_/.freeze

    def self.included(base)
      base.extend ClassMethods
      base.class_eval do
        attr_reader :custom_properties
      end
    end

    def initialize(...)
      @custom_properties = Hash.new
      super
    end

    def valid?(strict = false)
      self.class.required_properties.each_pair do |prop, validator|
        validator.call(self, send(prop)) or return false
      end
      self.class.mutex_properties.each do |mutexprops|
        mutexprops.map { |p| send p }.compact.size > 1 and return false
      end
      if strict
        self.class.suggested_single_properties.each do |single_prop|
          send(single_prop).size > 1 and return false
        end
      end
      true
    end

    def property(property_name)
      property_name = property_name.downcase
      if self.class.single_property?(property_name) || self.class.multiple_property?(property_name)
        send property_name
      else
        custom_property property_name
      end
    end

    def custom_property(property_name)
      custom_properties[property_name.downcase] || []
    end

    def append_custom_property(property_name, value)
      property_name = property_name.downcase
      if self.class.single_property?(property_name)
        send "#{property_name}=", value
      elsif self.class.multiple_property?(property_name)
        send "append_#{property_name}", value
      elsif value.is_a? Icalendar::Value
        (custom_properties[property_name] ||= []) << value
      else
        (custom_properties[property_name] ||= []) << Icalendar::Values::Text.new(value)
      end
    end

    def method_missing(method, *args, &block)
      method_name = method.to_s
      if method_name.start_with? 'x_'
        if method_name.end_with? '='
          append_custom_property method_name.chomp('='), args.first
        else
          custom_property method_name
        end
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      method.to_s.start_with?('x_') || super
    end

    module ClassMethods
      class PropertyList < ::Array
        attr_reader :mutation_version

        def initialize(...)
          @mutation_version = 0
          super
        end

        %i[
          << []= append clear collect! compact! concat delete delete_at
          delete_if fill filter! flatten! insert keep_if map! pop prepend push
          reject! replace reverse! rotate! select! shift shuffle! slice! sort!
          sort_by! uniq! unshift
        ].each do |mutator|
          class_eval <<~RUBY, __FILE__, __LINE__ + 1
            def #{mutator}(...)
              @mutation_version += 1
              super
            end
          RUBY
        end

        EMPTY = new.freeze
      end

      def properties
        single_properties + multiple_properties
      end

      def single_properties
        return @single_properties if @single_properties
        return PropertyList::EMPTY if frozen?

        @single_properties = PropertyList.new
      end

      def multiple_properties
        return @multiple_properties if @multiple_properties
        return PropertyList::EMPTY if frozen?

        @multiple_properties = PropertyList.new
      end

      def single_property?(prop)
        single_property_lookup.key?(prop.to_s)
      end

      def multiple_property?(prop)
        multiple_property_lookup.key?(prop.to_s)
      end

      def property_writer(prop)
        singles = single_properties
        multis = multiple_properties
        sv = singles.respond_to?(:mutation_version) ? singles.mutation_version : singles.hash
        mv = multis.respond_to?(:mutation_version) ? multis.mutation_version : multis.hash
        cache = @property_writer_cache
        return cache[2][prop.to_s] if cache && cache[0] == sv && cache[1] == mv

        writers = build_property_writer_map(singles, multis)
        @property_writer_cache = [sv, mv, writers].freeze unless frozen?
        writers[prop.to_s]
      end

      def required_properties
        @required_properties ||= {}
      end

      def suggested_single_properties
        @suggested_single_properties ||= []
      end

      def mutex_properties
        @mutex_properties ||= []
      end

      def renderable_properties
        @renderable_properties ||= build_renderable_properties
      end

      def default_property_types
        @default_property_types ||= Hash.new { |h,k| Icalendar::Values::Text }
      end

      def required_property(prop, klass = Icalendar::Values::Text, validator = nil)
        validator ||= ->(component, value) { !value.nil? }
        self.required_properties[prop] = validator
        single_property prop, klass, false
      end

      def required_multi_property(prop, klass = Icalendar::Values::Text, validator = nil)
        validator ||= ->(component, value) { !value.compact.empty? }
        self.required_properties[prop] = validator
        multi_property prop, klass, false
      end

      def optional_single_property(prop, klass = Icalendar::Values::Text, new_property = false)
        single_property prop, klass, new_property
      end

      def mutually_exclusive_properties(*properties)
        self.mutex_properties << properties
      end

      def optional_property(prop, klass = Icalendar::Values::Text, suggested_single = false, new_property = false, single_line = false)
        self.suggested_single_properties << prop if suggested_single
        multi_property prop, klass, new_property, single_line
      end

      def single_property(prop, klass, new_property)
        self.single_properties << prop.to_s
        self.default_property_types[prop.to_s] = klass
        reset_renderable_properties_cache

        property_var = :"@#{prop}"

        attr_reader prop.to_sym

        define_method "#{prop}=" do |value|
          instance_variable_set property_var, map_property_value(value, klass, false, new_property)
        end
      end

      def multi_property(prop, klass, new_property, single_line = false)
        self.multiple_properties << prop.to_s
        self.default_property_types[prop.to_s] = klass
        reset_renderable_properties_cache
        property_var = :"@#{prop}"
        setter = :"#{prop}="

        define_method "#{prop}=" do |value|
          if !single_line && value.is_a?(::Array)
            instance_variable_set property_var, map_multi_property_array(value, klass, new_property)
          else
            mapped = map_property_value value, klass, true, new_property
            if single_line && !(mapped.is_a?(Icalendar::Values::Helpers::Array) && mapped.empty?)
              instance_variable_set property_var, nil.equal?(mapped) ? [] : [mapped]
            elsif mapped.is_a? Icalendar::Values::Helpers::Array
              instance_variable_set property_var, mapped.to_a.compact
            else
              instance_variable_set property_var, nil.equal?(mapped) ? [] : [mapped]
            end
          end
        end

        define_method prop do
          value = instance_variable_get property_var
          if value.nil? && !instance_variable_defined?(property_var)
            send setter, nil
          else
            value
          end
        end

        define_method "append_#{prop}" do |value|
          send(prop) << map_property_value(value, klass, true, new_property)
        end
      end

      private

      def single_property_lookup
        props = single_properties
        version = props.respond_to?(:mutation_version) ? props.mutation_version : props.hash
        cache = @single_property_cache
        return cache[1] if cache && cache[0] == version

        lookup = props.each_with_object({}) { |p, h| h[p] = true }
        @single_property_cache = [version, lookup].freeze unless frozen?
        lookup
      end

      def multiple_property_lookup
        props = multiple_properties
        version = props.respond_to?(:mutation_version) ? props.mutation_version : props.hash
        cache = @multiple_property_cache
        return cache[1] if cache && cache[0] == version

        lookup = props.each_with_object({}) { |p, h| h[p] = true }
        @multiple_property_cache = [version, lookup].freeze unless frozen?
        lookup
      end

      def build_property_writer_map(singles, multis)
        writers = {}
        singles.each { |p| writers[p] = :"#{p}=" }
        multis.each { |p| writers[p] = :"append_#{p}" }
        writers
      end

      def build_renderable_properties
        multi_lookup = multiple_properties.each_with_object({}) { |prop, h| h[prop] = true }
        properties.map do |prop|
          PropertyMetadata.new(
            prop,
            prop.to_sym,
            prop.gsub(PROPERTY_WIRE_NAME_GSUB_REGEX, '').gsub('_', '-').upcase,
            default_property_types[prop],
            multi_lookup.key?(prop)
          )
        end
      end

      def reset_renderable_properties_cache
        @renderable_properties = nil
        return if frozen?

        singles = single_properties
        multis = multiple_properties
        sv = singles.respond_to?(:mutation_version) ? singles.mutation_version : singles.hash
        mv = multis.respond_to?(:mutation_version) ? multis.mutation_version : multis.hash
        @single_property_cache = [sv, singles.each_with_object({}) { |p, h| h[p] = true }].freeze
        @multiple_property_cache = [mv, multis.each_with_object({}) { |p, h| h[p] = true }].freeze
        @property_writer_cache = [sv, mv, build_property_writer_map(singles, multis)].freeze
      end
    end

    private

    def map_property_value(value, klass, multi_valued, new_property)
      return value if value.nil? || value.is_a?(Icalendar::Value)

      if value.is_a? ::Array
        params = new_property ? { 'value' => klass.value_type } : {}
        Icalendar::Values::Helpers::Array.new value, klass, params, { 'delimiter' => (multi_valued ? ',' : ';') }
      elsif new_property
        klass.new value, { 'value' => klass.value_type }
      else
        klass.new value
      end
    end

    def map_multi_property_array(values, klass, new_property)
      context = Icalendar::DowncasedHash.new('delimiter' => ',')
      mapped = values.map do |v|
        if v.is_a? Icalendar::Values::Helpers::Array
          Icalendar::Values::Helpers::Array.new v.value, klass, v.ical_params, { 'delimiter' => v.value_delimiter }
        elsif v.is_a? ::Array
          params = new_property ? { 'value' => klass.value_type } : {}
          Icalendar::Values::Helpers::Array.new v, klass, params, context
        elsif v.is_a? Icalendar::Value
          v
        elsif new_property
          klass.new v, { 'value' => klass.value_type }, context
        else
          params = klass <= Icalendar::Values::Helpers::TimeWithZone ? {} : Icalendar::Value::EMPTY_HASH
          klass.new v, params, context
        end
      end
      mapped.compact!
      mapped
    end

  end
end
