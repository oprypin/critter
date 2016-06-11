# Copyright (C) 2016 Oleh Prypin <oleh@pryp.in>
# This file is part of Critter.
# Released under the terms of the MIT license (see LICENSE).


abstract class Options
  macro def initialize(argv = ARGV)
    {% begin %}
      {% for var in vars = @type.instance_vars %}
        @{{var.id}} = default_{{var.id}}()
      {% end %}

      argv.each do |s|
        if !s.includes? '='
          raise "Options must be specified like 'name=value', not '#{s}'"
        end
        name, value = s.split('=', 2)
        name = name.downcase.sub(/^-+/, "").gsub('-', '_')
        case name
        {% for var in vars %}
          when {{var.name.stringify}}
            @{{var.id}} = convert_{{var.id}}(value)
        {% end %}
        else
          raise "Unknown option '#{name}'"
        end
      end
    {% end %}
  end

  macro option(name, type, convert)
    {% if name.is_a? Assign %}
      {% default = name.value %}
      {% name = name.target %}
    {% else %}
      {% default = nil %}
    {% end %}

    @{{name.id}} : {{type.id}}?
    def {{name.id}}? : {{type.id}}?
      @{{name.id}} != nil ? @{{name.id}} : default_{{name.id}}
    end
    def {{name.id}} : {{type.id}}
      raise "Option '{{name.id}}' is mandatory" if {{name.id}}? == nil
      {{name.id}}?.not_nil!
    end
    protected def convert_{{name.id}}(s)
      {{convert}}
    end
    protected def default_{{name.id}}
      {{default}}
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
