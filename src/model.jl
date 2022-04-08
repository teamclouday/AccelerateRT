# model data

using .AccelerateRT: Vector3

mutable struct ModelData
    filepath::String
    vertices::Vector{Vector3}
    facesV::Vector{Vector3} # a face corresponds 3 vertices
    normals::Vector{Vector3}
    facesN::Vector{Vector3} # a face corresponds 3 normals
end

function describeModel(data::ModelData)
    println("Model Path: $(data.filepath)")
    println("Number of Vertices: $(length(data.vertices))")
    println("Number of Normals: $(length(data.normals))")
    println("Number of Faces: $(length(data.facesV))")
end