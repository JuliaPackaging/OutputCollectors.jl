using OutputCollectors
using Test

# Output of a few scripts we are going to run
const simple_out = "1\n2\n3\n4\n"
const long_out = join(["$(idx)\n" for idx in 1:100], "")
const newlines_out = join(["marco$(d)polo$(d)" for d in ("\n","\r","\r\n")], "")

# Helper function to strip out color codes from strings to make it easier to
# compare output within tests that has been colorized
function strip_colorization(s)
    return replace(s, r"(\e\[\d+m)"m => "")
end

# Helper function to strip out log timestamps from strings
function strip_timestamps(s)
    return replace(s, r"^(\[\d\d:\d\d:\d\d\] )"m => "")
end

@testset "OutputCollectors.jl" begin
    @test_logs (:warn, r"Could not spawn") @test_throws Base.IOError OutputCollector(`does not exist`)

    if Sys.isunix()
        oc = OutputCollector(`echo`; verbose = true)
        @test merge(oc) == "\n"

        red = Base.text_colors[:red]
        def = Base.text_colors[:default]

        stdout_msg = "Print to stdout"
        stderr_msg = "Print to stderr"
        cmd = """
              echo $(stdout_msg)
              echo $(stderr_msg) > /dev/stderr
              """
        oc = OutputCollector(`sh -c $cmd`)
        @test merge(oc) == stdout_msg * "\n" * stderr_msg * "\n"
        @test merge(oc; colored = true) == stdout_msg * "\n" * red * stderr_msg * "\n" * def
        @test tail(oc; len = 1) == stderr_msg * "\n"
        @test tail(oc; len = 2, colored = true) == red * stderr_msg * "\n" * def
        @test collect_stdout(oc) == stdout_msg * "\n"
        @test collect_stderr(oc) == stderr_msg * "\n"

        cd("output_tests") do
            # Collect the output of `simple.sh``
            oc = OutputCollector(`sh ./simple.sh`)

            # Ensure we can wait on it and it exited properly
            @test wait(oc)

            # Ensure further waits are fast and still return 0
            let
                tstart = time()
                @test wait(oc)
                @test time() - tstart < 0.1
            end

            # Test that we can merge properly
            @test merge(oc) == simple_out

            # Test that merging twice works
            @test merge(oc) == simple_out

            # Test that `tail()` gives the same output as well
            @test tail(oc) == simple_out

            # Test that colorization works
            gt = "1\n$(red)2\n$(def)3\n4\n"
            @test merge(oc; colored=true) == gt
            @test tail(oc; colored=true) == gt

            # Test that we can grab stdout and stderr separately
            @test collect_stdout(oc) == "1\n3\n4\n"
            @test collect_stderr(oc) == "2\n"
        end

        # Next test a much longer output program
        cd("output_tests") do
            oc = OutputCollector(`sh ./long.sh`)

            # Test that it worked, we can read it, and tail() works
            @test wait(oc)
            @test merge(oc) == long_out
            @test tail(oc; len=10) == join(["$(idx)\n" for idx in 91:100], "")
        end

        # Next, test a command that fails
        cd("output_tests") do
            oc = OutputCollector(`sh ./fail.sh`)

            @test !wait(oc)
            @test merge(oc) == "1\n2\n"
        end

        # Next, test a command that kills itself (NOTE: This doesn't work on windows.  sigh.)
        @static if !Sys.iswindows()
            cd("output_tests") do
                oc = OutputCollector(`sh ./kill.sh`)

                @test !wait(oc)
                @test collect_stdout(oc) == "1\n2\n"
            end
        end

        # Next, test reading the output of a pipeline()
        grepline = pipeline(
            `sh -c 'printf "Hello\nWorld\nJulia\n"'`,
            `sh -c 'while read line; do case $line in *ul*) echo $line; esac; done'`
        )
        oc = OutputCollector(grepline)

        @test wait(oc)
        @test merge(oc) == "Julia\n"

        # Next, test that \r and \r\n are treated like \n
        cd("output_tests") do
            oc = OutputCollector(`sh ./newlines.sh`)

            @test wait(oc)
            @test collect_stdout(oc) == newlines_out
        end

        # Next, test that tee'ing to a stream works
        cd("output_tests") do
            ios = IOBuffer()
            oc = OutputCollector(`sh ./simple.sh`; tee_stream=ios, verbose=true)
            @test wait(oc)
            @test merge(oc) == simple_out

            seekstart(ios)
            tee_out = String(read(ios))
            tee_out = strip_colorization(tee_out)
            tee_out = strip_timestamps(tee_out)
            @test tee_out == simple_out
        end

        # Also test that auto-tail'ing can be can be directed to a stream
        cd("output_tests") do
            ios = IOBuffer()
            oc = OutputCollector(`sh ./fail.sh`; tee_stream=ios)

            @test !wait(oc)
            @test merge(oc) == "1\n2\n"
            seekstart(ios)
            tee_out = String(read(ios))
            tee_out = strip_colorization(tee_out)
            tee_out = strip_timestamps(tee_out)
            @test tee_out == "1\n2\n"
        end

        # Also test that auto-tail'ing can be turned off
        cd("output_tests") do
            ios = IOBuffer()
            oc = OutputCollector(`sh ./fail.sh`; tee_stream=ios, tail_error=false)

            @test !wait(oc)
            @test merge(oc) == "1\n2\n"

            seekstart(ios)
            @test String(read(ios)) == ""
        end

    end
end
