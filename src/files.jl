# manipulate files

using JLD2: save, load
using StaticArrays: MVector
using .AccelerateRT: Vector3, computeNormal

function loadFileText(path::String)::String
    @assert isfile(path) "[loadFileText] Failed to load $path, not a file!"
    res= ""
    open(path, "r") do io
        res = read(io, String)
    end
    return res
end

function loadFileBinary(path::String)
    @assert isfile(path) "[loadFileBinary] Failed to load $path, not a file!"
    return load(path)
end

function saveFileBinary(path::String, data)
    if ispath(path)
        println("[saveFileBinary] Warning: overwritting $(path)!")
    end
    mkpath(dirname(path))
    save(path, data)
end

function loadObjFile(path::String)
    @assert isfile(path) "[loadObjFile] Failed to load $path, not a file!"
    @assert lowercase(splitext(path)[2]) == ".obj"
    # read source
    source = split(loadFileText(path), '\n')
    # init vectors
    vertices = Vector3{Float32}[]
    normals = Vector3{Float32}[]
    facesV = Vector3{UInt32}[]
    facesN = Vector3{UInt32}[]
    # start reading
    for line in source
        line = lowercase(strip(line))
        # test empty line
        if isempty(line)
            continue
        end
        line = split(line)
        type = line[1]
        vals = line[2:end]
        # test at least 3 values
        if length(vals) < 3
            continue
        end
        # parse data based on type
        if type == "v"
            data = Vector3([parse(Float32, val) for val in vals[1:3]])
            push!(vertices, data)
        elseif type == "vn"
            data = Vector3([parse(Float32, val) for val in vals[1:3]])
            push!(normals, data)
        elseif type == "f"
            freq = length(findall("/", vals[1]))
            dataV = Vector3{UInt32}(0,0,0)
            dataN = Vector3{UInt32}(0,0,0)
            missingNormal = false
            if freq <= 1
                raw = [abs(parse(Int32, split(val, '/')[1])) for val in vals[1:3]]
                for (idx, val) in enumerate(raw)
                    dataV[idx] = val
                end
                missingNormal = true
            elseif freq == 2
                raw = [split(val, '/') for val in vals[1:3]]
                missingNormal = isempty(raw[1][3])
                for (idx, val) in enumerate(raw)
                    dataV[idx] = abs(parse(Int32, val[1]))
                    if !missingNormal
                        dataN[idx] = abs(parse(Int32, val[3]))
                    end
                end
            end
            if missingNormal
                # compute normal
                push!(normals, computeNormal(
                    vertices[dataV.x],
                    vertices[dataV.y],
                    vertices[dataV.z]
                ))
                nIdx = length(normals)
                dataN.x = nIdx
                dataN.y = nIdx
                dataN.z = nIdx
            end
            if sum(dataV) + sum(dataN) > 0
                push!(facesV, dataV)
                push!(facesN, dataN)
            end
        end
    end
    # make sure obj is not empty
    @assert !isempty(vertices) "[loadObjFile] Failed to load $path, no vertex data!"
    # make sure face is not empty
    if isempty(facesV)
        @assert mod(length(vertices), 3) == 0 "[loadObjFile] Failed to load $path, wrong number of vertices!"
        println("[loadObjFile] Warning: no face info, recomputing!")
        size = div(length(vertices), 3)
        normals = Vector{Vector3{Float32}}(undef, size)
        facesV = Vector{Vector3{UInt32}}(undef, size)
        facesN = Vector{Vector3{UInt32}}(undef, size)
        for i in range(1, length(vertices), step=3)
            idx = div(i+2, 3)
            facesV[idx] = Vector3{UInt32}(i, i+1, i+2)
            normals[idx] = computeNormal(
                vertices[i+0],
                vertices[i+1],
                vertices[i+2])
            facesN[idx] = Vector3{UInt32}(idx, idx, idx)
        end
    end
    return ModelData(path, vertices, facesV, normals, facesN)
end