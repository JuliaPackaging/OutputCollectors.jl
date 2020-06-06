using OutputCollectors
using Test

@testset "OutputCollectors.jl" begin
    if Sys.isunix()
        cmd = joinpath(@__DIR__, "command.sh")
        oc = OutputCollector(`$cmd`)
        @test merge(oc) == "Print to stdout\nPrint to stderr\n"
        @test merge(oc; colored = true) ==
            "Print to stdout\n" * Base.text_colors[:red] * "Print to stderr\n" * Base.text_colors[:default]
    end
end
