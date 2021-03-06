module Setup
  class BuildInDataType < BaseDataType

    attr_reader :model

    def title
      @title ||= model.to_s.to_title
    end

    def initialize(model)
      @model = model
    end

    def records_model
      model
    end

    def schema
      @schema ||= build_schema
    end

    def find_data_type(ref)
      BuildInDataType.build_ins[ref]
    end

    def embedding(*fields)
      @embedding = fields.is_a?(Enumerable) ? fields : [fields]
      self
    end

    def referenced_by(field_name)
      @referenced_by = field_name
      self
    end

    def and(to_merge)
      @to_merge = to_merge.deep_stringify_keys
      self
    end

    def with(*fields)
      if fields.present?
        raise Exception.new('Illegal argument') if fields.empty?
        fields = [fields] unless fields.is_a?(Enumerable)
        @with = fields.collect(&:to_s)
      else
        @with = nil
      end
      self
    end

    def including(*fields)
      if fields.present?
        raise Exception.new('Illegal argument') if fields.empty?
        fields = [fields] unless fields.is_a?(Enumerable)
        @including = fields.collect(&:to_s)
      else
        @including = nil
      end
      self
    end

    def excluding(*fields)
      if fields.present?
        raise Exception.new('Illegal argument') if fields.empty?
        fields = [fields] unless fields.is_a?(Enumerable)
        @excluding = fields.collect(&:to_s)
      else
        @excluding = nil
      end
      self
    end

    class << self

      def build_ins
        @build_ins ||= {}
      end

      def regist(model)
        model.include(Setup::OrmModelAware)
        model.include(Edi::Formatter)
        model.include(Edi::Filler)
        model.class.include(Mongoid::CenitExtension)
        build_ins[model.to_s] = BuildInDataType.new(model)
      end
    end

    EXCLUDED_FIELDS = %w{_id created_at updated_at version}
    EXCLUDED_RELATIONS = %w{account creator updater}

    private

    MONGOID_TYPE_MAP = {Array => 'array',
                        BigDecimal => 'integer',
                        Mongoid::Boolean => 'boolean',
                        Date => {'type' => 'string', 'format' => 'date'},
                        DateTime => {'type' => 'string', 'format' => 'date-time'},
                        Float => 'number',
                        Hash => 'object',
                        Integer => 'integer',
                        String => 'string',
                        Symbol => 'string',
                        Time => {'type' => 'string', 'format' => 'time'}}

    def excluded?(name)
      name = name.to_s
      (@excluding && @excluding.include?(name)) || EXCLUDED_FIELDS.include?(name) || EXCLUDED_RELATIONS.include?(name)
    end

    def included?(name)
      name = name.to_s
      (@with && @with.include?(name)) || (@including && @including.include?(name)) || !(@with || excluded?(name))
    end

    def build_schema
      schema = {'type' => 'object', 'properties' => properties = {}}
      schema[:referenced_by.to_s] = @referenced_by.to_s if @referenced_by
      (fields = model.fields).each do |field_name, field|
        properties[field_name] = json_schema_type(field.type) if !field.is_a?(Mongoid::Fields::ForeignKey) && included?(field_name)
      end
      (relations = model.reflect_on_all_associations(:embeds_one,
                                                     :embeds_many,
                                                     :has_one,
                                                     :belongs_to,
                                                     :has_many,
                                                     :has_and_belongs_to_many)).each do |relation|
        if included?(relation.name)
          property_schema = case relation.macro
                            when :embeds_one
                              {'$ref' => relation.klass.to_s}
                            when :embeds_many
                              {'type' => 'array', 'items' => {'$ref' => relation.klass.to_s}}
                            when :has_one
                              {'$ref' => relation.klass.to_s, 'referenced' => true, 'export_embedded' => @embedding && @embedding.include?(relation.name)}
                            when :belongs_to
                              {'$ref' => relation.klass.to_s, 'referenced' => true, 'export_embedded' => @embedding && @embedding.include?(relation.name)} if (@including && @including.include?(relation.name.to_s)) || relation.inverse_of.nil?
                            when :has_many, :has_and_belongs_to_many
                              {'type' => 'array', 'items' => {'$ref' => relation.klass.to_s, 'referenced' => true, 'export_embedded' => @embedding && @embedding.include?(relation.name)}}
                            end
          properties[relation.name] = property_schema if property_schema
        end
      end
      schema = @to_merge.merge(schema) if @to_merge
      schema.to_json
    end

    def json_schema_type(mongoid_type)
      ((type = MONGOID_TYPE_MAP[mongoid_type]).is_a?(Hash)) ? type : {'type' => type}
    end
  end
end
