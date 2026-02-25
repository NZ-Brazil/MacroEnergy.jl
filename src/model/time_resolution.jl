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

# Equality for UniformResolution
function Base.:(==)(a::UniformResolution, b::UniformResolution)
    return all(getproperty(a, prop) == getproperty(b, prop) for prop in propertynames(a))
end

# Hash for UniformResolution
function Base.hash(a::UniformResolution, h::UInt)
    ht = hash(UniformResolution, h)
    for prop in propertynames(a)
        ht = hash(getproperty(a, prop), ht)
    end
    return ht
end

time_interval_length(step::Int, r::UniformResolution) = r.block_length

# Flexible resolution: e.g., [1,3,4,6,7], where each number is the length of the block in reference timesteps
Base.@kwdef struct FlexibleResolution <: AbstractResolution
    block_lengths::Vector{Int}
    first_steps_in_time_interval::Vector{Int}
    time_steps::UnitRange{Int}
    time_interval::Vector{UnitRange{Int}}
    period_length::Int

    function FlexibleResolution(block_lengths::Vector{Int}, period_length::Int)
        isempty(block_lengths) && return error("Block lengths cannot be empty")
        period_length > 0 || return error("Period length must be positive")
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

# Equality for FlexibleResolution
function Base.:(==)(a::FlexibleResolution, b::FlexibleResolution)
    return all(getproperty(a, prop) == getproperty(b, prop) for prop in propertynames(a))
end

# Hash for FlexibleResolution
function Base.hash(a::FlexibleResolution, h::UInt)
    ht = hash(FlexibleResolution, h)
    for prop in propertynames(a)
        ht = hash(getproperty(a, prop), ht)
    end
    return ht
end

time_interval_length(step::Int, r::FlexibleResolution) = r.block_lengths[step]

TimeResolution(time_resolution_input::Int, period_length::Int) = UniformResolution(time_resolution_input, period_length)
TimeResolution(time_resolution_input::Vector{Int}, period_length::Int=8760) = FlexibleResolution(time_resolution_input, period_length)

"""
    find_common_time_intervals(resolutions::Union{AbstractResolution,Vector{<:AbstractResolution}}, total_timesteps::Int=8760)

This function finds time intervals that are common to all resolutions, potentially spanning multiple blocks.

# Examples
For example, if the resolutions are:
- [1,2,2,1]: flexible resolution with four blocks of length 1, 2, 2, 1
- (3): uniform resolution with length 3

Then the common time intervals are:
- [1:3, 4:6]

This is because the common time intervals are the time intervals that are common to both resolutions:
period   | 1 | 2 | 3 | 4 | 5 | 6 |
---------|---|---|---|---|---|---|
flexible | 1 |   2   |   3   | 4 |
uniform  |     1     |     2     |
---------|---|---|---|---|---|---|
common   |     1     |     2     |

And so, the common time intervals in the reference period are [1:3, 4:6].

```julia
period_length = 6
uniform_res = UniformResolution(3, period_length)
flexible_res = FlexibleResolution([1,2,2,1], period_length)
find_common_time_intervals(uniform_res, flexible_res, period_length)
# Returns [1:3, 4:6]
```
"""
function find_common_time_intervals(
    resolutions::Union{AbstractResolution,Vector{<:AbstractResolution}},
    total_timesteps::Int
)
    @assert total_timesteps > 0 "Total timesteps must be positive"
    
    # Handle single resolution case to be consistent with the interface
    if resolutions isa AbstractResolution
        resolutions = [resolutions]
    end

    # Get all block boundaries for each resolution. 
    # Note: the end of the last block could be greater than block iteself as it marks the end of the period.
    function get_time_interval_boundaries(res::AbstractResolution, total_timesteps::Int)
        boundaries = Set{Int}([1])  # Always start at 1

        if isa(res, FlexibleResolution)
            @assert total_timesteps <= sum(res.block_lengths) "Total timesteps must be less than or equal to the sum of the block lengths"
            current_time = 1
            for block_length in res.block_lengths
                effective_length = Int(block_length)
                current_time += effective_length
                if current_time <= total_timesteps + 1
                    push!(boundaries, current_time)
                end
            end
        elseif isa(res, UniformResolution)
            block_size = Int(res.block_length)
            for timestep in 1:block_size:(total_timesteps+1)
                push!(boundaries, timestep)
            end
        end

        return sort(collect(boundaries))
    end

    # Get boundaries for all resolutions
    all_boundaries = [get_time_interval_boundaries(res, total_timesteps) for res in resolutions]

    # Find common boundaries by taking the intersection of all vectors of boundaries
    common_boundaries = reduce(intersect, all_boundaries)
    push!(common_boundaries, total_timesteps + 1)  # Add end point
    sort!(common_boundaries)

    # Create common time intervals from common boundaries
    common_time_intervals = UnitRange{Int}[]
    for i in 1:(length(common_boundaries)-1)
        start_time = common_boundaries[i]
        end_time = common_boundaries[i+1] - 1
        if start_time <= total_timesteps && end_time >= start_time
            push!(common_time_intervals, start_time:end_time)
        end
    end

    return common_time_intervals
end

"""
    find_common_time_intervals(res1::AbstractResolution, res2::AbstractResolution, total_timesteps::Int)
Find common time intervals between two resolutions. This is a convenience function that calls `get_time_interval_boundaries` when just comparing two resolutions.
"""
function find_common_time_intervals(
    res1::AbstractResolution,
    res2::AbstractResolution,
    total_timesteps::Int
)
    return find_common_time_intervals([res1, res2], total_timesteps)
end

"""
    map_time_steps_to_common_time_intervals(resolution::AbstractResolution, common_time_intervals::Vector{UnitRange{Int}})

Group a single resolution time steps according to common time intervals.
Returns a vector of vectors of time steps for the resolution that overlap with each common time interval.
*Note: this function returns time steps for the resolution time intervals, not the common time intervals.

# Examples
```julia
uniform_res = UniformResolution(3, 6)
flexible_res = FlexibleResolution([1,2,2,1], 6)
common_time_intervals = find_common_time_intervals(uniform_res, flexible_res, 6)
# Map time steps to common time intervals for uniform resolution
map_time_steps_to_common_time_intervals(uniform_res, common_time_intervals)
# Returns [[1], [2]]

# Map time steps to common time intervals for flexible resolution
map_time_steps_to_common_time_intervals(flexible_res, common_time_intervals)
# Returns [[1,2], [3,4]]
```
"""
function map_time_steps_to_common_time_intervals(
    resolution::AbstractResolution,
    common_time_intervals::Vector{UnitRange{Int}}
)
    # Get resolution blocks that overlap with each common time interval
    all_time_steps_groups = Vector{Int}[]

    for common_time_interval in common_time_intervals
        # Find which resolution indices correspond to this common time interval
        time_steps_in_common_time_interval = Int[]

        if isa(resolution, FlexibleResolution)
            # For flexible resolution, map common time interval to resolution blocks
            current_time = 1
            for (block_idx, block_length) in enumerate(resolution.block_lengths)
                block_end = current_time + block_length - 1
                block_range = current_time:block_end

                # Check if this block overlaps with the common time interval
                if !isempty(intersect(block_range, common_time_interval))
                    push!(time_steps_in_common_time_interval, block_idx)
                end

                current_time = block_end + 1
            end

        elseif isa(resolution, UniformResolution)
            # For uniform resolution, map common time interval to resolution blocks
            block_size = resolution.block_length
            for time_idx in common_time_interval
                # Calculate which uniform block this time belongs to
                block_idx = div(time_idx - 1, block_size) + 1
                if block_idx <= length(resolution.time_interval) && !(block_idx in time_steps_in_common_time_interval)
                    push!(time_steps_in_common_time_interval, block_idx)
                end
            end
        end

        # Add time steps from this common time interval as a separate group
        push!(all_time_steps_groups, time_steps_in_common_time_interval)
    end

    return all_time_steps_groups
end
