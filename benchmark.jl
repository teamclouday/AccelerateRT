### A Pluto.jl notebook ###
# v0.19.0

using Markdown
using InteractiveUtils

# ╔═╡ 172dec87-d954-4060-85eb-3df1802ce37b
begin
	import Pkg
	Pkg.activate(".")
end

# ╔═╡ c7628a34-ffb8-4039-8c4f-c9e38b3c1d4b
using LinearAlgebra

# ╔═╡ 3bc7b47a-ee1e-4377-9dc6-4648b961d94b
using ProgressLogging

# ╔═╡ 54ec5984-7427-4734-b8b9-7e67b2b9cb38
using Plots

# ╔═╡ 991d9115-7a03-4152-904a-6f3ec0995136
using Logging

# ╔═╡ 545173b2-4d4c-4893-a17b-1b9d3bee9acb
function ingredients(path::String)
	# this is from the Julia source code (evalfile in base/loading.jl)
	# but with the modification that it returns the module instead of the last object
	name = Symbol(basename(path))
	m = Module(name)
	Core.eval(m,
        Expr(:toplevel,
             :(eval(x) = $(Expr(:core, :eval))($name, x)),
             :(include(x) = $(Expr(:top, :include))($name, x)),
             :(include(mapexpr::Function, x) = $(Expr(:top, :include))(mapexpr, $name, x)),
             :(include($path))))
	m
end

# ╔═╡ 000f910a-fd1d-47ce-ba0d-80f8a5fbf14d
ACC = ingredients("src/AccelerateRT.jl").AccelerateRT

# ╔═╡ 1d15a653-8f03-40a0-88d9-dce7f5c8de3d
BVH = ACC.BVH

# ╔═╡ a54ede51-f76e-46f5-a649-4a0cbdb97760
"Number of threads: $(Threads.nthreads())"

# ╔═╡ acf160be-a3cd-4c58-9895-25e9c1f13abe
mutable struct Camera
	pos::ACC.Vector3{Float32}
	center::ACC.Vector3{Float32}
	fov::Float32
	res::ACC.Vector2{UInt32}
end

# ╔═╡ 2880acb4-7ff8-4bf6-a2f6-84f45adffe89
mutable struct Ray
	origin::ACC.Vector3{Float32}
	dir::ACC.Vector3{Float32}
	dist::Float32
end

# ╔═╡ 89bb0d31-f2d1-4f46-a46d-2359a34ba9ef
models = ["bunny", "teapot", "sponza"]

# ╔═╡ 8c1a3646-cc41-45ce-8e21-9ba8eb151107
bvhTypes = ["middle", "median", "sah"]

# ╔═╡ 5c5a5ea2-c1b7-4f8b-8388-8155b153dd75
camera = Camera(
	ACC.Vector3{Float32}(0, 2, 3),
	ACC.Vector3(0f0),
	45.0f0,
	ACC.Vector2{UInt32}(50, 50)
)

# ╔═╡ 8716782b-d88c-4247-b89b-9cb6793c6bb0
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

# ╔═╡ 83f6f667-d39c-45b1-8929-db43191feba4
# intersection with triangle
function intersect!(
	ray::Ray, v0::ACC.Vector3,
	v1::ACC.Vector3, v2::ACC.Vector3
)::Bool
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
	ray.dist = min(ray.dist, dot(e2, qvec) * detInv)
	return true
end

# ╔═╡ 407c753a-f728-41ab-8f6c-c1dd5a173bc2
function rayTrace(
	camera::Camera, model, bvhType
)
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
	vertices, ordered, bvh = (() -> begin
		data = with_logger(NullLogger()) do
		ACC.loadFileBinary(filepath)
		end
		bvh = data["BVH"]
		ordered = data["Ordered"]
		vertices = data["Vertices"]
		return vertices, ordered, bvh
	end)()
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
			d = 2.0f0 .* (center ./ res) .- 1.0f0
			scale = Float32(tan(deg2rad(camera.fov * 0.5f0)))
			d.x *= scale
			d.y *= camRatio * scale
			dir = normalize((d.x .* camRight) .+ (d.y .* camUp) .+ camForward)
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

# ╔═╡ 772baf17-7c71-45c4-9ded-a0acaeda9186
collected = rayTrace(camera, models[1], bvhTypes[3]);

# ╔═╡ 010216eb-81ad-4709-b141-7cae1dc33228
function visualize(data, style, title)
	gr()
	m, n = size(data)
	if style == :depth
		heatmap(data', color=:greys, aspect_ratio=1, axis=nothing, title=title, xlims=(1,m), ylims=(1,n))
	elseif style == :colored
		heatmap(data', color=:thermal, aspect_ratio=1, axis=nothing, title=title, xlims=(1,m), ylims=(1,n))
	end
end

# ╔═╡ ea289b6b-1146-4b8e-b8b4-10d49f44e52e
visualize(collected[1], :depth, "bunny (SAH) depth")

# ╔═╡ 29be0939-a67a-49e4-9db1-9e7b06c7cfd2
visualize(collected[2], :colored, "bunny (SAH) tree depth")

# ╔═╡ a1ad3470-4b57-4bc6-b67f-ef954ee6555b
visualize(collected[3], :colored, "bunny (SAH) node visits")

# ╔═╡ abe581a8-2571-4989-801f-896b6d52dee2
visualize(collected[4], :colored, "bunny (SAH) leaf node visits")

# ╔═╡ Cell order:
# ╠═172dec87-d954-4060-85eb-3df1802ce37b
# ╠═545173b2-4d4c-4893-a17b-1b9d3bee9acb
# ╠═000f910a-fd1d-47ce-ba0d-80f8a5fbf14d
# ╠═1d15a653-8f03-40a0-88d9-dce7f5c8de3d
# ╠═c7628a34-ffb8-4039-8c4f-c9e38b3c1d4b
# ╠═3bc7b47a-ee1e-4377-9dc6-4648b961d94b
# ╠═54ec5984-7427-4734-b8b9-7e67b2b9cb38
# ╠═991d9115-7a03-4152-904a-6f3ec0995136
# ╠═a54ede51-f76e-46f5-a649-4a0cbdb97760
# ╠═acf160be-a3cd-4c58-9895-25e9c1f13abe
# ╠═2880acb4-7ff8-4bf6-a2f6-84f45adffe89
# ╠═89bb0d31-f2d1-4f46-a46d-2359a34ba9ef
# ╠═8c1a3646-cc41-45ce-8e21-9ba8eb151107
# ╠═5c5a5ea2-c1b7-4f8b-8388-8155b153dd75
# ╠═8716782b-d88c-4247-b89b-9cb6793c6bb0
# ╠═83f6f667-d39c-45b1-8929-db43191feba4
# ╠═407c753a-f728-41ab-8f6c-c1dd5a173bc2
# ╠═772baf17-7c71-45c4-9ded-a0acaeda9186
# ╠═010216eb-81ad-4709-b141-7cae1dc33228
# ╠═ea289b6b-1146-4b8e-b8b4-10d49f44e52e
# ╠═29be0939-a67a-49e4-9db1-9e7b06c7cfd2
# ╠═a1ad3470-4b57-4bc6-b67f-ef954ee6555b
# ╠═abe581a8-2571-4989-801f-896b6d52dee2
