module OutputCollectors

# In this file, we define a helper class that will run subprocesses, collecting
# the stdout and stderr, timestamped such that we can merge the two streams
# intelligently after the fact, or keep them separate for proper analysis.
import Base: wait, merge

export OutputCollector, merge, collect_stdout, collect_stderr, tail, tee

# Make sure we don't have problems when `Base.have_color` is `nothing`.
function get_have_color()
    @static if isdefined(Base, :get_have_color)
        return Base.get_have_color()
    else
        # Compatibility with Julia v1.4-.  Layman check for coloured output on
        # older Julia versions.  TODO: remove this function when we drop support
        # for oldere versions of Julia.
        return something(Base.have_color, false)
    end
end

struct LineStream
    pipe::Pipe
    lines::Vector{Tuple{Float64,String}}
    task::Task
end

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
    LineStream(pipe::Pipe)

Given a `Pipe` that has been initialized by `spawn()`, create an async Task to
read in lines as they come in and annotate the time the line was captured for
later replay/merging with other simultaneously captured streams.
"""
function LineStream(pipe::Pipe, event::Condition)
    # We always have to close() the input half of the stream before we can
    # read() from it.  I don't know why, and this is honestly kind of annoying
    close(pipe.in)

    lines = Tuple{Float64,String}[]
    task = @async begin
        # Read lines in until we can't anymore.
        while true
            # Push this line onto our lines, then notify() the event
            line = readuntil_many(pipe, ['\n', '\r'])
            if isempty(line) && eof(pipe)
                break
            end
            push!(lines, (time(), line))
            notify(event)
        end
    end

    # Create a second task that runs after the first just to notify()
    # This ensures that anybody that's listening to the event but gated on our
    # being alive (e.g. `tee()`) can die alongside us gracefully as well.
    @async begin
        fetch(task)
        notify(event)
    end
    return LineStream(pipe, lines, task)
end

"""
    alive(s::LineStream)

Returns `true` if the task owned by this `LineStream` is still processing
output from an underlying `Pipe`.
"""
function alive(s::LineStream)
    return !(s.task.state in [:done, :failed])
end


"""
    OutputCollector

A `run()` wrapper class that captures subprocess `stdout` and `stderr` streams
independently, resynthesizing and colorizing the streams appropriately.
"""
mutable struct OutputCollector
    cmd::Base.AbstractCmd
    P::Base.AbstractPipe
    stdout_linestream::LineStream
    stderr_linestream::LineStream
    event::Condition
    tee_stream::IO
    verbose::Bool
    tail_error::Bool

    done::Bool
    extra_tasks::Vector{Task}

    function OutputCollector(cmd, P, out_ls, err_ls, event, tee_stream,
                             verbose, tail_error)
        return new(cmd, P, out_ls, err_ls, event, tee_stream, verbose,
                   tail_error, false, Task[])
    end
end

"""
    OutputCollector(cmd::AbstractCmd; verbose::Bool = false)

Run `cmd`, and collect the output such that `stdout` and `stderr` are captured
independently, but with the time of each line recorded such that they can be
stored/analyzed independently, but replayed synchronously.
"""
function OutputCollector(cmd::Base.AbstractCmd; verbose::Bool=false,
                         tail_error::Bool=true, tee_stream::IO=stdout)
    # First, launch the command
    out_pipe = Pipe()
    err_pipe = Pipe()
    P = try
        run(pipeline(cmd, stdin=devnull, stdout=out_pipe, stderr=err_pipe); wait=false)
    catch
        @warn("Could not spawn $(cmd)")
        rethrow()
    end

    # Next, start siphoning off the first couple lines of output and error
    event = Condition()
    out_ls = LineStream(out_pipe, event)
    err_ls = LineStream(err_pipe, event)

    # Finally, wrap this up in an object so that we can merge stdout and stderr
    # back together again at the end
    self = OutputCollector(cmd, P, out_ls, err_ls, event, tee_stream,
                           verbose, tail_error)

    # If we're set as verbose, then start reading ourselves out to stdout
    if verbose
        tee(self; stream = tee_stream)
    end

    return self
end

"""
    wait(collector::OutputCollector)

Wait for the command and all line streams within an [`OutputCollector`](@ref) to
finish their respective tasks and be ready for full merging.  Return the success
of the underlying process.  Prints out the last 10 lines of the process if it
does not complete successfully unless the OutputCollector was created as
`verbose`.
"""
function wait(collector::OutputCollector)
    # If we've already done this song and dance before, then don't do it again
    if !collector.done
        wait(collector.P)
        fetch(collector.stdout_linestream.task)
        fetch(collector.stderr_linestream.task)

        # Also fetch on any extra tasks we've jimmied onto the end of this guy
        for t in collector.extra_tasks
            fetch(t)
        end

        # From this point on, we are actually done!
        collector.done = true

        # If we failed, print out the tail of the output, unless we've been
        # tee()'ing it out this whole time, but only if the user said it's okay.
        if !success(collector.P) && !collector.verbose && collector.tail_error
            our_tail = tail(collector; colored=get_have_color())
            print(collector.tee_stream, our_tail)
        end
    end
    
    # Shout to the world how we've done
    return success(collector.P)
end

"""
    merge(collector::OutputCollector; colored::Bool = false)

Merge the stdout and stderr streams of the [`OutputCollector`](@ref) on a
per-line basis, returning a single string containing all collected lines,
interleaved by capture time.  If `colored` is set to true, embeds terminal color
codes to print `stderr` in red.
"""
function merge(collector::OutputCollector; colored::Bool = false)
    # First, wait for things to be done.  No incomplete mergings here yet.
    wait(collector)

    # We copy here so that you can `merge()` more than once, if you want.
    stdout_lines = copy(collector.stdout_linestream.lines)
    stderr_lines = copy(collector.stderr_linestream.lines)
    output = IOBuffer()

    # Write out an stdout line, optionally with color, and pop off that line
    function write_line(lines, should_color, color)
        if should_color && colored
            print(output, color)
        end
        t, line = popfirst!(lines)
        print(output, line)
    end

    # These help us keep track of colorizing the output
    out_color = Base.text_colors[:default]
    err_color = Base.text_colors[:red]
    last_line_stderr = false

    # Merge stdout and stderr    
    while !isempty(stdout_lines) && !isempty(stderr_lines)
        # Figure out if stdout's timestamp is earlier than stderr's
        if stdout_lines[1][1] < stderr_lines[1][1]
            write_line(stdout_lines,  last_line_stderr, out_color)
            last_line_stderr = false
        else
            write_line(stderr_lines, !last_line_stderr, err_color)
            last_line_stderr = true
        end
    end

    # Now drain whichever one still has data within it
    while !isempty(stdout_lines)
        write_line(stdout_lines, last_line_stderr, out_color)
        last_line_stderr = false
    end
    while !isempty(stderr_lines)
        write_line(stderr_lines, !last_line_stderr, err_color)
        last_line_stderr = true
    end

    # Clear text colors at the end, if we need to
    if last_line_stderr && colored
        print(output, Base.text_colors[:default])
    end

    # Return our ill-gotten goods
    return String(take!(output))
end

"""
    collect_stdout(collector::OutputCollector)

Returns all stdout lines collected by this collector so far.
"""
function collect_stdout(collector::OutputCollector)
    return join([l[2] for l in collector.stdout_linestream.lines], "")
end

"""
    collect_stderr(collector::OutputCollector)

Returns all stderr lines collected by this collector so far.
"""
function collect_stderr(collector::OutputCollector)
    return join([l[2] for l in collector.stderr_linestream.lines], "")
end

"""
    tail(collector::OutputCollector; len::Int = 100, colored::Bool = false)

Write out the last `len` lines, optionally writing colored lines.
"""
function tail(collector::OutputCollector; len::Int = 100,
              colored::Bool = false)
    out = merge(collector; colored=colored)

    idx = length(out)
    for line_idx in 1:len
        # We can run into UnicodeError's here
        try
            idx = findprev(isequal('\n'), out, idx-1)
            # We have to check for both `nothing` or `0` for Julia 0.6
            if idx === nothing || idx == 0
                idx = 0
                break
            end
        catch
            break
        end
    end

    return out[idx+1:end]
end

"""
    tee(c::OutputCollector; colored::Bool = false, stream::IO = stdout)

Spawn a background task to incrementally output lines from `collector` to the
standard output, optionally colored.
"""
function tee(c::OutputCollector; colored::Bool=get_have_color(),
             stream::IO=stdout)
    tee_task = @async begin
        out_idx = 1
        err_idx = 1
        out_lines = c.stdout_linestream.lines
        err_lines = c.stderr_linestream.lines

        # Helper function to print out the next line of stdout/stderr
        function print_next_line()
            timestr = Libc.strftime("[%T] ", time())
            # We know we have data, so figure out if it's for stdout, stderr
            # or both, and we need to choose which to print based on timestamp
            printstyled(stream, timestr; bold=true)
            if length(out_lines) >= out_idx
                if length(err_lines) >= err_idx
                    # If we've got input waiting from both lines, then output
                    # the one with the lowest capture time
                    if out_lines[out_idx][1] < err_lines[err_idx][1]
                        # Print the out line as it's older
                        print(stream, out_lines[out_idx][2])
                        out_idx += 1
                    else
                        # Print the err line as it's older
                        printstyled(stream, err_lines[err_idx][2]; color=:red)
                        print(stream)
                        err_idx += 1
                    end
                else
                    # Print the out line that is the only one waiting
                    print(stream, out_lines[out_idx][2])
                    out_idx += 1
                end
            else
                # Print the err line that is the only one waiting
                printstyled(stream, err_lines[err_idx][2]; color=:red)
                print(stream)
                err_idx += 1
            end
        end

        # First thing, wait for some input.  This avoids us trying to inspect
        # the liveliness of the linestreams before they've even started.
        wait(c.event)

        while alive(c.stdout_linestream) || alive(c.stderr_linestream)
            if length(out_lines) >= out_idx || length(err_lines) >= err_idx
                # If we have data to output, then do so
                print_next_line()
            else
                # Otherwise, wait for more input
                wait(c.event)
            end
        end

        # Drain the rest of stdout and stderr
        while length(out_lines) >= out_idx || length(err_lines) >= err_idx
            print_next_line()
        end
    end

    # Let the collector know that he might have to wait on this `tee()` to
    # finish its business as well.
    push!(c.extra_tasks, tee_task)

    return tee_task
end

end # module OutputCollectors
