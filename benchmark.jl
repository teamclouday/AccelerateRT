# run benchmark and store all data

using Distributed: @everywhere, @distributed, addprocs, rmprocs, nprocs
using ArgParse

@everywhere using Logging
@everywhere using ProgressLogging
@everywhere using TerminalLoggers
@everywhere using LinearAlgebra
@everywhere using Random
@everywhere using SharedArrays

@everywhere include("./src/AccelerateRT.jl")
@everywhere using .AccelerateRT

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
            default = 100
		"--resolution"
			help = "screen resolution (in format WxH)"
			default = "50x50"
		"--distribute"
			help = "distribute tasks to multi-cores (set 0 to use all cores)"
			arg_type = Int
            default = 0
		"--skip"
			help = "whether to skip existing benchmark caches"
			action = :store_true
    end
    return parse_args(ARGS, s)
end

function main()
    args = parseCommandline()
	cpulen = length(Sys.cpu_info())
	@assert 0 <= args["distribute"] <= cpulen "Number of cores: $(args["distribute"]) not available!"
	parallel = args["distribute"] != 1
	if parallel
		@info "Distributed Mode"
		addprocs(iszero(args["distribute"]) ? cpulen - 1 : args["distribute"] - 1)
	end
	global_logger(TerminalLogger())
	@info "Number of threads available:   $(Threads.nthreads())"
	@info "Number of processes available: $(nprocs())"
	benchmark(args)
	if parallel
		rmprocs()
	end
end

function benchmark(args)
	@assert args["samples"] >= 1 "argument samples should be positive!"
	@assert args["seed"] >= 0 "argument seed should be positive!"
	@assert !isempty(args["resolution"]) "argument resolution should not be empty!"
	@info """
	# Benchmark Info
		Random Seed:         $(args["seed"])  
		Random Samples:      $(args["samples"])  
		Camera Resolution:   $(args["resolution"])  
		Skip Existing File?  $(args["skip"] ? "true" : "false")  
	"""
	sharedData = SharedArray{UInt32}([
		getResolution(args["resolution"])...,
		UInt32(args["skip"]), args["samples"],
		args["seed"]
	])
	iters = reduce(hcat, reshape(collect.(Iterators.product(1:4, 1:3)), :))
	iterIdxM = SharedArray{Int}(iters[1, :])
	iterIdxB = SharedArray{Int}(iters[2, :])
	@sync @distributed for idx in 1:length(iterIdxM)
		mIdx, bIdx = iterIdxM[idx], iterIdxB[idx]
		models = ["teapot", "bunny", "dragon", "sponza"]
		bvhTypes = ["middle", "median", "sah"]
		m, b = models[mIdx], bvhTypes[bIdx]
		modelsSetting = Dict(
			"teapot" 	=> (Vector3(0.0f0), 3.0f0, false),
			"bunny"		=> (Vector3{Float32}(0.0, 0.1, 0.1), 3.0f0, false),
			"dragon"	=> (Vector3(0.0f0), 5.0f0, false),
			"sponza"	=> (Vector3(0.0f0), 1.0f0, true)
		)
		resW, resH = sharedData[1], sharedData[2]
		skip = sharedData[3] == 1
		samples = sharedData[4]
		seed = sharedData[5]
		camera = ScreenCamera(
			Vector3(0.0f0), Vector3(0.0f0), Float32(45),
			Vector2{UInt32}(resW, resH)
		)
		filepath = getFilePath(m, b, samples, resW, resH)
		if skip && isfile(filepath)
			@info "Skipped $filepath"
			continue
		end
		@info "Now benchmark on ($m, $b)"
		data = Dict()
		setting = modelsSetting[m]
		positions = sampleSphere(samples, seed) .* setting[2]
		loaded = loadData(m, b)
		for it in 1:samples
			# set camera position
			center, pos = setting[1], (positions[it, :] .+ setting[1])
			if setting[3] # whether to revert position and center
				pos, center = center, pos
			end
			camera.pos .= pos
			camera.center .= center
			# ray trace
			sample = rayTrace(camera; loaded=loaded)
			# update data
			data[it] = sample
		end
		@info "Saving to $filepath"
		saveFileBinary(filepath, Dict("samples" => samples, "positions" => positions, "data" => data))
	end
end
@everywhere mutable struct ScreenCamera
	pos::Vector3{Float32}
	center::Vector3{Float32}
	fov::Float32
	res::Vector2{UInt32}
end
@everywhere mutable struct Ray
	origin::Vector3{Float32}
	dir::Vector3{Float32}
	dist::Float32
end

# intersection with AABB
@everywhere function intersect(ray::Ray, bounds)::Bool
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
@everywhere function intersect!(ray::Ray, v0::Vector3, v1::Vector3, v2::Vector3)::Bool
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

@everywhere function loadData(model, bvhType)
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
		loadFileBinary(filepath)
	end
	bvh = data["BVH"]
	ordered = data["Ordered"]
	vertices = data["Vertices"]
	return vertices, ordered, bvh
end

@everywhere function rayTrace(camera::ScreenCamera; loadInfo=nothing, loaded=nothing)
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
	camRight = normalize(cross(camForward, Vector3{Float32}(0,1,0)))
	camUp = normalize(cross(camRight, camForward))
	camRatio = Float32(res.x) / Float32(res.y)
	# dispatch ray for each pixel of screen
	@withprogress name="raytracing" begin
	progIter = Threads.Atomic{Int}(0)
	progCount = Integer(res.x * res.y)
	Threads.@threads for (ix, iy) in collect(Iterators.product(1:res.x, 1:res.y))
		# initialize ray
		ray = (() -> begin
			center = Vector2{Float32}(ix-1, iy-1)
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

@everywhere function sampleSphere(num=100, seed=0)
	@assert num > 0 "generated number should be positive!"
	@assert seed >= 0 "seed has to be non-negative!"
	rng = MersenneTwister()
	if !iszero(seed)
		Random.seed!(rng, seed)
	end
	res = zeros(Float32, num, 3)
	x1 = zeros(Float32, num)
	x2 = zeros(Float32, num)
	x1x2sqr = zeros(Float32, num)
	# generate and reject
	idx = 1
	while idx <= num
		m, n = (rand(rng, Float32, 2) .* Float32(2) .- Float32(1))
		m2n2 = m^2 + n^2
		if m2n2 >= Float32(1)
			continue # reject
		end
		x1[idx], x2[idx] = m, n
		x1x2sqr[idx] = m2n2
		idx += 1
	end
	# x
	res[:, 1] .= Float32(2) .* x1 .* sqrt.(Float32(1) .- x1x2sqr)
	# y
	res[:, 2] .= Float32(2) .* x2 .* sqrt.(Float32(1) .- x1x2sqr)
	# z
	res[:, 3] .= Float32(1) .- Float32(2) .* x1x2sqr
	return res
end

@everywhere function getFilePath(model, bvhType, samples, w, h)
	name = "S$(samples)_R$(w)x$(h)_$(model)_$(bvhType).jld2"
	return joinpath("caches", name)
end

function getResolution(res)
	@assert occursin(r"^[0-9]+x[0-9]+$", res) "argument resolution $res is invalid!"
	w, h = collect(eachmatch(r"[0-9]+", res))
	return Vector2{UInt32}(parse(UInt32, w.match), parse(UInt32, h.match))
end

main()