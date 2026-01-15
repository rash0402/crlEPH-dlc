using HDF5
using Printf

function inspect_h5(filepath)
    println("Inspecting: $filepath")
    h5open(filepath, "r") do file
        function list_obj(obj, prefix="  ")
            for name in keys(obj)
                item = obj[name]
                if isa(item, HDF5.Dataset)
                    sz = size(item)
                    println("$prefix$name: Dataset $sz")
                elseif isa(item, HDF5.Group)
                    println("$prefix$name: Group")
                    list_obj(item, prefix * "  ")
                end
            end
        end
        list_obj(file)
    end
end

if length(ARGS) > 0
    inspect_h5(ARGS[1])
else
    println("Usage: julia inspect_h5.jl <filepath>")
end
