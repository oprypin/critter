# Copyright (C) 2016 Oleh Prypin <oleh@pryp.in>
# This file is part of Critter.
# Released under the terms of the MIT license (see LICENSE).


abstract class Options
  macro def initialize(argv = ARGV)
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
        if @{{var.id}} == nil && !responds_to?(:{{var.id}}_default)
          raise "Option '{{var.id}}' is mandatory"
        end
      {% end %}
    {% end %}
  end

  macro option(name, type, convert)
    {% if name.is_a? Assign %}
      {% default = name.value %}
      {% name = name.target.id %}

      protected def {{name}}_default
        {{default}}
      end

      def {{name}}
        @{{name}} || {{name}}_default
      end
      def {{name}}!
        @{{name}}.not_nil!
      end
    {% else %}
      {% name = name.id %}

      def {{name}}
        @{{name}}.not_nil!
      end
    {% end %}

    @{{name}} : {{type}}? = nil

    protected def {{name}}=(s : String)
      @{{name}} = {{convert}}
    end
  end

  macro string(name)
    option({{name}}, String, s)
  end
  macro int(name)
    option({{name}}, Int32, s.to_i)
  end
  macro bool(name)
    option({{name}}, Bool, ["true", "yes", "false", "no"].index(s.downcase).not_nil! < 2)
  end
end
