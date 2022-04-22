# define helper structs for BVHs

using ..AccelerateRT: Vector3, DataType

# axis aligned bounding box
mutable struct AABB{T<:DataType}
    pMin::Vector3{T}
    pMax::Vector3{T}
end

Base.show(io::IO, x::AABB) = print(io, "[$(x.pMin),$(x.pMax)]")

mutable struct BVHPrimitive{T<:DataType, K<:DataType}
    face::Vector3{K} # indices for vertices
    bounds::AABB{T} # bounds
    centroid::Vector3{T} # center
end

Base.show(io::IO, x::BVHPrimitive) = print(io, "$(x.face)")

mutable struct BVHNode{T<:DataType}
    bounds::AABB{T}
    primBegin::UInt32
    primEnd::UInt32
    children::AbstractVector{BVHNode{T}}
end

mutable struct BVHNodeFlatten{T<:DataType}

end

function Base.min(v1::Vector3{T}, v2::Vector3{T})::Vector3 where T<:DataType
    return Vector3{T}(
        min(v1.x, v2.x),
        min(v1.y, v2.y),
        min(v1.z, v2.z)
    )
end

function Base.max(v1::Vector3{T}, v2::Vector3{T})::Vector3 where T<:DataType
    return Vector3{T}(
        max(v1.x, v2.x),
        max(v1.y, v2.y),
        max(v1.z, v2.z)
    )
end

function AABB{T}() where T<:DataType
    pMax = Vector3{T}(typemin(T), typemin(T), typemin(T))
    pMin = Vector3{T}(typemax(T), typemax(T), typemax(T))
    return AABB{T}(pMin, pMax)
end

function AABB(v1::Vector3{T}, v2::Vector3{T}, v3::Vector3{T}) where T<:DataType
    pMin = min(v1, min(v2, v3))
    pMax = max(v1, max(v2, v3))
    return AABB{T}(pMin, pMax)
end

function combineAABB!(bCurr::AABB{T}, bNew::AABB{T}) where T<:DataType
    bCurr.pMin .= min(bCurr.pMin, bNew.pMin)
    bCurr.pMax .= max(bCurr.pMax, bNew.pMax)
end

function combineAABB!(bCurr::AABB{T}, vNew::Vector3{T}) where T<:DataType
    bCurr.pMin .= min(bCurr.pMin, vNew)
    bCurr.pMax .= max(bCurr.pMax, vNew)
end

function combineAABB(b1::AABB{T}, b2::AABB{T})::AABB where T<:DataType
    return AABB{T}(
        min(b1.pMin, b2.pMin),
        max(b1.pMax, b2.pMax))
end

function combineAABB(b::AABB{T}, v::Vector3{T})::AABB where T<:DataType
    return AABB{T}(
        min(b.pMin, v),
        max(b.pMax, v))
end

function computeCentroid(b::AABB{T})::Vector3 where T<:DataType
    extent = b.pMin + b.pMax
    if isnan(sum(extent)) || isinf(sum(extent))
        extent .= Vector3{T}(0,0,0)
    end
    return extent * T(0.5)
end

function computeOffset(b::AABB{T}, v::Vector3{T})::Vector3 where T<:DataType
    res = v - b.pMin
    extent = b.pMax - b.pMin
    if isnan(sum(extent)) || isinf(sum(extent))
        extent .= Vector3{T}(1,1,1)
    end
    for i in 1:3
        if iszero(extent[i])
            extent[i] = T(1)
        end
    end
    res .= res ./ extent
    return res
end

function computeSurfaceArea(b::AABB{T}) where T<:DataType
    extent = b.pMax - b.pMin
    if isnan(sum(extent)) || isinf(sum(extent))
        extent .= Vector3{T}(0,0,0)
    end
    return T(2) * (extent.x * extent.y + extent.x * extent.z + extent.y * extent.z)
end

function computeVolume(b::AABB{T}) where T<:DataType
    extent = b.pMax - b.pMin
    if isnan(sum(extent)) || isinf(sum(extent))
        extent .= Vector3{T}(0,0,0)
    end
    return extent.x * extent.y * extent.z
end

function computeOverlap(b1::AABB{T}, b2::AABB{T})::AABB where T<:DataType
    res = AABB{T}()
    vMin = max(b1.pMin, b2.pMin)
    vMax = min(b1.pMax, b2.pMax)
    if any(vMin .>= vMax)
        return res
    end
    combineAABB!(res, vMin)
    combineAABB!(res, vMax)
    return res
end

function BVHPrimitive(face::Vector3{K}, vertices::AbstractVector{Vector3{T}}) where {T<:DataType, K<:DataType}
    bounds = AABB(vertices[face.x], vertices[face.y], vertices[face.z])
    return BVHPrimitive{T,K}(
        face,
        bounds,
        computeCentroid(bounds)
    )
end

function displayBVH(bvh::BVHNode, depth=1)
    prev = '~'^depth
    println("$(prev)($depth)AABB: [$(bvh.bounds.pMin),$(bvh.bounds.pMax)]; Primitives: [$(bvh.primBegin),$(bvh.primEnd)]")
    for child in bvh.children
        displayBVH(child, depth+1)
    end
end

function describeBVH(bvh::BVHNode)
    data = [0,0,typemax(Int),0] # [node count, leaf count, min depth, max depth]
    function traverse(bvh::BVHNode, depth)
        data[1] += 1
        data[4] = max(data[4], depth)
        if isempty(bvh.children)
            data[2] += 1
            data[3] = min(data[3], depth)
        else
            for child in bvh.children
                traverse(child, depth+1)
            end
        end
    end
    traverse(bvh, 1)
    println("Number of Nodes: $(data[1])")
    println("Number of Leaves: $(data[2])")
    println("Min Depth: $(data[3])")
    println("Max Depth: $(data[4])")
end
