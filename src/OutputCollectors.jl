module OutputCollectors
using StyledStrings

export OutputCollector, collect_output

"""
    readuntil_many(s::IO, delims)

Given a collection of delimiter characters, read from `s` until one of those
delimiters is reached, or we reach the end of `s`.
"""
function readuntil_many(s::IO, delims)
    out = IOBuffer()
    while !eof(s)
        c = read(s, Char)
        write(out, c)
        if c in delims
            break
        end
    end
    return String(take!(out))
end

"""
    OutputCollector

"""
struct OutputCollector
    pipes::Dict{String,<:Base.AbstractPipe}
    outputs::Vector{<:IO}
    styles::Dict{String,Symbol}
    line_tasks::Vector{Task}
    closer_task::Task
    merging_task::Task
end

function OutputCollector(pipes::Dict{String,<:Base.AbstractPipe},
                         outputs::Vector{<:IO},
                         styles::Dict{String,Symbol} = Dict{String,Symbol}())
    for name in keys(styles)
        if name ∉ keys(pipes)
            throw(ArgumentError("Cannot provide styling for pipe '$(name)' that does not exist in `pipes`!"))
        end
    end

    # Make sure all streams have a style, even if it just defaults to `default`.
    styles = Dict(name => get(styles, name, :default) for name in keys(pipes))
    pipe_names = collect(keys(pipes))

    # This is the communication channel that each per-stream task will use to
    # send us the lines coming from each stream
    lines_channel = Channel{Tuple{Int,String}}(2048)

    # Launch a task per-stream to collate lines and send them down the channel:
    line_tasks = Task[]
    for (name, pipe) in pipes
        name_idx = findfirst(==(name), pipe_names)
        push!(line_tasks, Threads.@spawn begin
            # This is really annoying; we can end up trying to read from a `Pipe` object
            # before it's been properly initialized by `run(::Cmd)`, which throws a fatal
            # error.  Why?!  There's not even a way to wait upon the pipe getting properly
            # initialized, so we are forced to fall back to polling like a plebian.
            # Luckily, this shouldn't take too long as we usually create this pipe just
            # before we run the command.
            while pipe.out.status ∈ (Base.StatusUninit, Base.StatusInit)
                sleep(0.00001)
            end

            # We always have to close() the input half of the stream before we can read() from it.
            close(pipe.in)

            # Read lines in until we can't anymore.
            while true
                # Push this line onto our `lines`, and identify which stream it came from
                line = readuntil_many(pipe, ['\n', '\r'])
                if isempty(line) && eof(pipe)
                    break
                end
                put!(lines_channel, (name_idx, line))
            end
        end)
    end

    # Launch a task that waits for all tasks within `line_tasks` to finish, then closes the channel.
    closer_task = Threads.@spawn begin
        for task in line_tasks
            wait(task)
        end
        close(lines_channel)
    end

    merging_task = Threads.@spawn begin
        # Receive the next line from our `lines_channel`:
        for (name_idx, line) in lines_channel
            # Style it
            styled_line = styled"{$(styles[pipe_names[name_idx]]):$(line)}"

            # Write it out to all of our outputs
            for output in outputs
                print(output, styled_line)
            end
        end
    end

    return OutputCollector(pipes, outputs, styles, line_tasks, closer_task, merging_task)
end

function Base.wait(collector::OutputCollector)
    wait.(collector.line_tasks)
    wait(collector.closer_task)
    wait(collector.merging_task)
end

# Convenience method to wrap a `Cmd` in a pipeline that will feed to an OutputCollector
function collect_output(cmd::Base.AbstractCmd, outputs::Vector{<:IO}; stdout_style::Symbol = :default, stderr_style::Symbol = :red)
    stdout_pipe = Pipe()
    stderr_pipe = Pipe()
    pipes = Dict("stdout" => stdout_pipe, "stderr" => stderr_pipe)
    styles = Dict("stdout" => stdout_style, "stderr" => stderr_style)
    oc = OutputCollector(pipes, outputs, styles)
    return pipeline(cmd; stdout=stdout_pipe, stderr=stderr_pipe), oc
end

end # module OutputCollectors
