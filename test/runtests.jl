using OutputCollectors
using Test

const red = Base.text_colors[:red]
const default = Base.text_colors[:default]


# Output of a few scripts we are going to run
const simple_out = "1\n2\n3\n4\n"
const simple_out_colored = "1\n$(red)2\n$(default)3\n4\n"
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
    if !Sys.isunix()
        @error("Skipping tests on non-posix platform because we naively use 'sh' in these tests")
        return
    end

    output = IOBuffer()
    output_colored = IOContext(IOBuffer(), :color => true)
    cmd, oc = collect_output(`echo`, [output])
    @test success(cmd)
    wait(oc)
    @test String(take!(output)) == "\n"

    stdout_msg = "Print to stdout"
    stderr_msg = "Print to stderr"
    cmd = """
    echo $(stdout_msg)
    sleep 1
    echo $(stderr_msg) > /dev/stderr
    """
    cmd, oc = collect_output(`sh -c $cmd`, [output, output_colored])
    @test success(cmd)
    wait(oc)
    output_str = String(take!(output))
    output_colored_str = String(take!(output_colored.io))
    @test output_str == stdout_msg * "\n" * stderr_msg * "\n"
    @test output_colored_str == stdout_msg * "\n" * red * stderr_msg * "\n" * default

    cd("output_tests") do
        # Collect the output of `simple.sh``
        cmd, oc = collect_output(`sh ./simple.sh`, [output, output_colored])
        @test success(cmd)
        wait(oc)

        # Test that we can merge properly
        @test String(take!(output)) == simple_out

        # Test that colorization works
        @test String(take!(output_colored.io)) == simple_out_colored
    end

    # Next test a much longer output program
    cd("output_tests") do
        cmd, oc = collect_output(`sh ./long.sh`, [output])
        @test success(cmd)
        wait(oc)
        @test String(take!(output)) == long_out
    end

    # Next, test a command that fails
    cd("output_tests") do
        cmd, oc = collect_output(ignorestatus(`sh ./fail.sh`), [output])
        @test !success(cmd)
        wait(oc)
        @test String(take!(output)) == "1\n2\n"
    end

    # Next, test a command that kills itself (NOTE: This doesn't work on windows.  sigh.)
    @static if !Sys.iswindows()
        cd("output_tests") do
            cmd, oc = collect_output(ignorestatus(`sh ./kill.sh`), [output])
            @test !success(cmd)
            wait(oc)
            @test String(take!(output)) == "1\n2\n"
        end
    end

    # Next, test reading the output of a pipeline()
    grepline = pipeline(
        `sh -c 'printf "Hello\nWorld\nJulia\n"'`,
        `sh -c 'while read line; do case $line in *ul*) echo $line; esac; done'`
    )
    cmd, oc = collect_output(grepline, [output])
    @test success(cmd)
    wait(oc)
    @test String(take!(output)) == "Julia\n"

    # Next, test that \r and \r\n are treated like \n
    cd("output_tests") do
        cmd, oc = collect_output(`sh ./newlines.sh`, [output])
        @test success(cmd)
        wait(oc)
        @test String(take!(output)) == newlines_out
    end
end
