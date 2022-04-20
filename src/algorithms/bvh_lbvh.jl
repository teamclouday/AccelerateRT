# LBVH
# This function is not complete and not included in the module yet

using .BVH: AABB, combineAABB, combineAABB!, computeOffset, computeCentroid, computeSurfaceArea, BVHNode, BVHPrimitive
using ..AccelerateRT: ModelData, Vector3, DataType

mutable struct BVHPrimitiveMorton{K<:DataType}
    face::Vector3{K}
    code::UInt32
end

mutable struct LBVHTreelet
    start::Integer
    nPrims::Integer
    nodes::Union{BVHNode, Nothing}
end

function leftShift3(x::UInt32)::UInt32
    if x == (1 << 10)
        x -= 1
    end
    x = (x | (x << 16)) & 0b00000011000000000000000011111111
    x = (x | (x <<  8)) & 0b00000011000000001111000000001111
    x = (x | (x <<  4)) & 0b00000011000011000011000011000011
    x = (x | (x <<  2)) & 0b00001001001001001001001001001001
    return x
end

function encodeMorton(v::Vector3{T})::UInt32 where T<:DataType
    return (leftShift3(round(UInt32, abs(v.z))) << 2) |
           (leftShift3(round(UInt32, abs(v.y))) << 1) |
           (leftShift3(round(UInt32, abs(v.x))))
end

function radixSort!(v::Vector{BVHPrimitiveMorton})
    tmp = Vector{BVHPrimitiveMorton}(undef, length(v))
    bitsPerPass = 6
    nBits = 30
    nPasses = div(nBits, bitsPerPass)
    for pass = 0:(nPasses-1)
        lowBit = pass * bitsPerPass
        # set pointers
        pIn  = (pass & 1) ? tmp : v
        pOut = (pass & 1) ? v : tmp
        # count number of zero bits
        nBuckets = 1 << bitsPerPass
        bucketCount = zeros(Integer, nBuckets)
        bitMask = UInt32((1 << bitsPerPass) - 1)
        for p in pIn
            bucket = (p.code >> lowBit) & bitMask
            bucketCount[bucket + 1] += 1
        end
        # compute starting index
        outIndex = ones(Integer, nBuckets)
        for i in 2:nBuckets
            outIndex[i] = outIndex[i-1] + bucketCount[i-1]
        end
        # store sorted values
        for p in pIn
            bucket = (p.code >> lowBit) & bitMask
            pOut[outIndex[bucket]] = p
            outIndex[bucket] += 1
        end
        # swap results if necessary
        if (nPasses & 1) == 1
            v .= tmp
        end
    end
end

function emitLBVH(
    nodes::BVHNode{T},
    primitives::AbstractVector{BVHPrimitive{T, K}},
    primitivesM::AbstractVector{BVHPrimitiveMorton{K}},
    orderedPrimitives::AbstractVector{Vector3{K}},
    data::Dict, bitIndex, offset
) where {T<:DataType, K<:DataType}
    if bitIndex == -1 || data["nPrims"] <= 256
        # create leaf node
        data["total"] += 1
        bounds = AABB{T}()
        firstOffset = Threads.atomic_add!(offset, data["nPrims"])
        for i in 1:data["nPrims"]
            orderedPrimitives[firstOffset + i] = primitivesM[i].face
            combineAABB!(bounds, primitives[])
        end
    else

    end
end

function constructLBVH!(
    primitives::AbstractVector{BVHPrimitive{T, K}},
    orderedPrimitives::AbstractVector{Vector3{K}};
    parallel=true
)::BVHNode where {T<:DataType, K<:DataType}
    # check number of threads
    if parallel && Threads.nthreads() <= 1
        @warn "[constructLBVH!] Warning: parallel requested but only $(Threads.nthreads()) threads available, export JULIA_NUM_THREADS=8 before running this script!"
    end
    # step1: compute total bounds
    boundsAll = AABB{T}()
    for prim in primitives
        combineAABB!(boundsAll, prim.bounds)
    end
    # step2: compute morton indices
    mortonPrims = Vector{BVHPrimitiveMorton}(undef, length(primitives))
    computeMorton = idx -> begin
        mortonBits = 10
        mortonScale = T(1 << mortonBits)
        offset = computeOffset(boundsAll, primitives[idx].centroid)
        return BVHPrimitiveMorton(
            primitives[idx].face,
            encodeMorton(offset .* mortonScale)
        )
    end
    if parallel
        Threads.@threads for idx in 1:length(primitives)
            mortonPrims[idx] = computeMorton(idx)
        end
    else
        for idx in 1:length(primitives)
            mortonPrims[idx] = computeMorton(idx)
        end
    end
    # step3: sort by morton code
    radixSort!(mortonPrims)   
    # step4: find interval of primitives for each treelet
    treeletsToBuild = LBVHTreelet[]
    begin
        idxStart = 0
        for idxEnd in 1:length(primitives)
            mask = UInt32(0b00111111111111000000000000000000)
            if (idxEnd == length(primitives)) ||
                ((mortonPrims[idxStart+1].code & mask) !=
                 (mortonPrims[idxEnd+1].code & mask))
                nPrims = idxEnd - idxStart
                maxNodes = 2 * nPrims - 1
                push!(treeletsToBuild, LBVHTreelet(idxStart, nPrims, nothing))
                idxStart = idxEnd
            end
        end
    end
    # step5: create LBVHs
    atomicTotal = Threads.Atomic{Integer}(0)
    atomicOffset = Threads.Atomic{Integer}(0)
    lbvhBuild = idx -> begin
        nodesCreated = 0
        firstBitIndex = 29 - 12
        treelet = treeletsToBuild[idx]

    end
    if parallel

    else

    end
end
