# Copyright (C) 2016 Oleh Prypin <oleh@pryp.in>
# This file is part of Critter.
# Released under the terms of the MIT license (see LICENSE).


record Option(T), value : T, set : Bool do
  def initialize
    @value = uninitialized T
    @set = false
  end

  def initialize(@value : T)
    @set = true
  end
end

abstract class Options
  def initialize(argv = ARGV)
    {% begin %}
      argv.each do |s|
        if !s.includes? '='
          raise "Options must be specified like 'name=value', not '#{s}'"
        end
        name, value = s.split('=', 2)
        name = name.downcase.sub(/^-+/, "").gsub('-', '_')
        case name
        {% for var in @type.instance_vars %}
          when {{var.name.stringify}}
            self.{{var.id}} = value
        {% end %}
        else
          raise "Unknown option '#{name}'"
        end
      end

      {% for var in @type.instance_vars %}
        {% var = var.id %}
        if @{{var}}.is_a?(Option) && !@{{var}}.set && !responds_to?(:{{var}}!)
          raise "Option '{{var}}' is mandatory"
        end
      {% end %}
    {% end %}
  end

  macro option(name, type, &convert)
    {% if name.is_a? Assign %}
      {% default = name.value %}
      {% name = name.target.id %}

      def {{name}}
        @{{name}}.set ? @{{name}}.value : {{default}}
      end
      def {{name}}!
        if @{{name}}.set
          @{{name}}.value
        else
          raise TypeCastError.new("Option '{{name}}' hasn't been set")
        end
      end
    {% else %}
      {% name = name.id %}

      def {{name}}
        @{{name}}.value
      end
    {% end %}

    @{{name}} = Option({{type}}).new

    private def {{name}}=(s : String)
      @{{name}} = Option({{type}}).new(s.try {{convert}})
    end
  end

  macro string(name)
    option({{name}}, String, &.to_s)
  end
  macro int(name)
    option({{name}}, Int32, &.to_i)
  end
  macro bool(name)
    option({{name}}, Bool) { |s|
      {"true" => true, "yes" => true, "false" => false, "no" => false}.fetch(s.downcase) do
        raise ArgumentError.new("Invalid boolean: '#{s}'")
      end
    }
  end
end
