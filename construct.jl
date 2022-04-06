# construct BVH and export to binary file

using ArgParse

include("src/AccelerateRT.jl")
using .AccelerateRT

function parseCommandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
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
end

main()