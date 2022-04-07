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
    prim::AbstractVector{BVHPrimitive}
    children::AbstractVector{BVHNode{T}}
end

mutable struct BVHNodeFlatten{T<:DataType}

end

function AABB{T}() where T<:DataType
    pMax = Vector3{T}(typemin(T), typemin(T), typemin(T))
    pMin = Vector3{T}(typemax(T), typemax(T), typemax(T))
    return AABB{T}(pMin, pMax)
end

function AABB(v1::Vector3{T}, v2::Vector3{T}, v3::Vector3{T}) where T<:DataType
    pMin = min(v1, v2, v3)
    pMax = max(v1, v2, v3)
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
        extent = Vector3{T}(0,0,0)
    end
    return extent * T(0.5)
end

function BVHPrimitive(face::Vector3{K}, vertices::AbstractVector{Vector3{T}}) where {T<:DataType, K<:DataType}
    bounds = AABB(vertices[face.x], vertices[face.y], vertices[face.z])
    return BVHPrimitive{T,K}(
        face,
        bounds,
        computeCentroid(bounds)
    )
end

function displayBVH(bvh::BVHNode, depth=0)
    prev = '~'^depth
    print("$(prev)($depth)AABB: [$(bvh.bounds.pMin),$(bvh.bounds.pMax)]; Primitives: [ ")
    for p in bvh.prim
        print(p, " ")
    end
    println("]")
    for child in bvh.children
        displayBVH(child, depth+1)
    end
end