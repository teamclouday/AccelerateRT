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

# ╔═╡ 81966b7b-e879-4dc1-bea6-547f06549dfe
using Random

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

# ╔═╡ 5b1c67bf-e195-4262-9129-55672d2c5944
md"""
### Structures and Constants
"""

# ╔═╡ acf160be-a3cd-4c58-9895-25e9c1f13abe
mutable struct Camera
	pos::ACC.Vector3{Float32}    	# position
	center::ACC.Vector3{Float32} 	# center to look at
	fov::Float32 					# field of view in degrees
	res::ACC.Vector2{UInt32} 		# rendered frame resolution
end

# ╔═╡ 2880acb4-7ff8-4bf6-a2f6-84f45adffe89
mutable struct Ray
	origin::ACC.Vector3{Float32} 	# original position
	dir::ACC.Vector3{Float32} 		# direction
	dist::Float32 					# distance to nearest hit
end

# ╔═╡ 89bb0d31-f2d1-4f46-a46d-2359a34ba9ef
models = ["teapot", "bunny", "dragon", "sponza"]

# ╔═╡ 8c1a3646-cc41-45ce-8e21-9ba8eb151107
bvhTypes = ["middle", "median", "sah"]

# ╔═╡ 0e4805a4-05fc-48d2-8cc8-521976b2c0ee
md"""
### Utility Functions
"""

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
	t = dot(e2, qvec) * detInv
	if t <= 0.0f0
		return false
	end
	ray.dist = min(ray.dist, t)
	return true
end

# ╔═╡ a3aa37ac-2fcf-4754-a214-76c6d97ec1d8
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

# ╔═╡ 407c753a-f728-41ab-8f6c-c1dd5a173bc2
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

# ╔═╡ 010216eb-81ad-4709-b141-7cae1dc33228
function visualize(data, style, title)
	gr()
	m, n = size(data)
	if style == :depth
		return heatmap(data', color=:greys, aspect_ratio=1, axis=nothing, border=:none, title=title, xlims=(1,m), ylims=(1,n), titlefontsize=10)
	elseif style == :colored
		return heatmap(data', color=:thermal, aspect_ratio=1, axis=nothing, border=:none, title=title, xlims=(1,m), ylims=(1,n), titlefontsize=10)
	end
end

# ╔═╡ 5304c09f-8463-427d-83ef-90eb66670c27
function visualizeAll(camera, model)
	collected = []
	for t in bvhTypes
		c = rayTrace(camera; loadInfo=(model, t))
		p1 = visualize(c[1], :depth, "$model ($t) depth")
		p2 = visualize(c[2], :colored, "$model ($t) max tree depth")
		p3 = visualize(c[3], :colored, "$model ($t) node visits")
		p4 = visualize(c[4], :colored, "$model ($t) leaf node visits")
		push!(collected, p1, p2, p3, p4)
	end
	plot(collected..., layout=(length(bvhTypes), 4), size=(1000,800), legend=false)
end

# ╔═╡ ac361e17-db7e-44e9-b290-751272967403
md"""
`sample1` implements the following algorithm:
```math
\begin{align*}
\theta&=\text{Uniform}(0, 2\pi),\\
\phi&=\text{Uniform}(0, \pi),\\
x&=\sin\phi \cdot \cos\theta,\\
y&=\sin\phi \cdot \sin\theta,\\
z&=\cos\phi.
\end{align*}
```
"""

# ╔═╡ bb2a715f-c344-4c19-97da-d0f141f016f5
function sample1(num=100, seed=0)
	@assert num > 0 "generated number should be positive!"
	@assert seed >= 0 "seed has to be non-negative!"
	rng = MersenneTwister()
	if !iszero(seed)
		Random.seed!(rng, seed)
	end
	gen = rand(rng, Float32, 2*num)
	res = zeros(Float32, num, 3)
	theta = Float32(2 * pi) .* gen[1:num]
	phi = Float32(pi) .* gen[(num+1):end]
	# z
	res[:, 3] .= cos.(phi)
	phi .= sin.(phi)
	# x
	res[:, 1] .= phi .* (cos.(theta))
	# y
	res[:, 2] .= phi .* (sin.(theta))
	return res
end

# ╔═╡ b257a75e-83e4-4ee5-9c99-2aac3193c4cb
md"""
`sample2` implements the following algorithm by Marsaglia (1972):
```math
\begin{align*}
x_1,x_2&=\text{Uniform}(-1, 1),\\
\text{Reject If }&\quad x_1^2+x_2^2\geq1,\\
x&=2x_1\sqrt{1-x_1^2-x_2^2},\\
y&=2x_2\sqrt{1-x_1^2-x_2^2},\\
z&=1-2(x_1^2+x_2^2).
\end{align*}
```
"""

# ╔═╡ 6accc136-0e4f-4933-b4e4-76e8eb648982
function sample2(num=100, seed=0)
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

# ╔═╡ 139c4824-3158-45f0-af83-0c539067749f
md"""
`sample3` implements algorithm by Cook (1957):
```math
\begin{align*}
x_0,x_1,x_2,x_3&=\text{Uniform}(-1, 1),\\
\text{Reject If }&\quad x_0^2+x_1^2+x_2^2+x_3^2\geq1,\\
x&=\frac{2(x_1x_3+x_0x_2)}{x_0^2+x_1^2+x_2^2+x_3^2},\\
y&=\frac{2(x_2x_3-x_0x_1)}{x_0^2+x_1^2+x_2^2+x_3^2},\\
z&=\frac{x_0^2+x_3^2-x_1^2-x_2^2}{x_0^2+x_1^2+x_2^2+x_3^2}.\\
\end{align*}
```
"""

# ╔═╡ 660d3f9d-6bbd-443f-9e41-fa0db116f31b
function sample3(num=100, seed=0)
	@assert num > 0 "generated number should be positive!"
	@assert seed >= 0 "seed has to be non-negative!"
	rng = MersenneTwister()
	if !iszero(seed)
		Random.seed!(rng, seed)
	end
	res = zeros(Float32, num, 3)
	x0123 = zeros(Float32, num, 4)
	x03sqr = zeros(Float32, num)
	x12sqr = zeros(Float32, num)
	x0123sqr = zeros(Float32, num)
	# generate and reject
	idx = 1
	while idx <= num
		r0, r1, r2, r3 = (rand(rng, Float32, 4) .* Float32(2) .- Float32(1))
		r03sqr = r0^2 + r3^2
		r12sqr = r1^2 + r2^2
		r0123sqr = r03sqr + r12sqr
		if r0123sqr >= Float32(1)
			continue # reject
		end
		x0123[idx, :] .= (r0,r1,r2,r3)
		x03sqr[idx] = r03sqr
		x12sqr[idx] = r12sqr
		x0123sqr[idx] = r0123sqr
		idx += 1
	end
	# x
	res[:, 1] .= Float32(2) .* (x0123[:, 2] .* x0123[:, 4] .+ x0123[:, 1] .* x0123[:, 3]) ./ x0123sqr
	# y
	res[:, 2] .= Float32(2) .* (x0123[:, 3] .* x0123[:, 4] .- x0123[:, 1] .* x0123[:, 2]) ./ x0123sqr
	# z
	res[:, 3] .= (x03sqr .- x12sqr) ./ x0123sqr
	return res
end

# ╔═╡ 0e8dcfef-adea-4183-923f-ba9201075a55
md"""
`sample4` implements a simple algorithm with Gaussian distribution:
```math
\begin{align*}
x,y,z&=\text{Normal}(),\\
\vec{v}&=\frac{1}{\sqrt{x^2+y^2+z^2}}\begin{bmatrix}
x\\y\\z
\end{bmatrix}
\end{align*}
```
"""

# ╔═╡ c055387f-cedf-4254-84a9-cb0634fb39b9
function sample4(num=100, seed=0)
	@assert num > 0 "generated number should be positive!"
	@assert seed >= 0 "seed has to be non-negative!"
	rng = MersenneTwister()
	if !iszero(seed)
		Random.seed!(rng, seed)
	end
	res = randn(rng, Float32, num, 3)
	n = norm.(eachrow(res))
	res .= res ./ n
	return res
end

# ╔═╡ 626c2387-4b2c-47f3-a536-01cdf55e3a65
function visualizeSphere(sampled)
	gr()
	plot(sampled[:, 1], sampled[:, 2], sampled[:, 3], aspect_ratio=:equal, grid=:true, seriestype=:scatter, title="size = $(size(sampled)[1])", alpha=0.4, xlim=(-1.5,1.5), ylim=(-1.5,1.5), zlim=(-1.5,1.5), label=false, titlefontsize=10)
end

# ╔═╡ c07fce63-9db6-4e11-9c51-150060d36e54
md"""
### Comparison
Compare different BVH's on teapot model
"""

# ╔═╡ f8ce933e-286f-403b-942b-f0b536ee52a1
camera = Camera(
	ACC.Vector3{Float32}(0, 3, 3),
	ACC.Vector3{Float32}(0, 0, 0),
	45.0f0,
	ACC.Vector2{UInt32}(25, 25)
)

# ╔═╡ 49e97f5c-bb86-43a9-9ce7-0992b0d40a03
visualizeAll(camera, models[1])

# ╔═╡ f4bd6b6c-9a6f-40fd-b1a0-2d92ed4de8f7
md"""
### Sampling
Test unit sphere sampling for experiment\
`https://mathworld.wolfram.com/SpherePointPicking.html` for reference
"""

# ╔═╡ 9a545956-4507-40bc-b864-800772280242
randseed = 123

# ╔═╡ bee4d132-27a1-4b32-b102-89a8b7643dc7
visualizeSphere(sample1(500, randseed))

# ╔═╡ 898fba16-0ba5-41b3-bffe-0262941cbcf1
visualizeSphere(sample2(500, randseed))

# ╔═╡ 45dce20c-8843-4ee4-a201-d5aa6035586a
visualizeSphere(sample3(500, randseed))

# ╔═╡ 836acb1e-73a5-485f-a3fa-ab7949b0c89f
visualizeSphere(sample4(500, randseed))

# ╔═╡ Cell order:
# ╟─172dec87-d954-4060-85eb-3df1802ce37b
# ╟─545173b2-4d4c-4893-a17b-1b9d3bee9acb
# ╟─000f910a-fd1d-47ce-ba0d-80f8a5fbf14d
# ╟─1d15a653-8f03-40a0-88d9-dce7f5c8de3d
# ╠═c7628a34-ffb8-4039-8c4f-c9e38b3c1d4b
# ╠═3bc7b47a-ee1e-4377-9dc6-4648b961d94b
# ╠═54ec5984-7427-4734-b8b9-7e67b2b9cb38
# ╠═991d9115-7a03-4152-904a-6f3ec0995136
# ╠═81966b7b-e879-4dc1-bea6-547f06549dfe
# ╟─a54ede51-f76e-46f5-a649-4a0cbdb97760
# ╟─5b1c67bf-e195-4262-9129-55672d2c5944
# ╠═acf160be-a3cd-4c58-9895-25e9c1f13abe
# ╠═2880acb4-7ff8-4bf6-a2f6-84f45adffe89
# ╟─89bb0d31-f2d1-4f46-a46d-2359a34ba9ef
# ╟─8c1a3646-cc41-45ce-8e21-9ba8eb151107
# ╟─0e4805a4-05fc-48d2-8cc8-521976b2c0ee
# ╟─8716782b-d88c-4247-b89b-9cb6793c6bb0
# ╟─83f6f667-d39c-45b1-8929-db43191feba4
# ╟─a3aa37ac-2fcf-4754-a214-76c6d97ec1d8
# ╟─407c753a-f728-41ab-8f6c-c1dd5a173bc2
# ╟─010216eb-81ad-4709-b141-7cae1dc33228
# ╟─5304c09f-8463-427d-83ef-90eb66670c27
# ╟─ac361e17-db7e-44e9-b290-751272967403
# ╟─bb2a715f-c344-4c19-97da-d0f141f016f5
# ╟─b257a75e-83e4-4ee5-9c99-2aac3193c4cb
# ╟─6accc136-0e4f-4933-b4e4-76e8eb648982
# ╟─139c4824-3158-45f0-af83-0c539067749f
# ╟─660d3f9d-6bbd-443f-9e41-fa0db116f31b
# ╟─0e8dcfef-adea-4183-923f-ba9201075a55
# ╟─c055387f-cedf-4254-84a9-cb0634fb39b9
# ╟─626c2387-4b2c-47f3-a536-01cdf55e3a65
# ╟─c07fce63-9db6-4e11-9c51-150060d36e54
# ╠═f8ce933e-286f-403b-942b-f0b536ee52a1
# ╠═49e97f5c-bb86-43a9-9ce7-0992b0d40a03
# ╟─f4bd6b6c-9a6f-40fd-b1a0-2d92ed4de8f7
# ╟─9a545956-4507-40bc-b864-800772280242
# ╠═bee4d132-27a1-4b32-b102-89a8b7643dc7
# ╠═898fba16-0ba5-41b3-bffe-0262941cbcf1
# ╠═45dce20c-8843-4ee4-a201-d5aa6035586a
# ╠═836acb1e-73a5-485f-a3fa-ab7949b0c89f
