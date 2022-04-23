# BVH modifed based on binned-SAH

using .BVH: AABB, combineAABB, combineAABB!, computeOffset, computeCentroid,
    computeSurfaceArea, computeOverlap, computeVolume, BVHNode, BVHPrimitive
using ..AccelerateRT: ModelData, Vector3, DataType
using LinearAlgebra: norm

mutable struct SAHBucket
    count::Integer
    bounds::AABB
end

function constructBVHModified!(
    primitives::AbstractVector{BVHPrimitive{T, K}},
    orderedPrimitives::AbstractVector{Vector3{K}},
    idxBegin::Integer, idxEnd::Integer
)::BVHNode where {T<:DataType, K<:DataType}
    @assert idxBegin <= idxEnd "[constructBVHModified!] Failed to construct BVHSAH!"
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
        # else do modified SAH
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
            # blend between SAH and VO
            c_sah = (c0 * computeSurfaceArea(b0) + c1 * computeSurfaceArea(b1)) / computeSurfaceArea(boundsAll)
            bOverlap = computeOverlap(b0, b1)
            c_vol = min(T(1), (computeVolume(b0) + computeVolume(b1) - computeVolume(bOverlap)) / computeVolume(boundsAll))
            
            # c_vol1 = computeVolume(bOverlap) / computeVolume(boundsAll)
            c_dist = norm(computeCentroid(bOverlap) - computeCentroid(boundsAll)) / norm(boundsAll.pMax - boundsAll.pMin)
            # c_sah2 = computeSurfaceArea(bOverlap) / computeSurfaceArea(boundsAll)
            # c_sah3 = (computeSurfaceArea(b0) + computeSurfaceArea(b1)) / computeSurfaceArea(boundsAll)
            # c_vol2 = (computeVolume(b0) + computeVolume(b1)) / computeVolume(boundsAll)
            c_dist2 = (() -> begin
                center = computeCentroid(boundsAll)
                center0 = computeCentroid(b0)
                center1 = computeCentroid(b1)
                dist0 = norm(center0 - center)
                dist1 = norm(center1 - center)
                return abs(dist0 - dist1) / (dist0 + dist1)
            end)()

            # alpha = T(0.5)
            alpha = T(0.2) + T(0.1) * (c_dist + c_dist2)  # 45.35, 43.87, 52.04
            # alpha = T(0.2) + T(0.2) * c_dist2             # 45.39, 43.88, 52.12
            # alpha = T(0.8) - T(0.2) * c_dist              # 45.53, 44.03, 52.37
            costs[i] = (T(1) - alpha) * c_sah + alpha * c_vol * nPrims
        end
        # step7: search bucket that minimizes cost
        minSplitBucket = argmin(costs)
        minCost = costs[minSplitBucket]
        maxCost = nPrims
        # step8: decide whether to create leaf or split
        if nPrims >= 256 || minCost < maxCost
            # partition by assigned bucket
            mapFunc = x -> begin
                b = round(Integer, nBuckets * computeOffset(boundsCentroid, x.centroid)[splitDim])
                b = max(0, min(b, nBuckets - 1)) + 1
                return b <= minSplitBucket
            end
            sort!(view(primitives, idxBegin:idxEnd); by=mapFunc)
            # find middle index
            mid = searchsortedlast(map(mapFunc, view(primitives, idxBegin:idxEnd)), false) + idxBegin - 1
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
        @warn "[constructBVHModified!] Warning: failed to partition nodes in ($idxBegin,$idxEnd)!"
        # if partition failed, create leaf node
        primStart = length(orderedPrimitives) + 1
        for idx in idxBegin:idxEnd
            push!(orderedPrimitives, primitives[idx].face)
        end
        return BVHNode{T}(boundsAll, primStart, length(orderedPrimitives), [])
    end
    # step10: recursion
    return BVHNode{T}(boundsAll, 0, 0, [
        constructBVHModified!(primitives, orderedPrimitives, idxBegin, mid), # left node
        constructBVHModified!(primitives, orderedPrimitives, mid+1, idxEnd)  # right node
    ])
end