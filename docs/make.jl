using Documenter, OutputCollectors

makedocs(
    modules = [OutputCollectors],
    sitename = "OutputCollectors.jl",
)

deploydocs(
    repo = "github.com/JuliaPackaging/OutputCollectors.jl.git",
    push_preview = true,
)
