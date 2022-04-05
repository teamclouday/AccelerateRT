# AccelerateRT
Explore acceleration structures for ray tracing.  
Final project for Duke University CS634: Geometric Algorithms.

------

### Setup

First make sure you have [Julia](https://julialang.org/) language installed.

Then install dependencies locally in command line:
```julia
julia> ]
(@v1.7) pkg> activate .
(AccelerateRT) pkg> instantiate
```

To execute, run:
```
julia --project=. main.jl
```

Can optionally install dependencies in `Project.toml` globally, and execute `main.jl` directly.