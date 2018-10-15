# frozen_string_literal: true

module ActiveInteraction
  class Base
    # @!method self.array(*attributes, options = {}, &block)
    #   Creates accessors for the attributes and ensures that values passed to
    #     the attributes are Arrays.
    #
    #   @!macro filter_method_params
    #   @param block [Proc] filter method to apply to each element
    #
    #   @example
    #     array :ids
    #   @example
    #     array :ids do
    #       integer
    #     end
  end

  # @private
  class ArrayFilter < Filter
    include Missable

    register :array

    private

    def klasses
      %w[
        ActiveRecord::Relation
        ActiveRecord::Associations::CollectionProxy
      ].each_with_object([Array]) do |name, result|
        next unless (klass = name.safe_constantize)
        result.push(klass)
      end
    end

    def matches?(value)
      klasses.any? { |klass| value.is_a?(klass) }
    rescue NoMethodError
      false
    end

    def adjust_output(value, context)
      return value if filters.empty?

      filter = filters.values.first
      value.map { |e| filter.clean(e, context) }
    end

    def convert(value)
      if value.respond_to?(:to_ary)
        value.to_ary
      else
        value
      end
    rescue NoMethodError
      false
    end

    def add_option_in_place_of_name(klass, options)
      filter_name_or_option = {
        ObjectFilter    => :class,
        RecordFilter    => :class,
        InterfaceFilter => :from
      }
      if klass == InterfaceFilter && options.key?(:methods)
        options
      elsif (key = filter_name_or_option[klass]) && !options.key?(key)
        options.merge(
          :"#{key}" => name.to_s.singularize.camelize.to_sym
        )
      else
        options
      end
    end

    def method_missing(*, &block) # rubocop:disable Style/MethodMissing
      super do |klass, names, options|
        options = add_option_in_place_of_name(klass, options)

        filter = klass.new(names.first || '', options, &block)

        filters[filters.size.to_s.to_sym] = filter

        validate!(filter)
      end
    end

    def validate!(filter)
      error_multiple_inner_filters if filters.size > 1
      error_named_inner_filter unless filter.name.empty?
      error_inner_filter_using_groups unless filter.groups.empty?
      error_inner_filter_using_default if filter.default?

      nil
    end

    def error_multiple_inner_filters
      raise InvalidFilterError, ErrorMessage.new(
        issue: {
          desc: 'An array filter can only have one inner filter.',
          code: source_str,
          lines: 1..-2
        }
      )
    end

    def error_inner_filter_using_groups
      raise InvalidFilterError, ErrorMessage.new(
        issue: {
          desc: %q(Inner array filters can't be referenced so they can't belong to a group.),
          code: source_str,
          lines: [1]
        },
        fix: {
          if: -> { !options[:groups] },
          desc: %q(If you're trying to set groups for the entire array, that can be done at the array level.),
          code: source_str
            .sub(/,? groups:.*?(?:,|$)/, '')
            .sub(/ do/, ", groups: #{filters.first.last.groups.inspect} do")
        }
      )
    end

    def error_named_inner_filter
      raise InvalidFilterError, ErrorMessage.new(
        issue: {
          desc: 'Inner values can not be referenced so they do not need to be named.',
          code: source_str,
          lines: [1]
        },
        fix: {
          desc: 'You can fix this by removing the name.',
          code: source_str
            .sub(/\A(.*?#{filters.first.last.class.slug}) :#{filters.first.last.name},?(.*)\z/m, '\1\2')
        }
      )
    end

    def error_inner_filter_using_default
      raise InvalidFilterError, ErrorMessage.new(
        issue: {
          desc: 'There are no inner filter values to set a default for.',
          code: source_str,
          lines: [1]
        },
        fix: {
          if: -> { !options[:default] },
          desc: %q(If you're trying to set a default for the entire array, that can be done at the array level.),
          code: source_str
            .sub(/ do/, ", default: [#{filters.first.last.default.inspect}] do")
        }
      )
    end
  end
end
