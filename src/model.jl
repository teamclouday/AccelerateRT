# model data

using .AccelerateRT: Vector3

mutable struct ModelData
    filepath::String
    vertices::Vector{Vector3}
    normals::Vector{Vector3}
    faces::Vector{Vector3}
end

function describeModel(data::ModelData)
    println("Model Path: $(data.filepath)")
    println("Number of Vertices: $(length(data.vertices))")
    println("Number of Normals: $(length(data.normals))")
    println("Number of Faces: $(length(data.faces))")
end