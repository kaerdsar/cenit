module Setup
  class Observer < Event

    BuildInDataType.regist(self).referenced_by(:name).excluding(:last_trigger_timestamps).including(:data_type)

    belongs_to :data_type, class_name: Setup::DataType.to_s, inverse_of: :events
    field :triggers, type: String

    validates_presence_of :data_type, :triggers

    before_save :format_triggers

    def triggers_apply_to?(obj_now, obj_before = nil)
      puts "Applying event '#{self}'..."
      r = true
      triggers_hash = JSON.parse(self.triggers)
      triggers_hash.each do |field_name, conditions|
        conditions.each do |_, condition|
          puts "...verifying trigger #{condition} on (#{obj_now},#{obj_before})::#{field_name}"
          puts c = if (condition['o'] == '_change')
                     field_changed(obj_now, obj_before, field_name)
                  else
                     condition_apply(obj_now, field_name, condition) && !condition_apply(obj_before, field_name, condition)
                  end
          r &&= c
        end
      end
      puts "Event '#{name ? name : self}' #{r ? '' : 'DOES NOT'} APPLIES!"
      r
    end

    def self.lookup(obj_now, obj_before = nil)
      where(data_type: obj_now.orm_model.data_type).each do |e|
        next unless e.triggers_apply_to?(obj_now, obj_before)
        Setup::Flow.where(active: true, event: e).each { |f| f.process(source_id: obj_now.id.to_s) }
      end
    end

    def to_s
      name ? name : super
    end

    private

    def field_changed(obj_now, obj_before, field_name)
      now_v = obj_now.try(field_name)
      before_v = obj_before.try(field_name)
      r = now_v != before_v
      puts "#{now_v} change? #{before_v} -> #{r}"
      r
    end

    def condition_apply(obj, field_name, condition)
      obj_v = obj.try(field_name)
      cond_v = valuate(condition['v'], obj_v.class)
      obj_values = if cond_v.is_a?(String) || (cond_v.is_a?(Array) && cond_v.detect { |e| e.is_a?(String) })
                     convert_to_string_array(obj_v)
                   else
                     [obj_v]
                   end
      unless op = condition['o']
        op = cond_v.is_a?(Array) ? 'in' : 'is'
      end
      begin
        obj_values.each do |obj_v|
          r = self.send("op_#{op}", obj_v, cond_v)
          puts "#{obj_v} #{op} #{cond_v} -> #{r}"
          return true if r
        end
      rescue Exception => ex
        puts "ERROR #{ex.message}"
      end
      false
    end

    def convert_to_string_array(obj_v)
      return [obj_v] if obj_v.is_a?(String)
      array = [:name, :title, :id].map { |property| obj_v.send(property).to_s rescue next }
      array << obj_v.to_s if array.empty?
      array
    end

    def valuate(cond_v, klass)
      return unless cond_v
      return cond_v if cond_v.is_a?(klass)
      cond_v = [cond_v] unless is_array = cond_v.is_a?(Array)
      to_obj_class = {NilClass => :to_s, Integer => :to_f, Fixnum => :to_f, Float => :to_f, String => :to_s,
                      Date => :to_date, DateTime => :to_datetime, Time => :to_time, ActiveSupport::TimeWithZone => :to_time,
                      FalseClass => :to_boolean, TrueClass => :to_boolean, BigDecimal => :to_d}[klass]
      cond_v = cond_v.collect do |e|
        case
        when e.nil? || (e.is_a?(String) && e.empty?)
          nil
        when to_obj_class.nil?
          e
        else
          begin
            e.to_s.send(to_obj_class)
          rescue Exception => ex
            puts "ERROR invoking [#{klass}](#{e} of class #{e.class}).#{to_obj_class} -> #{ex.message}"
            e
          end
        end
      end
      return is_array ? cond_v : cond_v[0]
    end

    def op_like(obj_v, cond_v)
      obj_v.nil? ? cond_v.nil? : (cond_v.nil? ? false : !obj_v.to_s[cond_v.to_s].nil?)
    end

    def op_is(obj_v, cond_v)
      obj_v == cond_v
    end

    def op_starts_with(obj_v, cond_v)
      obj_v.nil? ? cond_v.nil? : (cond_v.nil? ? false : obj_v.to_s.start_with?(cond_v.to_s))
    end

    def op_ends_with(obj_v, cond_v)
      obj_v.nil? ? cond_v.nil? : (cond_v.nil? ? false : obj_v.to_s.end_with?(cond_v.to_s))
    end

    def op__not_null(obj_v, cond_v)
      !op__null(obj_v, cond_v)
    end

    def op__null(obj_v, cond_v)
      obj_v.nil? || obj_v.to_s.empty?
    end

    def op_in(obj_v, cond_v)
      cond_v.include?(obj_v) rescue false
    end

    def op_default(obj_v, cond_v)
      op_is(obj_v, cond_v.nil? ? nil : cond_v[0])
    end

    def op_between(obj_v, cond_v)
      return false if obj_v.nil? || cond_v.nil?
      min = cond_v[1].nil? ? true : obj_v >= cond_v[1]
      max = cond_v[2].nil? ? true : obj_v <= cond_v[2]
      min && max
    end

    def op_today(obj_v, cond_v)
      op_between(obj_v, [nil, Date.today.at_beginning_of_day, Date.today.at_end_of_day])
    end

    def op_yesterday(obj_v, cond_v)
      op_between(obj_v, [nil, Date.yesterday.at_beginning_of_day, Date.yesterday.at_end_of_day])
    end

    def op_this_week(obj_v, cond_v)
      op_between(obj_v, [nil, Date.today.at_beginning_of_week.at_beginning_of_day, Date.today.at_end_of_week.at_end_of_day])
    end

    def op_last_week(obj_v, cond_v)
      op_between(obj_v, [nil, (last_week_beginning = Date.today.weeks_ago(1).at_beginning_of_week).at_beginning_of_day, last_week_beginning.at_end_of_week.at_end_of_day])
    end

    def format_triggers
      if self.triggers.nil? || self.triggers.length == 0
        errors.add(:triggers, "can't be blank")
        return false
      end
      begin
        self.triggers = self.triggers.gsub('=>', ':')
        hash = JSON.parse(self.triggers)
        hash.delete('_')
        if hash.blank?
          errors.add(:triggers, "can't be blank")
          return false
        end
        self.triggers = hash.to_json
      rescue
        errors.add(:triggers, 'are not valid')
        return false
      end
      modified = nil
      hash.each do |_, conditions|
        conditions.each do |_, condition|
          modified = condition['o'] = condition.delete('v') if condition['o'].nil? && %w(_null _not_null _change).include?(condition['v'])
        end
      end
      self.triggers = hash.to_json if modified
      if self.name.nil? || self.name.empty?
        triggered_fields = hash.keys
        self.name = "#{self.data_type.name} on #{triggered_fields.shift}"
        unless triggered_fields.empty?
          last = triggered_fields.pop
          triggered_fields.each { |f| self.name += ", #{f}" }
          self.name += " and #{last}"
        end
      end
    end
  end
end

class String
  def to_boolean
    self == 'true'
  end
end
