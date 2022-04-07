# construct BVH and export to binary file

using ArgParse, StaticArrays

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
        ext = ".middle.bson"
        path = bvhPath * ext
        if args["skip"] && isfile(path)
            println("Loading existing $path")
            bvh = loadFileBinary(path)
        else
            println("Constructing BVHSimple with middle criteria")
            primitives = createPrimitives(model)
            bvh = BVH.constructBVHSimple(primitives, 1, length(primitives), :middle)
        end
        if args["save"]
            println("Saving to $path")
            saveFileBinary(path, bvh)
        end
    elseif args["algMedian"]
        ext = ".median.bson"
        path = bvhPath * ext
        if args["skip"] && isfile(path)
            println("Loading existing $path")
            bvh = loadFileBinary(path)
        else
            println("Constructing BVHSimple with median criteria")
            primitives = createPrimitives(model)
            bvh = BVH.constructBVHSimple(primitives, 1, length(primitives), :median)
        end
        if args["save"]
            println("Saving to $path")
            saveFileBinary(path, bvh)
        end
    end
    if bvh !== nothing
        println("BVH Structure:")
        BVH.displayBVH(bvh)
    end
end

function createPrimitives(model::ModelData)
    primitives = BVH.BVHPrimitive{Float32, UInt32}[]
    for face in model.facesV
        bounds = BVH.AABB(model.vertices[face.x], model.vertices[face.y], model.vertices[face.z])
        centroid = BVH.computeCentroid(bounds)
        push!(primitives, BVH.BVHPrimitive{Float32, UInt32}(face, bounds, centroid))
    end
    return primitives
end

main()