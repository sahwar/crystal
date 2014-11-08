module Crystal
  class TypeLookup < Visitor
    getter! type

    def self.lookup(root_type, node, self_type = root_type)
      lookup = new root_type, self_type
      node.accept lookup
      lookup.type.not_nil!
    end

    def initialize(@root)
      @self_type = @root
    end

    def initialize(@root, @self_type)
    end

    delegate program, @root

    def visit(node : ASTNode)
      true
    end

    def visit(node : Path)
      the_type = @root.lookup_type(node)
      if the_type && the_type.is_a?(Type)
        @type = the_type.remove_alias_if_simple
      else
        node.raise("undefined constant #{node}")
      end
    end

    def visit(node : Union)
      types = node.types.map do |ident|
        ident.accept self
        type
      end
      @type = program.type_merge(types)
      false
    end

    def end_visit(node : Virtual)
      @type = type.instance_type.virtual_type
    end

    def end_visit(node : Metaclass)
      @type = type.virtual_type
    end

    def visit(node : Generic)
      node.name.accept self

      instance_type = @type.not_nil!
      unless instance_type.is_a?(GenericClassType)
        node.raise "#{instance_type} is not a generic class, it's a #{instance_type.type_desc}"
      end

      if instance_type.variadic
        min_needed = instance_type.type_vars.length - 1
        if node.type_vars.length < min_needed
          node.raise "wrong number of type vars for #{instance_type} (#{node.type_vars.length} for #{min_needed}..)"
        end
      else
        if instance_type.type_vars.length != node.type_vars.length
          node.raise "wrong number of type vars for #{instance_type} (#{node.type_vars.length} for #{instance_type.type_vars.length})"
        end
      end

      type_vars = node.type_vars.map do |type_var|
        type_var.accept self
        @type.not_nil! as TypeVar
      end
      @type = instance_type.instantiate(type_vars)
      false
    end

    def visit(node : Fun)
      types = [] of Type
      if inputs = node.inputs
        inputs.each do |input|
          input.accept self
          types << type
        end
      end

      if output = node.output
        output.accept self
        types << type
      else
        types << program.void
      end

      @type = program.fun_of(types)
      false
    end

    def visit(node : Self)
      @type = @self_type
      false
    end

    def visit(node : TypeOf)
      meta_vars = MetaVars { "self": MetaVar.new("self", @self_type) }
      visitor = TypeVisitor.new(program, meta_vars)
      node.expressions.each &.accept visitor
      @type = program.type_merge node.expressions
      false
    end

    def visit(node : Underscore)
      node.raise "can't use underscore as generic type argument"
    end
  end
end
