# construct BVH and export to binary file

using ArgParse

include("src/AccelerateRT.jl")
using .AccelerateRT

function parseCommandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--algMiddle"
            help = "construct simple BVH with middle criteria"
            action = :store_true
        "--algMedian"
            help = "construct simple BVH with media criteria"
            action = :store_true
        "--save"
            help = "save constructed structure"
            action = :store_true
        "--skip"
            help = "skip existing structure"
            action = :store_true
        "--show"
            help = "print structure"
            action = :store_true
        "model"
            help = "obj model path"
            required = true
    end
    return parse_args(s)
end

function main()
    args = parseCommandline()
    modelPath = args["model"]
    model = loadObjFile(modelPath)
    describeModel(model)
    bvhPath = joinpath("structures", replace(strip(modelPath), r"[^a-zA-Z0-9]" => "_"))
    bvh = nothing
    if args["algMiddle"]
        ext = ".middle.jld2"
        path = bvhPath * ext
        ordered = nothing
        if args["skip"] && isfile(path)
            println("Loading existing $path")
            data = loadFileBinary(path)
            bvh = data["BVH"]
            ordered = data["Ordered"]
        else
            println("Constructing BVHSimple with middle criteria")
            primitives = createPrimitives(model)
            ordered = BVH.BVHPrimitive{Float32, UInt32}[]
            bvh = BVH.constructBVHSimple!(primitives, ordered, 1, length(primitives), :middle)
        end
        if args["save"]
            println("Saving to $path")
            saveFileBinary(path, Dict("BVH" => bvh, "Ordered" => ordered, "Vertices" => model.vertices))
        end
    elseif args["algMedian"]
        ext = ".median.jld2"
        path = bvhPath * ext
        ordered = nothing
        if args["skip"] && isfile(path)
            println("Loading existing $path")
            data = loadFileBinary(path)
            bvh = data["BVH"]
            ordered = data["Ordered"]
        else
            println("Constructing BVHSimple with median criteria")
            primitives = createPrimitives(model)
            ordered = BVH.BVHPrimitive{Float32, UInt32}[]
            bvh = BVH.constructBVHSimple!(primitives, ordered, 1, length(primitives), :median)
        end
        if args["save"]
            println("Saving to $path")
            saveFileBinary(path, Dict("BVH" => bvh, "Ordered" => ordered, "Vertices" => model.vertices))
        end
    end
    if bvh !== nothing && args["show"]
        println("==============")
        println("BVH Structure:")
        BVH.displayBVH(bvh)
        println("==============")
    end
    BVH.describeBVH(bvh)
end

function createPrimitives(model::ModelData)
    primitives = Vector{BVH.BVHPrimitive{Float32, UInt32}}(undef, length(model.facesV))
    for idx in range(1, length(model.facesV))
        face = model.facesV[idx]
        bounds = BVH.AABB(model.vertices[face.x], model.vertices[face.y], model.vertices[face.z])
        centroid = BVH.computeCentroid(bounds)
        primitives[idx] = BVH.BVHPrimitive{Float32, UInt32}(face, bounds, centroid)
    end
    return primitives
end

main()