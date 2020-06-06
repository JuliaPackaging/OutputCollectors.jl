using OutputCollectors
using Test

@testset "OutputCollectors.jl" begin
    @test_logs (:warn, r"Could not spawn") @test_throws Base.IOError OutputCollector(`does not exist`)

    if Sys.isunix()
        oc = OutputCollector(`echo`; verbose = true)
        @test merge(oc) == "\n"

        stdout_msg = "Print to stdout"
        stderr_msg = "Print to stderr"
        cmd = """
              echo $(stdout_msg)
              echo $(stderr_msg) > /dev/stderr
              """
        oc = OutputCollector(`bash -c $cmd`)
        @test merge(oc) == stdout_msg * "\n" * stderr_msg * "\n"
        @test merge(oc; colored = true) ==
            stdout_msg * "\n" * Base.text_colors[:red] * stderr_msg * "\n" * Base.text_colors[:default]
        @test tail(oc; len = 1) == stderr_msg * "\n"
        @test tail(oc; len = 2, colored = true) ==
            Base.text_colors[:red] * stderr_msg * "\n" * Base.text_colors[:default]
        @test collect_stdout(oc) == stdout_msg * "\n"
        @test collect_stderr(oc) == stderr_msg * "\n"
    end
end
