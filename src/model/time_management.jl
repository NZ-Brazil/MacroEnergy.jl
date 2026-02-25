Base.@kwdef mutable struct TimeData <: AbstractTimeData
    resolution::AbstractResolution
    period_index::Int64 = 1
    subperiods::Vector{StepRange{Int64,Int64}} = StepRange{Int64,Int64}[]
    subperiod_indices::Vector{Int64} = Vector{Int64}()
    subperiod_weights::Dict{Int64,Float64} = Dict{Int64,Float64}()
    subperiod_map::Dict{Int64,Int64} = Dict{Int64,Int64}()
    # precomputed lookup for timestep-to-subperiod mapping
    _timestep_to_subperiod::Dict{Int64,Int64} = Dict{Int64,Int64}()
end

"""
Build lookup table for timestep-to-subperiod mapping.
Call this after subperiods are finalized.
"""
function build_timestep_lookup!(timedata::TimeData)
    empty!(timedata._timestep_to_subperiod)
    for (i, sp) in enumerate(timedata.subperiods)
        for t in sp
            timedata._timestep_to_subperiod[t] = i
        end
    end
end

######### TimeData interface #########
current_subperiod(y::Union{AbstractVertex,AbstractEdge}, t::Int64) =
    subperiod_indices(y)[findfirst(t .∈ subperiods(y))];
get_subperiod(y::Union{AbstractVertex,AbstractEdge}, w::Int64) = subperiods(y)[findfirst(subperiod_indices(y).==w)];
hours_per_timestep(y::Union{AbstractVertex,AbstractEdge}) = y.timedata.hours_per_timestep;
period_index(y::Union{AbstractVertex,AbstractEdge}) = y.timedata.period_index;
subperiods(y::Union{AbstractVertex,AbstractEdge}) = y.timedata.subperiods;
subperiod_indices(y::Union{AbstractVertex,AbstractEdge}) = y.timedata.subperiod_indices;
subperiod_weight(y::Union{AbstractVertex,AbstractEdge}, w::Int64) =
    y.timedata.subperiod_weights[w];
time_interval(y::Union{AbstractVertex,AbstractEdge}) = time_interval(y.timedata.resolution);
time_steps(y::Union{AbstractVertex,AbstractEdge}) = time_steps(y.timedata.resolution)
##Functions needed to model long duration storage:
modeled_subperiods(y::Union{AbstractVertex,AbstractEdge}) = sort(collect(keys(y.timedata.subperiod_map)))
subperiod_map(y::Union{AbstractVertex,AbstractEdge}) = y.timedata.subperiod_map;
subperiod_map(y::Union{AbstractVertex,AbstractEdge}, n::Int64) = subperiod_map(y)[n];
######### TimeData interface #########


@doc raw"""
    timestepbefore(t::Int, h::Int,subperiods::Vector{StepRange{Int64,Int64})

Determines the time step that is `h` steps before index `t` in subperiod `p` with circular indexing.

"""
function timestepbefore(t::Int, h::Int, subperiods::Vector{StepRange{Int64,Int64}})::Int
    #Find the subperiod that contains time t
    w = subperiods[findfirst(t .∈ subperiods)]
    #circular shift of the subperiod forward by h steps
    wc = circshift(w, h)

    return wc[findfirst(w .== t)]

end

@doc raw"""
    timestepbefore_fast(t::Int, h::Int, timedata::TimeData)

Optimized version using precomputed lookup table.
Requires `build_timestep_lookup!(timedata)` to be called first.
"""
function timestepbefore_fast(t::Int, h::Int, timedata::TimeData)::Int
    subperiod_idx = get(timedata._timestep_to_subperiod, t, 0)
    @assert subperiod_idx > 0 "Time $t not found in lookup table. Call build_timestep_lookup! first."
    
    target_subperiod = timedata.subperiods[subperiod_idx]
    
    # Find position of t within the subperiod
    pos_in_subperiod = t - target_subperiod.start + 1
    subperiod_length = length(target_subperiod)
    
    # Calculate the position h steps before with circular indexing
    new_pos = mod1(pos_in_subperiod - h, subperiod_length)
    
    # Convert back to absolute time index
    return target_subperiod.start + new_pos - 1
end
