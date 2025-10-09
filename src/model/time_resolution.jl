# Abstract resolution type interface
period_length(r::AbstractResolution) = r.period_length
time_interval(r::AbstractResolution) = r.time_interval
time_steps(r::AbstractResolution) = r.time_steps

# Uniform resolution: e.g., [1,2,3,4,5]
struct UniformResolution <: AbstractResolution
    block_length::Int
    first_steps_in_time_interval::StepRange{Int,Int}
    time_steps::UnitRange{Int}
    time_interval::Vector{UnitRange{Int}}
    period_length::Int

    function UniformResolution(block_length::Int, period_length::Int)
        @assert block_length > 0 "Block length must be positive"
        
        # Compute first steps in time interval from block_length and period_length
        first_steps_in_time_interval = 1:block_length:period_length

        # number of time steps in the interval
        time_steps = 1:length(first_steps_in_time_interval)
        
        # Calculate time intervals for each block
        time_interval = UnitRange{Int}[i:min(i+block_length-1, period_length) for i in first_steps_in_time_interval]
        
        new(block_length, first_steps_in_time_interval, time_steps, time_interval, period_length)
    end
end
# Default constructor
UniformResolution() = UniformResolution(1, 0)

# Flexible resolution: e.g., [1,3,4,6,7], where each number is the length of the block in reference timesteps
Base.@kwdef struct FlexibleResolution <: AbstractResolution
    block_lengths::Vector{Int}
    first_steps_in_time_interval::Vector{Int}
    time_steps::UnitRange{Int}
    time_interval::Vector{UnitRange{Int}}
    period_length::Int

    function FlexibleResolution(block_lengths::Vector{Int}, period_length::Int)
        @assert all(block_lengths .> 0) "All block lengths must be positive"

        first_steps_in_time_interval = cumsum([1; block_lengths[1:end-1]])
        time_steps = 1:length(block_lengths)
        
        # Calculate time intervals for each block
        time_interval = Vector{UnitRange{Int}}()
        current_time = 1
        for block_length in block_lengths
            block_end = current_time + block_length - 1
            push!(time_interval, current_time:block_end)
            current_time = block_end + 1
        end

        @assert length(time_interval) == length(time_steps) "Length of time interval and time steps must be the same"
        
        new(block_lengths, first_steps_in_time_interval, time_steps, time_interval, period_length)
    end
end

