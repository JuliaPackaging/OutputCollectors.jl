## OutputCollectors.jl

[![Build Status](https://travis-ci.com/JuliaPackaging/OutputCollectors.jl.svg?branch=master)](https://travis-ci.com/JuliaPackaging/OutputCollectors.jl)

[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://juliapackaging.github.io/OutputCollectors.jl/stable)
[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://juliapackaging.github.io/OutputCollectors.jl/dev)

[![Coverage Status](https://coveralls.io/repos/github/JuliaPackaging/OutputCollectors.jl/badge.svg?branch=master)](https://coveralls.io/github/JuliaPackaging/OutputCollectors.jl?branch=master)
[![codecov](https://codecov.io/gh/JuliaPackaging/OutputCollectors.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JuliaPackaging/OutputCollectors.jl)


This package lets you capture subprocess `stdout` and `stderr` streams
independently, resynthesizing and colorizing the streams appropriately.

## Installation

`OutputCollectors.jl` can be installed with [Julia built-in package
manager](https://julialang.github.io/Pkg.jl/v1/).  In a Julia session, after
entering the package manager mode with `]`, run the command

```
add OutputCollectors.jl
```

## Usage

```julia
julia> using OutputCollectors

julia> script = """
       #!/bin/sh
       echo 1
       sleep 1
       echo 2 >&2
       sleep 1
       echo 3
       sleep 1
       echo 4
       """
"#!/bin/sh\necho 1\nsleep 1\necho 2 >&2\nsleep 1\necho 3\nsleep 1\necho 4\n"

julia> oc = OutputCollector(`sh -c $script`; verbose = true);

julia> [22:42:30] 1
[22:42:31] 2
[22:42:32] 3
[22:42:33] 4
julia>

julia> merge(oc)
"1\n2\n3\n4\n"

julia> merge(oc; colored = true)
"1\n\e[31m2\n\e[39m3\n4\n"

julia> tail(oc; len = 2)
"3\n4\n"

julia> collect_stdout(oc)
"1\n3\n4\n"

julia> collect_stderr(oc)
"2\n"
```
