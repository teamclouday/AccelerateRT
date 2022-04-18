# BVH built with SAH

using .BVH: AABB, combineAABB, combineAABB!, computeOffset, computeCentroid, computeSurfaceArea, BVHNode, BVHPrimitive
using ..AccelerateRT: ModelData, Vector3, DataType

mutable struct SAHBucket
    count::Integer
    bounds::AABB
end

function constructBVHSAH!(
    primitives::AbstractVector{BVHPrimitive{T, K}},
    orderedPrimitives::AbstractVector{Vector3{K}},
    idxBegin::Integer, idxEnd::Integer
)::BVHNode where {T<:DataType, K<:DataType}
    @assert idxBegin <= idxEnd "[constructBVHSAH!] Failed to construct BVHSAH!"
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
    mid = idxBegin
    nPrims = idxEnd - idxBegin + 1
    if idxEnd - idxBegin <= 4
        # if too few primitives for SAH, do middle partition
        mid = div(idxBegin + idxEnd, 2)
        # partial sort
        mapFunc = x->x.centroid[splitDim]
        partialsort!(view(primitives, idxBegin:idxEnd), mid - idxBegin + 1; by=mapFunc)
    else
        # else do normal SAH
        nBuckets = 12
        buckets = [SAHBucket(0, AABB{T}()) for _ in 1:nBuckets]
        # step5: initialize buckets
        for idx in idxBegin:idxEnd
            b = round(Integer, nBuckets * computeOffset(boundsCentroid, primitives[idx].centroid)[splitDim])
            b = max(0, min(b, nBuckets - 1)) + 1
            buckets[b].count += 1
            combineAABB!(buckets[b].bounds, primitives[idx].bounds)
        end
        # step6: compute costs for each bucket
        costs = Vector{T}(undef, nBuckets - 1)
        for i in 1:(nBuckets-1)
            c0, c1 = 0, 0
            b0, b1 = AABB{T}(), AABB{T}()
            for j in 1:i
                combineAABB!(b0, buckets[j].bounds)
                c0 += buckets[j].count
            end
            for j in (i+1):nBuckets
                combineAABB!(b1, buckets[j].bounds)
                c1 += buckets[j].count
            end
            costs[i] = T(0.125) + (c0 * computeSurfaceArea(b0) + c1 * computeSurfaceArea(b1)) / computeSurfaceArea(boundsAll)
        end
        # step7: search bucket that minimizes SAH
        minSplitBucket = argmin(costs)
        minCost = costs[minSplitBucket]
        # step8: decide whether to create leaf or split
        if nPrims >= 256 || minCost < nPrims
            # partition by assigned bucket
            mapFunc = x -> begin
                b = round(Integer, nBuckets * computeOffset(boundsCentroid, x.centroid)[splitDim])
                b = max(0, min(b, nBuckets - 1)) + 1
                return b <= minSplitBucket
            end
            sort!(view(primitives, idxBegin:idxEnd); by=mapFunc)
            # find middle index
            mid = searchsortedlast(map(mapFunc, view(primitives, idxBegin:idxEnd)), false)
        else
            # in this case, initialize as a leaf node
            primStart = length(orderedPrimitives) + 1
            for idx in idxBegin:idxEnd
                push!(orderedPrimitives, primitives[idx].face)
            end
            return BVHNode{T}(boundsAll, primStart, length(orderedPrimitives), [])
        end
    end
    # step9: check success partition
    if mid < idxBegin
        @warn "[constructBVHSAH!] Warning: failed to partition nodes in ($idxBegin,$idxEnd)!"
        # if partition failed, create leaf node
        primStart = length(orderedPrimitives) + 1
        for idx in idxBegin:idxEnd
            push!(orderedPrimitives, primitives[idx].face)
        end
        return BVHNode{T}(boundsAll, primStart, length(orderedPrimitives), [])
    end
    # step10: recursion
    return BVHNode{T}(boundsAll, 0, 0, [
        constructBVHSAH!(primitives, orderedPrimitives, idxBegin, mid), # left node
        constructBVHSAH!(primitives, orderedPrimitives, mid+1, idxEnd)  # right node
    ])
end
