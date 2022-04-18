# run benchmark and store all data

using ArgParse
using Logging
using ProgressLogging
using LinearAlgebra
using Plots
using Random

include("src/AccelerateRT.jl")
using .AccelerateRT

function parseCommandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--seed"
            help = "random seed"
            arg_type = Int
            default = 0
        "--samples"
            help = "number of random samples"
            arg_type = Int
            default = 20
    end
    return parse_args(s)
end

function main()
    args = parseCommandline()
    models = ["teapot", "bunny", "dragon", "sponza"]
    bvhTypes = ["middle", "median", "sah"]
    # set random seed
    if !iszero(args["seed"])
        Random.seed!(args["seed"])
    end
end

mutable struct Camera
	pos::Vector3{Float32}
	center::Vector3{Float32}
	fov::Float32
	res::Vector2{UInt32}
end

mutable struct Ray
	origin::Vector3{Float32}
	dir::Vector3{Float32}
	dist::Float32
end

# intersection with AABB
function intersect(ray::Ray, bounds)::Bool
	invDir = 1.0f0 ./ ray.dir
	f = (bounds.pMax .- ray.origin) .* invDir
	n = (bounds.pMin .- ray.origin) .* invDir
	tMax = max(f, n)
	tMin = min(f, n)
	t0 = max(tMin.x, tMin.y, tMin.z)
	t1 = min(tMax.x, tMax.y, tMax.z)
	return t1 >= t0
end

# intersection with triangle
function intersect!(ray::Ray, v0::ACC.Vector3, v1::ACC.Vector3, v2::ACC.Vector3)::Bool
	e1 = v1 .- v0
	e2 = v2 .- v0
	pvec = cross(ray.dir, e2)
	det = dot(e1, pvec)
	if det < 1f-6
		return false
	end
	detInv = 1.0f0 / det
	tvec = ray.origin .- v0
	u = dot(tvec, pvec) * detInv
	if u < 0.0f0 || u > 1.0f0
		return false
	end
	qvec = cross(tvec, e1)
	v = dot(ray.dir, qvec) * detInv
	if v < 0.0f0 || (v + u) > 1.0f0
		return false
	end
	t = dot(e2, qvec) * detInv
	if t <= 0.0f0
		return false
	end
	ray.dist = min(ray.dist, t)
	return true
end

function loadData(model, bvhType)
	@assert isdir("structures") "Error: structures folder not found!"
	# find path
	filepath = (() -> begin
		files = readdir("structures")
		reg = Regex("$(model)_obj.$(bvhType).jld2")
		for f in files
			if occursin(reg, f)
				# load constructed data
				path = joinpath("structures", f)
				return path
			end
		end
		return ""
	end)()
	# load structure
	@assert !isempty(filepath) "Failed to find constructure BVH with $model and $(bvhType)!"
	data = with_logger(NullLogger()) do
		ACC.loadFileBinary(filepath)
	end
	bvh = data["BVH"]
	ordered = data["Ordered"]
	vertices = data["Vertices"]
	return vertices, ordered, bvh
end

function rayTrace(
	camera::Camera; loadInfo=nothing, loaded=nothing
)
	vertices, ordered, bvh = nothing, nothing, nothing
	if loaded !== nothing
		vertices, ordered, bvh = loaded
	elseif loadInfo !== nothing
		vertices, ordered, bvh = loadData(loadInfo...)
	else
		@error "loadInfo and loaded not set!"
	end
	res = camera.res
	depthMap = zeros(Float32, (res.x, res.y))
	treeDepthMap = zeros(Integer, (res.x, res.y))
	visitsMap = zeros(Integer, (res.x, res.y))
	visitsLeafMap = zeros(Integer, (res.x, res.y))
	# compute info from camera
	camForward = normalize(camera.center - camera.pos)
	camRight = normalize(cross(camForward, ACC.Vector3{Float32}(0,1,0)))
	camUp = normalize(cross(camRight, camForward))
	camRatio = Float32(res.x) / Float32(res.y)
	# dispatch ray for each pixel of screen
	@withprogress begin
	progIter = Threads.Atomic{Int}(0)
	progCount = Integer(res.x * res.y)
	Threads.@threads for (ix, iy) in collect(Iterators.product(1:res.x, 1:res.y))
		# initialize ray
		ray = (() -> begin
			center = ACC.Vector2{Float32}(ix-1, iy-1)
			d = 2.0f0 .* ((center .+ 0.5f0) ./ res) .- 1.0f0
			scale = Float32(tan(deg2rad(camera.fov * 0.5f0)))
			d.x *= scale
			d.y *= camRatio * scale
			dir = normalize((d.x .* camRight) .+ (d.y .* camUp) .+ camForward)
			dir.x = iszero(dir.x) ? 1f-6 : dir.x
			dir.y = iszero(dir.y) ? 1f-6 : dir.y
			dir.z = iszero(dir.z) ? 1f-6 : dir.z
			return Ray(camera.pos, dir, typemax(Float32))
		end)()
		# cast into bvh
		stack = [(1, bvh)]
		maxDepth = 0
		visitsCount = 0
		visitsLeafCount = 0
		while !isempty(stack)
			depth, node = popfirst!(stack)
			visitsCount += 1
			maxDepth = max(maxDepth, depth)
			# test intersection with bvh bounding box
			if intersect(ray, node.bounds)
				if isempty(node.children)
					# if is leaf, test intersection with triangle
					visitsLeafCount += 1
					for primIdx in node.primBegin:node.primEnd
						face = ordered[primIdx]
						v0 = vertices[face.x]
						v1 = vertices[face.y]
						v2 = vertices[face.z]
						intersect!(ray, v0, v1, v2)
					end
				else
					# else pop children into stack
					for child in node.children
						push!(stack, (depth+1, child))
					end
				end
			end
		end
		# record info
		depthMap[ix, iy] = ray.dist
		treeDepthMap[ix, iy] = maxDepth
		visitsMap[ix, iy] = visitsCount
		visitsLeafMap[ix, iy] = visitsLeafCount
		# update progress bar
		Threads.atomic_add!(progIter, 1)
		@logprogress progIter[] / progCount
	end
	end
	return depthMap, treeDepthMap, visitsMap, visitsLeafMap
end

function sample(model, bvhType, count, center, reverted=false)

end

main()