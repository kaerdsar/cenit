[String, Integer, Float, Boolean, Date, DateTime, Time].each do |klass|
  klass.class_eval("
    def self.to_json_schema
      {'$ref' => #{klass.name}}
    end
  ")
end

class String
  def to_json_schema
    Xsd::BUILD_IN_TYPES[self] || {'$ref' => self}
  end

  def to_title
    self.
        gsub(/([A-Z])(\d)/,'\1 \2').
        gsub(/([a-z])(\d|[A-Z])/,'\1 \2').
        gsub(/(\d)([a-z]|[A-Z])/,'\1 \2').
        tr('_', ' ').
        tr('-', ' ')
  end
end