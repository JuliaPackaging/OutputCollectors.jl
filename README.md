## OutputCollectors.jl

[![CI](https://github.com/JuliaPackaging/OutputCollectors.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/JuliaPackaging/OutputCollectors.jl/actions/workflows/ci.yml)

[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://juliapackaging.github.io/OutputCollectors.jl/stable)
[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://juliapackaging.github.io/OutputCollectors.jl/dev)

[![Coverage Status](https://coveralls.io/repos/github/JuliaPackaging/OutputCollectors.jl/badge.svg?branch=master)](https://coveralls.io/github/JuliaPackaging/OutputCollectors.jl?branch=master)
[![codecov](https://codecov.io/gh/JuliaPackaging/OutputCollectors.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JuliaPackaging/OutputCollectors.jl)


This package lets you capture subprocess `stdout` and `stderr` streams independently, resynthesizing and colorizing the streams appropriately.

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

julia> output = IOBuffer()
       proc, oc = collect_output(`sh -c $script`, [output, stdout])
       success(proc)

1
2
3
4

julia> wait(oc)

julia> String(take!(output))
"1\n2\n3\n4\n"
```
