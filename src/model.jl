# model data

using .AccelerateRT: Vector3

mutable struct ModelData
    filepath::String
    vertices::Vector{Vector3}
    facesV::Vector{Vector3} # a face corresponds 3 vertices
    normals::Vector{Vector3}
    facesN::Vector{Vector3} # a face corresponds 3 normals
    vertexCount
end

mutable struct ModelRenderData
    filepath::String
    vertices::Vector{Float32}
    vertexCount
end

function describeModel(data::ModelData)
    println("Model Path: $(data.filepath)")
    println("Number of Vertices: $(length(data.vertices))")
    println("Number of Normals: $(length(data.normals))")
    println("Number of Faces: $(length(data.facesV))")
end

function computeModelRenderData(data::ModelData)::ModelRenderData
    vertices = Float32[]
    for (fv, fn) in zip(data.facesV, data.facesN)
        push!(vertices, data.vertices[fv.x]...)
        push!(vertices, data.normals[fn.x]...)
        push!(vertices, data.vertices[fv.y]...)
        push!(vertices, data.normals[fn.y]...)
        push!(vertices, data.vertices[fv.z]...)
        push!(vertices, data.normals[fn.z]...)
    end
    return ModelRenderData(data.filepath, vertices, data.vertexCount)
end