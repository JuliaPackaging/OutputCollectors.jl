using Documenter, OutputCollectors

makedocs(
    modules = [OutputCollectors],
    sitename = "OutputCollectors.jl",
)

deploydocs(
    repo = "github.com/JuliaPackaging/OutputCollectors.jl.git",
    push_preview = true,
    devbranch = "master",
    versions = ["v0.1" => "release-0.1", "v1" => "master", "v#.#"],
)
