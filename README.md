# AccelerateRT
Explore acceleration structures (BVHs) for ray tracing.  
Final project for Duke University CS634: Geometric Algorithms.

------

### Project Setup

First make sure you have [Julia](https://julialang.org/) language installed.  
Then install project dependencies locally from command line:
```
>> julia
               _
   _       _ _(_)_     |  Documentation: https://docs.julialang.org
  (_)     | (_) (_)    |
   _ _   _| |_  __ _   |  Type "?" for help, "]?" for Pkg help.
  | | | | | | |/ _` |  |
  | | |_| | | | (_| |  |  Version 1.7.0 (2021-11-30)
 _/ |\__'_|_|_|\__'_|  |  Official https://julialang.org/ release
|__/                   |

julia> ]
(@v1.7) pkg> activate .
(AccelerateRT) pkg> instantiate
julia> exit()
```

------

### BVH Construction

Commands

```
>> julia --project=. .\construct.jl -h
usage: construct.jl [--algMiddle] [--algMedian] [--save] [--skip]
                    [--show] [-h] model

positional arguments:
  model        obj model path

optional arguments:
  --algMiddle  construct simple BVH with middle criteria
  --algMedian  construct simple BVH with media criteria 
  --save       save constructed structure
  --skip       skip existing structure
  --show       print structure
  -h, --help   show this help message and exit
```

For example, following command constructs simple BVH with median criteria for `bunny` model.  
Saving the computed structure at the end into `structures` folder.
```
>> julia --project=. .\construct.jl .\models\bunny\bunny.obj --algMedian --save
```

------

### Visualization

Commands

```
>> julia --project=. .\visualize.jl -h
usage: visualize.jl [--bvh BVH] [-h] model

positional arguments:
  model       obj model path

optional arguments:
  --bvh BVH   constructed BVH path
  -h, --help  show this help message and exit
```

For example, following command visualizes `teapot` model in an interactive environment.
```
>> julia --project=. .\visualize.jl .\models\teapot\teapot.obj
```

The following command visualizes `bunny` model and its precomputed BVH structure.
```
>> julia --project=. .\visualize.jl .\models\bunny\bunny.obj --bvh .\structures\__models_bunny_bunny_obj.median.jld2
```

<img src="example.png" width="600" alt="bunnyBVH">

