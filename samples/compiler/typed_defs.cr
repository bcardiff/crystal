# $ make clean deps
# $ CRYSTAL_CONFIG_PATH=`pwd`/src ./bin/crystal build samples/compiler/typed_defs.cr
# $ ./typed_defs foo.cr

require "../src/compiler/crystal/**"

include Crystal

filename = ARGV[0]
source = %(require "./#{filename}")

compiler = Compiler.new
compiler.no_codegen = true
result = compiler.compile(Compiler::Source.new(".", source), "fake-no-build")

def parent_location(loc : Location)
  f = loc.filename

  if f.is_a?(VirtualFile)
    f.expanded_location
  else
    nil
  end
end

def real_location(loc : Location?)
  return nil unless loc

  res = loc
  parent = parent_location(loc)

  while parent
    res = parent
    parent = parent_location(parent)
  end

  res
end

class TypedDefCounter
  getter def_counter = Hash(String, Int32).new

  def process(result)
    process_result result
  end

  def process_typed_def(typed_def)
    if loc = real_location(typed_def.location)
      loc_str = loc.to_s
      @def_counter[loc_str] = @def_counter.fetch(loc_str, 0) + 1
    end
  end

  private def process_result(result : Compiler::Result)
    process_type result.program
    # if file_module = result.program.file_module? target_location.original_filename
    #   process_type file_module
    # end
  end

  private def process_type(type : Type) : Nil
    if type.is_a?(NamedType) || type.is_a?(Program) || type.is_a?(FileModule)
      type.types?.try &.each_value do |inner_type|
        process_type inner_type
      end
    end

    if type.is_a?(GenericType)
      type.generic_types.each_value do |instanced_type|
        process_type instanced_type
      end
    end

    process_type type.metaclass if type.metaclass != type

    if type.is_a?(DefInstanceContainer)
      type.def_instances.each do |key, typed_def|
        process_typed_def typed_def
      end
    end
  end
end

counter = TypedDefCounter.new
counter.process(result)

c = counter.def_counter.to_a
c.sort_by! &.[1]

c.each do |(l, c)|
  puts "#{c}\t#{l}"
end
