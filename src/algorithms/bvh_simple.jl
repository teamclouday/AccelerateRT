# the most simple BVH

using .BVH: AABB, combineAABB!, BVHNode, BVHPrimitive
using ..AccelerateRT: ModelData, Vector3, DataType

function constructBVHSimple!(
    primitives::AbstractVector{BVHPrimitive{T, K}},
    orderedPrimitives::AbstractVector{Vector3{K}},
    idxBegin::Integer, idxEnd::Integer, criteria::Symbol
)::BVHNode where {T<:DataType, K<:DataType}
    @assert idxBegin <= idxEnd "[constructBVHSimple!] Failed to construct BVHSimple!"
    # step1: compute total bounds and centroid bounds
    boundsAll = AABB{T}()
    boundsCentroid = AABB{T}()
    for prim in primitives[idxBegin:idxEnd]
        combineAABB!(boundsAll, prim.bounds)
        combineAABB!(boundsCentroid, prim.centroid)
    end
    # step2: check if only one face left
    if idxEnd - idxBegin == 0
        # in this case, initialize as a leaf node
        primStart = length(orderedPrimitives) + 1
        for idx in idxBegin:idxEnd
            push!(orderedPrimitives, primitives[idx].face)
        end
        return BVHNode{T}(boundsAll, primStart, length(orderedPrimitives), [])
    end
    # step3: select split dimension by the maximum extent
    splitDim = argmax(boundsCentroid.pMax - boundsCentroid.pMin)
    # step4: check if split dimension extent is zero
    if boundsCentroid.pMax[splitDim] == boundsCentroid.pMin[splitDim]
        # in this case, initialize as a leaf node
        primStart = length(orderedPrimitives) + 1
        for idx in idxBegin:idxEnd
            push!(orderedPrimitives, primitives[idx].face)
        end
        return BVHNode{T}(boundsAll, primStart, length(orderedPrimitives), [])
    end
    # step5: partition faces
    mid = idxBegin
    if criteria == :median
        # find middle index
        mid = div(idxBegin + idxEnd, 2)
        # partial sort
        mapFunc = x -> x.centroid[splitDim]
        partialsort!(view(primitives, idxBegin:idxEnd), mid - idxBegin + 1; by=mapFunc)
    elseif criteria == :middle
        # compute middle value
        midVal = (boundsCentroid.pMax[splitDim] + boundsCentroid.pMin[splitDim]) * T(0.5)
        # partition primitives by middle value
        mapFunc = x -> x.centroid[splitDim] >= midVal
        sort!(view(primitives, idxBegin:idxEnd); by=mapFunc)
        # find middle index
        # mid = 0 if split failed
        mid = searchsortedlast(map(mapFunc, view(primitives, idxBegin:idxEnd)), false) + idxBegin - 1
    else
        error("[constructBVHSimple!] Failed to construct BVHSimple, unrecognized criteria $(criteria)!")
    end
    # step6: check success partition
    if mid < idxBegin
        @warn "[constructBVHSimple!] Warning: $(criteria) failed to partition nodes in ($idxBegin,$idxEnd)!"
        # if partition failed, create leaf node
        primStart = length(orderedPrimitives) + 1
        for idx in idxBegin:idxEnd
            push!(orderedPrimitives, primitives[idx].face)
        end
        return BVHNode{T}(boundsAll, primStart, length(orderedPrimitives), [])
    end
    # step7: recursion
    return BVHNode{T}(boundsAll, 0, 0, [
        constructBVHSimple!(primitives, orderedPrimitives, idxBegin, mid, criteria), # left node
        constructBVHSimple!(primitives, orderedPrimitives, mid+1, idxEnd, criteria)  # right node
    ])
end
