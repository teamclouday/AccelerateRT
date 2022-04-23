### A Pluto.jl notebook ###
# v0.19.2

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

# ╔═╡ f6e5809a-a73d-47ba-9f33-c3c442b7d37f
using Statistics

# ╔═╡ b35c68c2-146a-4cc1-8056-1607b2ac10f3
using Printf

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
bvhTypes = ["middle", "median", "sah", "sahm"]

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

# ╔═╡ 010216eb-81ad-4709-b141-7cae1dc33228
function visualize(data, style, title, margin=0Plots.mm)
	gr()
	m, n = size(data)
	if style == :depth
		return heatmap(data', color=:greys, aspect_ratio=1, axis=nothing, border=:none, title=title, xlims=(1,m), ylims=(1,n), titlefontsize=10, left_margin=margin)
	elseif style == :colored
		return heatmap(data', color=:thermal, aspect_ratio=1, axis=nothing, border=:none, title=title, xlims=(1,m), ylims=(1,n), titlefontsize=10, left_margin=margin)
	end
end

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
	plot(sampled[:, 1], sampled[:, 2], sampled[:, 3], aspect_ratio=:equal, grid=:true, seriestype=:scatter, alpha=0.4, xlim=(-1.5,1.5), ylim=(-1.5,1.5), zlim=(-1.5,1.5), label=false, titlefontsize=10)
end

# ╔═╡ c7401b1e-3485-4007-8174-51c371a4df31
function collectInfo(infoMaps)
	n = length(infoMaps)
	res = Dict()
	names = ["TreeDepth", "NodeVisits", "PrimVisits", "Score"]
	for name in names
		res[name] = Dict(
			"max" => zeros(Integer, n),
			"min" => zeros(Integer, n),
			"mean" => zeros(Float32, n),
			"std" => zeros(Float32, n)
		)
	end
	for idx in 1:n
		for nameIdx in 1:(length(names)-1)
			name = names[nameIdx]
			m = infoMaps[idx][nameIdx+1]
			res[name]["max"][idx] = maximum(m)
			res[name]["min"][idx] = minimum(m)
			res[name]["mean"][idx] = mean(m)
			res[name]["std"][idx] = std(m)
		end
		mScore = infoMaps[idx][3] .+ infoMaps[idx][4]
		res[names[end]]["max"][idx] = maximum(mScore)
		res[names[end]]["min"][idx] = minimum(mScore)
		res[names[end]]["mean"][idx] = mean(mScore)
		res[names[end]]["std"][idx] = std(mScore)
	end
	return res
end

# ╔═╡ d1460db5-485a-4376-83d3-c15ecfead9e7
function loadData(model, bvhType, samples, resolution)
	@assert isdir("caches") "Error: caches folder not found!"
	filename = "S$(samples)_R$(resolution)_$(model)_$(bvhType).jld2"
	data = ACC.loadFileBinary(joinpath("caches", filename))
	return [data["data"][idx] for idx in 1:samples]
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
	visitsNodesMap = zeros(Integer, (res.x, res.y))
	visitsPrimsMap = zeros(Integer, (res.x, res.y))
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
		visitsPrims = 0
		while !isempty(stack)
			depth, node = popfirst!(stack)
			visitsCount += 1
			maxDepth = max(maxDepth, depth)
			# test intersection with bvh bounding box
			if intersect(ray, node.bounds)
				if isempty(node.children)
					# if is leaf, test intersection with triangle
					for primIdx in node.primBegin:node.primEnd
						visitsPrims += 1
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
		visitsNodesMap[ix, iy] = visitsCount
		visitsPrimsMap[ix, iy] = visitsPrims
		# update progress bar
		Threads.atomic_add!(progIter, 1)
		@logprogress progIter[] / progCount
	end
	end
	return depthMap, treeDepthMap, visitsNodesMap, visitsPrimsMap
end

# ╔═╡ 5304c09f-8463-427d-83ef-90eb66670c27
function visualizeAll(camera, model)
	collected = []
	for bvhIdx in 1:length(bvhTypes)
		c = rayTrace(camera; loadInfo=(model, bvhTypes[bvhIdx]))
		p1 = visualize(c[1], :depth, (bvhIdx == 1 ? "PrimDepth" : ""), 15Plots.mm)
		annotate!(p1, -(camera.res[1] * 0.2), camera.res[2] * 0.5, text(bvhTypes[bvhIdx], :center, 10))
		p2 = visualize(c[2], :colored, (bvhIdx == 1 ? "TreeDepth" : ""))
		annotate!(p2, camera.res[1] * 0.5, -(camera.res[2] * 0.1), text(@sprintf("mean = %.2f", mean(c[2])), :center, 10))
		p3 = visualize(c[3], :colored, (bvhIdx == 1 ? "NodeVisits" : ""))
		annotate!(p3, camera.res[1] * 0.5, -(camera.res[2] * 0.1), text(@sprintf("mean = %.2f", mean(c[3])), :center, 10))
		p4 = visualize(c[4], :colored, (bvhIdx == 1 ? "PrimVisits" : ""))
		annotate!(p4, camera.res[1] * 0.5, -(camera.res[2] * 0.1), text(@sprintf("mean = %.2f", mean(c[4])), :center, 10))
		# score = c[3] .+ c[4]
		# p5 = visualize(score, :colored, (bvhIdx == 1 ? "Score" : ""))
		# annotate!(p5, camera.res[1] * 0.5, -(camera.res[2] * 0.1), text(@sprintf("mean = %.2f", mean(score)), :center, 10))
		push!(collected, p1, p2, p3, p4)
	end
	plot(collected..., layout=(length(bvhTypes), 4), size=(800,500), legend=false)
end

# ╔═╡ ba50cd42-47d0-48b3-b00c-bb5924c801da
function visualizeTrend(data, samples, title)
	x = 1:samples
	collected = []
	for name in ["TreeDepth", "NodeVisits", "PrimVisits", "Score"]
		p = plot(x, data[name]["max"], label="max", title=name, titlefontsize=10)
		plot!(p, x, data[name]["min"], label="min")
		plot!(p, x, data[name]["mean"], label="mean")
		plot!(p, x, data[name]["std"], label="std")
		push!(collected, p)
	end
	plot(collected..., layout=(4, 1), size=(900,500), plot_title=title)
end

# ╔═╡ 4aeef626-dfc3-435a-9448-8c9939fc1fa5
function visualizeComparison(model, samples, resolution)
	dataTypes = ["TreeDepth", "NodeVisits", "PrimVisits", "Score"]
	valTypes = ["max", "mean", "std"]
	plotData = zeros(Float32, length(valTypes), length(dataTypes), length(bvhTypes))
	for bvhIdx in 1:length(bvhTypes)
		data = collectInfo(loadData(model, bvhTypes[bvhIdx], samples, resolution))
		for (dIdx, vIdx) in Iterators.product(1:length(dataTypes), 1:length(valTypes))
			plotData[vIdx, dIdx, bvhIdx] = mean(
				data[dataTypes[dIdx]][valTypes[vIdx]]
			)
		end
	end
	collected = []
	x = 1:length(bvhTypes)
	for row in 1:length(valTypes)
		for col in 1:length(dataTypes)
			title = row == 1 ? dataTypes[col] : ""
			ylabel = col == 1 ? valTypes[row] : ""
			left_margin = col == 1 ? 10Plots.mm : 2Plots.mm
			xticks = row == length(valTypes) ? (x, bvhTypes) : nothing
			p = bar(x, plotData[row, col, :], title=title, tickfontsize=10,
				ylabel=ylabel, titlefont=10, xticks=xticks, left_margin=left_margin,
				color=cgrad(:matter, length(bvhTypes), categorical = true)[x])
			annotate!(p, x, plotData[row, col, :],
				[text(@sprintf("%.2f", val), :bottom, 10) for val in plotData[row, col, :]])
			push!(collected, p)
		end
	end
	plot(collected..., legend=nothing, size=(1250,800), layout=(length(valTypes), length(dataTypes)))
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
teapotvis = visualizeAll(camera, models[1])

# ╔═╡ fa788135-febf-4af6-aa0e-856f62a669e1
savefig(teapotvis, "figures/teapot_vis.png")

# ╔═╡ f4bd6b6c-9a6f-40fd-b1a0-2d92ed4de8f7
md"""
### Sampling
Test unit sphere sampling for experiment\
`https://mathworld.wolfram.com/SpherePointPicking.html` for reference
"""

# ╔═╡ 9a545956-4507-40bc-b864-800772280242
randseed = 123

# ╔═╡ 4e2c922c-301e-4d21-ba41-330bf5f245a0
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

# ╔═╡ bee4d132-27a1-4b32-b102-89a8b7643dc7
sample1vis = visualizeSphere(sample1(500, randseed))

# ╔═╡ ff5aabdd-d353-4a9e-a3b4-56c7a14909f6
savefig(sample1vis, "figures/sample1.png")

# ╔═╡ 5041a9a5-8ad7-44d9-97e9-9b96acf05f37
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

# ╔═╡ 898fba16-0ba5-41b3-bffe-0262941cbcf1
sample2vis = visualizeSphere(sample2(500, randseed))

# ╔═╡ 4becc0c8-f80c-4176-9d1b-74cc86c22281
savefig(sample2vis, "figures/sample2.png")

# ╔═╡ 12b4b033-12b0-494a-9461-4e967e7e0480
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

# ╔═╡ 45dce20c-8843-4ee4-a201-d5aa6035586a
sample3vis = visualizeSphere(sample3(500, randseed))

# ╔═╡ 506da3f2-3587-4d79-a68b-441340411e74
savefig(sample3vis, "figures/sample3.png")

# ╔═╡ f8bcbfd5-07c7-4dcc-a0f1-182190f46142
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

# ╔═╡ 836acb1e-73a5-485f-a3fa-ab7949b0c89f
sample4vis = visualizeSphere(sample4(500, randseed))

# ╔═╡ 1c9ec9cc-0918-4f79-ac10-9692f830ea5d
savefig(sample4vis, "figures/sample4.png")

# ╔═╡ 2ae03942-0fea-4e7b-9720-8a3486ab41b6
md"""
# Performance Metric
"""

# ╔═╡ 48be4909-7f7a-4c4b-bd26-8c639f668833
md"""
Visualization of 500 samples
"""

# ╔═╡ 71c3532f-1d4a-44de-aadc-66a33e977aa4
visualizeTrend(
	collectInfo(loadData(models[1], bvhTypes[1], 500, "100x100")),
	500, "$(models[1]) $(bvhTypes[1])")

# ╔═╡ 3faf1d5b-7998-41a1-8aff-541df4826518
visualizeTrend(
	collectInfo(loadData(models[1], bvhTypes[2], 500, "100x100")),
	500, "$(models[1]) $(bvhTypes[2])")

# ╔═╡ 4e358b8e-6e1f-4915-80e4-f25a7961fd7e
visualizeTrend(
	collectInfo(loadData(models[1], bvhTypes[3], 500, "100x100")),
	500, "$(models[1]) $(bvhTypes[3])")

# ╔═╡ 1852b0b4-0230-4c1a-b338-e7368623454f
visualizeTrend(
	collectInfo(loadData(models[1], bvhTypes[4], 500, "100x100")),
	500, "$(models[1]) $(bvhTypes[4])")

# ╔═╡ bdaad362-49a4-4ee3-acc5-dbcf0b27b116
md"""
Visualization of 1000 samples with resolution 50x50
"""

# ╔═╡ 9389f254-08b7-458b-8292-f1b1af2df455
compareVisTeapot = visualizeComparison(models[1], 1000, "50x50")

# ╔═╡ 3f085494-55dc-4435-823c-1c4cee54ac05
savefig(compareVisTeapot, "figures/compare_teapot.png")

# ╔═╡ 57bba5db-ddaa-491f-b1d3-56ef0a26d361
compareVisBunny = visualizeComparison(models[2], 1000, "50x50")

# ╔═╡ 2729d589-f28a-4dbf-a736-910df8f7837a
savefig(compareVisBunny, "figures/compare_bunny.png")

# ╔═╡ c5830da6-295e-4c84-8ebf-6e682f4f90b6
compareVisDragon = visualizeComparison(models[3], 1000, "50x50")

# ╔═╡ 23a70b54-b432-40ec-9d7b-c3b1c59bfa7a
savefig(compareVisDragon, "figures/compare_dragon.png")

# ╔═╡ c064eaab-a217-4172-a294-41c8e6cfbb2b
compareVisSponza = visualizeComparison(models[4], 1000, "50x50")

# ╔═╡ 49ebc3cf-b456-4f1a-afc8-db81b9142e88
savefig(compareVisSponza, "figures/compare_sponza.png")

# ╔═╡ 7c13cb1d-9230-40a5-a411-266a2f3d7a60
md"""
Visualization of 500 samples with resolution 100x100\
Resolution does not affect results much!
"""

# ╔═╡ 6c46a738-c1d9-467b-9d9a-93c4dcd41417
compareVisSponza100x100 = visualizeComparison(models[4], 500, "100x100")

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
# ╠═f6e5809a-a73d-47ba-9f33-c3c442b7d37f
# ╠═b35c68c2-146a-4cc1-8056-1607b2ac10f3
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
# ╟─bb2a715f-c344-4c19-97da-d0f141f016f5
# ╟─6accc136-0e4f-4933-b4e4-76e8eb648982
# ╟─660d3f9d-6bbd-443f-9e41-fa0db116f31b
# ╟─c055387f-cedf-4254-84a9-cb0634fb39b9
# ╟─626c2387-4b2c-47f3-a536-01cdf55e3a65
# ╟─c7401b1e-3485-4007-8174-51c371a4df31
# ╟─d1460db5-485a-4376-83d3-c15ecfead9e7
# ╟─ba50cd42-47d0-48b3-b00c-bb5924c801da
# ╟─4aeef626-dfc3-435a-9448-8c9939fc1fa5
# ╟─c07fce63-9db6-4e11-9c51-150060d36e54
# ╠═f8ce933e-286f-403b-942b-f0b536ee52a1
# ╟─49e97f5c-bb86-43a9-9ce7-0992b0d40a03
# ╟─fa788135-febf-4af6-aa0e-856f62a669e1
# ╟─f4bd6b6c-9a6f-40fd-b1a0-2d92ed4de8f7
# ╟─9a545956-4507-40bc-b864-800772280242
# ╟─4e2c922c-301e-4d21-ba41-330bf5f245a0
# ╟─bee4d132-27a1-4b32-b102-89a8b7643dc7
# ╟─ff5aabdd-d353-4a9e-a3b4-56c7a14909f6
# ╟─5041a9a5-8ad7-44d9-97e9-9b96acf05f37
# ╟─898fba16-0ba5-41b3-bffe-0262941cbcf1
# ╟─4becc0c8-f80c-4176-9d1b-74cc86c22281
# ╟─12b4b033-12b0-494a-9461-4e967e7e0480
# ╟─45dce20c-8843-4ee4-a201-d5aa6035586a
# ╟─506da3f2-3587-4d79-a68b-441340411e74
# ╟─f8bcbfd5-07c7-4dcc-a0f1-182190f46142
# ╟─836acb1e-73a5-485f-a3fa-ab7949b0c89f
# ╟─1c9ec9cc-0918-4f79-ac10-9692f830ea5d
# ╟─2ae03942-0fea-4e7b-9720-8a3486ab41b6
# ╟─48be4909-7f7a-4c4b-bd26-8c639f668833
# ╟─71c3532f-1d4a-44de-aadc-66a33e977aa4
# ╟─3faf1d5b-7998-41a1-8aff-541df4826518
# ╟─4e358b8e-6e1f-4915-80e4-f25a7961fd7e
# ╟─1852b0b4-0230-4c1a-b338-e7368623454f
# ╟─bdaad362-49a4-4ee3-acc5-dbcf0b27b116
# ╟─9389f254-08b7-458b-8292-f1b1af2df455
# ╟─3f085494-55dc-4435-823c-1c4cee54ac05
# ╟─57bba5db-ddaa-491f-b1d3-56ef0a26d361
# ╟─2729d589-f28a-4dbf-a736-910df8f7837a
# ╟─c5830da6-295e-4c84-8ebf-6e682f4f90b6
# ╟─23a70b54-b432-40ec-9d7b-c3b1c59bfa7a
# ╟─c064eaab-a217-4172-a294-41c8e6cfbb2b
# ╟─49ebc3cf-b456-4f1a-afc8-db81b9142e88
# ╟─7c13cb1d-9230-40a5-a411-266a2f3d7a60
# ╟─6c46a738-c1d9-467b-9d9a-93c4dcd41417
