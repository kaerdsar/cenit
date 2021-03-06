module Mongoid
  module CenitExtension
    extend ActiveSupport::Concern

    module ClassMethods

      def collection_size(scale = 1)
        mongo_session.command(collstats: collection_name, scale: scale)['size'] rescue 0
      end

      def for_property(property)
        (relation = try(:reflect_on_association, property)) && relation.try(:klass)
      end

      def for_each_association(&block)
        reflect_on_all_associations(:embeds_one,
                                    :embeds_many,
                                    :has_one,
                                    :has_many,
                                    :has_and_belongs_to_many,
                                    :belongs_to).each do |relation|
          block.yield(name: relation.name, embedded: relation.embedded?)
        end
      end

      def other_affected_models
        models = []
        reflect_on_all_associations(:embedded_in,
                                    :embeds_one,
                                    :embeds_many,
                                    :has_one,
                                    :has_many,
                                    :has_and_belongs_to_many,
                                    :belongs_to).each do |relation|
          models << relation.klass unless [:has_and_belongs_to_many, :belongs_to].include?(relation.macro) && relation.inverse_of.nil?
        end
        models.uniq
      end

      def other_affected_by
        reflect_on_all_associations(:embedded_in,
                                    :embeds_one,
                                    :embeds_many,
                                    :has_one,
                                    :has_many,
                                    :has_and_belongs_to_many,
                                    :belongs_to).collect { |relation| relation.klass }.uniq
      end
    end
  end
end