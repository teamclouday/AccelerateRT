# manipulate files

using BSON
using StaticArrays: MVector
using .AccelerateRT: Vector3, computeNormal

function loadFileText(path::String)::String
    @assert isfile(path) "Failed to load $path, not a file!"
    res= ""
    open(path, "r") do io
        res = read(io, String)
    end
    return res
end

function loadFileBinary(path::String)
    @assert isfile(path) "Failed to load $path, not a file!"

end

function loadObjFile(path::String)
    @assert isfile(path) "Failed to load $path, not a file!"
    @assert lowercase(splitext(path)[2]) == ".obj"
    # read source
    source = split(loadFileText(path), '\n')
    # init vectors
    vertices = Vector3{Float32}[]
    normals_temp = Vector3{Float32}[]
    faces_temp = []
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
            push!(normals_temp, data)
        elseif type == "f"
            freq = length(findall("/", vals[1]))
            data = MVector{6, UInt32}(0,0,0,0,0,0)
            missingNormal = false
            if freq <= 1
                raw = [abs(parse(Int32, split(val, '/')[1])) for val in vals[1:3]]
                for (idx, val) in enumerate(raw)
                    data[idx] = val
                end
                missingNormal = true
            elseif freq == 2
                raw = [split(val, '/') for val in vals[1:3]]
                missingNormal = isempty(raw[1][3])
                for (idx, val) in enumerate(raw)
                    data[idx] = abs(parse(Int32, val[1]))
                    if !missingNormal
                        data[idx+3] = abs(parse(Int32, val[3]))
                    end
                end
            end
            if missingNormal
                # compute normal
                push!(normals_temp, computeNormal(
                    vertices[data[1]],
                    vertices[data[2]],
                    vertices[data[3]]
                ))
                nIdx = length(normals_temp)
                data[4] = nIdx
                data[5] = nIdx
                data[6] = nIdx
            end
            if sum(data) > 0
                push!(faces_temp, data)
            end
        end
    end
    # make sure obj is not empty
    @assert !isempty(vertices) "Failed to load $path, no vertex data!"
    # collect faces and normals in correct order
    faces = Vector3{UInt32}[]
    normals = Vector3{Float32}[]
    if isempty(faces_temp)
        for i in range(1, step=3, stop=length(vertices))
            push!(faces, Vector3{UInt32}(i-1, i, i+1))
            n = computeNormal(
                vertices[i],
                vertices[i+1],
                vertices[i+2]
            )
            push!(normals, n, n, n)
        end
    else
        normals = Array{Vector3{Float32}, 1}(undef, length(vertices))
        for face in faces_temp
            ix, iy, iz = face[1], face[2], face[3]
            ia, ib, ic = face[4], face[5], face[6]
            push!(faces, Vector3{UInt32}(ix-1, iy-1, iz-1))
            normals[ix] = normals_temp[ia]
            normals[iy] = normals_temp[ib]
            normals[iz] = normals_temp[ic]
        end
    end
    return ModelData(path, vertices, normals, faces)
end