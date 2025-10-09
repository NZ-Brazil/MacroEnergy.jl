function load_time_data(
    data::AbstractDict{Symbol,Any},
    commodities::Dict{Symbol,DataType},
    rel_path::AbstractString
)
    period_index = get(data, :SystemIndex, 1)
    if haskey(data, :path)
        path = rel_or_abs_path(data[:path], rel_path)
        return load_time_data(path, commodities, rel_path, period_index)
    else
        return load_time_data(data, commodities)
    end
end

function load_time_data(
    path::AbstractString,
    commodities::Dict{Symbol,DataType},
    rel_path::AbstractString,
    period_index::Int = 1
)
    path = rel_or_abs_path(path, rel_path)
    if isdir(path)
        path = joinpath(path, "time_data.json")
    end
    # read in the list of commodities from the data directory
    isfile(path) || error("Time data not found at $(abspath(path))")

    # Before reading the time data into the macro data structures
    # we make sure that the period map is loaded
    time_data = copy(JSON3.read(path))
    haskey(time_data, :SubPeriodMap) && load_subperiod_map!(time_data, rel_path)
    validate_and_set_default_total_hours_modeled!(time_data::AbstractDict{Symbol,Any})
    time_data[:SystemIndex] = period_index
    return load_time_data(time_data, commodities)
end

function load_time_data(
    time_data::AbstractDict{Symbol,Any},
    commodities::Dict{Symbol,DataType}
)
    # validate the time data
    validate_time_data(time_data, commodities)

    # create the time data object
    return create_time_data(time_data, commodities)
end

function load_subperiod_map!(
    time_data::AbstractDict{Symbol,Any},
    rel_path::AbstractString
)
    subperiod_map_data = time_data[:SubPeriodMap]
    # if the period map is file path, load it
    if haskey(subperiod_map_data, :path)
        path = rel_or_abs_path(subperiod_map_data[:path], rel_path)
        subperiod_map_data = load_subperiod_map(path)
    end
    validate_subperiod_map(subperiod_map_data)
    time_data[:SubPeriodMap] = subperiod_map_data
end

function load_subperiod_map(path::AbstractString)
    isfile(path) || error("Period map file not found at $(abspath(path))")
    return load_csv(path)
end

function validate_subperiod_map(subperiod_map_data::DataFrame)
    @assert names(subperiod_map_data) == ["Period_Index", "Rep_Period", "Rep_Period_Index"]
    @assert typeof(subperiod_map_data[!, :Period_Index]) == Vector{Union{Missing, Int}}
    @assert typeof(subperiod_map_data[!, :Rep_Period]) == Vector{Union{Missing, Int}}
    @assert typeof(subperiod_map_data[!, :Rep_Period_Index]) == Vector{Union{Missing, Int}}
end

function validate_and_set_default_total_hours_modeled!(time_data::AbstractDict{Symbol,Any})
    # Check if TotalTimeStepsModeled exists and is an integer
    if haskey(time_data, :TotalTimeStepsModeled)
        if !isa(time_data[:TotalTimeStepsModeled], Integer)
            throw(ArgumentError("TotalTimeStepsModeled must be an integer, got $(typeof(time_data[:TotalTimeStepsModeled]))"))
        end
    # If TotalTimeStepsModeled does not exist, use default value of 8760 (hours per year)
    else
        @warn("TotalTimeStepsModeled not found in time_data.json - Using 8760 as default value for TotalTimeStepsModeled")
        time_data[:TotalTimeStepsModeled] = 8760
    end
end

function validate_time_data(
    time_data::AbstractDict{Symbol,Any},
    case_commodities::Dict{Symbol,DataType}
)
    # Check that the time data has the correct fields
    @assert haskey(time_data, :NumberOfSubperiods)
    @assert haskey(time_data, :TimeResolution)
    @assert haskey(time_data, :TimeStepsPerSubperiod)
    # Check that the time data has the correct values    
    @assert time_data[:NumberOfSubperiods] > 0
    # Check that the TimeStepsPerSubperiod is positive
    @assert time_data[:TimeStepsPerSubperiod] > 0
    # validate period map
    haskey(time_data, :SubPeriodMap) && validate_subperiod_map(time_data[:SubPeriodMap])
    # validate time resolution
    validate_time_resolution(time_data[:TimeResolution], time_data[:TimeStepsPerSubperiod])
    # Check that the time data has the correct commodities
    @assert keys(time_data[:TimeResolution]) <= keys(case_commodities)
    macro_commodities = commodity_types(MacroEnergy) # Get the available commodities
    validate_commodities(keys(time_data[:TimeResolution]), macro_commodities)
end

function validate_time_resolution(time_resolution::Dict{Symbol,Any}, time_steps_per_subperiod::Int)

    for resolution in values(time_resolution)
        if isa(resolution, Vector)
            @assert all(resolution .> 0) "All TimeResolution values must be positive, got $resolution"
            is_valid = can_span_subperiods(resolution, time_steps_per_subperiod)
            if !is_valid
                msg = "Time resolution $resolution is not compatible with the number of time steps per subperiod $time_steps_per_subperiod.\n"
                msg *= "Hint: Please check the time data input and ensure that the `TimeResolution` blocks can span the subperiods with length $time_steps_per_subperiod."
                error(msg)
            end
        else
            @assert resolution > 0 "TimeResolution value must be positive, got $resolution"
            is_valid = mod(time_steps_per_subperiod, resolution) == 0
            if !is_valid
                msg = "Time resolution $resolution is not compatible with the number of time steps per subperiod $time_steps_per_subperiod.\n"
                msg *= "Hint: Please check the time data input and ensure that the `TimeResolution` are a multiple of `TimeStepsPerSubperiod`."
                error(msg)
            end
        end
    end
end

function can_span_subperiods(block_lengths::Vector{Int}, target::Int)
    remaining_blocks = copy(block_lengths)
    
    while !isempty(remaining_blocks)
        
        current_sum = 0
        i = 1
        # Try to form a complete subperiod starting from the first remaining block
        while i <= length(remaining_blocks) && current_sum < target
            current_sum += remaining_blocks[i]
            i += 1
        end
        
        if current_sum == target
            # If we found exactly the right sum, remove those blocks and continue
            deleteat!(remaining_blocks, 1:(i-1))
        else
            # If we can't form a complete subperiod with consecutive blocks, fail immediately
            return false
        end
    end
    
    return true
end

function create_time_data(
    time_data::AbstractDict{Symbol,Any},
    commodities::Dict{Symbol,DataType}
)
    all_timedata = Dict{Symbol,TimeData}()
    time_data_keys = keys(time_data[:TimeResolution])
    for (sym, type) in commodities
        if sym in time_data_keys
            all_timedata[sym] = create_commodity_timedata(sym, type, time_data)
        else
            # Check if sym is any of supertypes(type), and if so load the time data from there
            for supertype in supertypes(type)
                if Symbol(supertype) in time_data_keys
                    @debug "Using time data from $(supertype) for $(sym)"
                    all_timedata[sym] = create_commodity_timedata(Symbol(supertype), type, time_data)
                    break
                end
            end
        end
    end
    return all_timedata
end

function create_commodity_timedata(
    sym::Symbol,
    type::DataType,
    time_data::AbstractDict{Symbol,Any}
)
    number_of_subperiods = time_data[:NumberOfSubperiods];

    timesteps_per_subperiod = time_data[:TimeStepsPerSubperiod]

    total_timesteps_modeled = time_data[:TotalTimeStepsModeled]

    period_length = number_of_subperiods * timesteps_per_subperiod;

    timestep_resolution = get_resolution(time_data[:TimeResolution][sym], time_data[:ReferenceClock], period_length)

    validate_temporal_resolution(period_length, timestep_resolution)

    subperiods = create_subperiods(time_data, timestep_resolution)

    subperiod_map  = get_timedata_subperiod_map(time_data)

    unique_rep_periods = get_unique_rep_periods(subperiod_map)

    weights = get_weights(subperiod_map, unique_rep_periods, timesteps_per_subperiod, total_timesteps_modeled)

    return TimeData(;
        resolution = timestep_resolution,
        period_index = get(time_data, :SystemIndex, 1),
        subperiods = subperiods,
        subperiod_indices = unique_rep_periods,
        subperiod_weights = Dict(unique_rep_periods .=> weights),
        subperiod_map = subperiod_map
    )
end

function get_resolution(time_resolution_input::Union{Int, Vector{Int}}, reference_timestep::Real=1, period_length::Int=8760)
    reference_timestep !== 1 && @error "Reference timestep is not 1, this is not supported yet"
    TimeResolution(time_resolution_input, period_length)
end

function validate_temporal_resolution(period_length::Int, timestep_resolution::AbstractResolution)
    if isa(timestep_resolution, FlexibleResolution) && sum(timestep_resolution.block_lengths) != period_length
        msg = "Period length does not match the sum of the block lengths in the flexible resolution \n"
        msg *= "Period length: $period_length, sum of block lengths: $(sum(timestep_resolution.block_lengths)) \n"
        msg *= "Flexible resolution: $(timestep_resolution) \n"
        msg *= "Please check the time data input and ensure that the `TimeResolution` and `TimeStepsPerSubperiod` are consistent with the `NumberOfSubperiods`"
        error(msg)
    end
end

"""
    create_subperiods(time_data::AbstractDict{Symbol,Any}, resolution::UniformResolution)

Convert reference time subperiods to model timesteps for uniform resolution.

# Example
If TimeStepsPerSubperiod = 168 reference hours, block_length = 24 hours/timestep,
and NumberOfSubperiods = 52, this creates 52 subperiods of 7 model timesteps each.

# Returns
Vector{UnitRange{Int}}: Each subperiod as a range of model timesteps (e.g., [1:7, 8:14, ...])
"""
function create_subperiods(time_data::AbstractDict{Symbol,Any}, resolution::UniformResolution)
    number_of_subperiods = time_data[:NumberOfSubperiods]
    reference_timesteps_per_subperiod = time_data[:TimeStepsPerSubperiod]
    block_length = resolution.block_length
    
    # Validate subperiod length
    if !iszero(reference_timesteps_per_subperiod % block_length)
        error("TimeStepsPerSubperiod ($reference_timesteps_per_subperiod) is not divisible by " *
              "block_length ($block_length). Please ensure subperiod length aligns with time resolution.")
    end
    
    # Convert to resolution timesteps
    resolution_timesteps_per_subperiod = div(reference_timesteps_per_subperiod, block_length)
    total_resolution_timesteps = number_of_subperiods * resolution_timesteps_per_subperiod
    
    # Partition resolution timesteps into subperiods
    resolution_time_range = 1:total_resolution_timesteps
    return collect(Iterators.partition(resolution_time_range, resolution_timesteps_per_subperiod))
end

"""
    create_subperiods(time_data::AbstractDict{Symbol,Any}, resolution::FlexibleResolution)

Convert reference time subperiods to model timesteps for flexible resolution.

Maps each reference subperiod to the model blocks (with variable lengths) that fall within it.

# Example
If TimeStepsPerSubperiod = 168 reference hours, and block_lengths = [24, 24, 24, 24, 48, 24],
the first subperiod might span model blocks 1:6.

# Returns
Vector{UnitRange{Int}}: Each subperiod as a range of model block indices
"""
function create_subperiods(time_data::AbstractDict{Symbol,Any}, resolution::FlexibleResolution)
    number_of_subperiods = time_data[:NumberOfSubperiods]
    reference_timesteps_per_subperiod = time_data[:TimeStepsPerSubperiod]
    
    # Create reference time subperiods (in reference timesteps, e.g., hours)
    total_reference_timesteps = number_of_subperiods * reference_timesteps_per_subperiod
    reference_time_range = 1:total_reference_timesteps
    reference_subperiods = Iterators.partition(reference_time_range, reference_timesteps_per_subperiod)
    
    # Get cumulative timesteps for each resolution block (in reference timesteps)
    cumulative_reference_time = cumsum(resolution.block_lengths)
    
    # Map each reference subperiod to resolution blocks
    subperiods_in_resolution_time = Vector{UnitRange{Int}}(undef, number_of_subperiods)
    next_block_idx = 1
    
    for (subperiod_idx, reference_subperiod) in enumerate(reference_subperiods)
        start_block_idx = next_block_idx
        
        # Find all resolution blocks whose cumulative end time falls within this reference subperiod
        while next_block_idx <= length(cumulative_reference_time) && 
              cumulative_reference_time[next_block_idx] ∈ reference_subperiod
            next_block_idx += 1
        end
        
        end_block_idx = next_block_idx - 1
        subperiods_in_resolution_time[subperiod_idx] = start_block_idx:end_block_idx
    end
    
    return subperiods_in_resolution_time
end

function get_unique_rep_periods(subperiod_map::Dict{Int64, Int64})
    
    rep_periods = collect(values(subperiod_map))

    return sort(unique(rep_periods))

end

function get_weights(subperiod_map::Dict{Int64, Int64}, unique_rep_periods::Vector{Int64}, hours_per_subperiod::Int64, total_hours_modeled::Int64)

    # If no period map provided in time_data.json input, each period maps to itself from get_timedata_subperiod_map
    is_identity_mapping = all(subperiod_map[k] == k for k in keys(subperiod_map))

    if is_identity_mapping
        @warn "Using default weights = 1 as no period map provided and each period maps to itself"
        unscaled_weights = [1.0 for _ in unique_rep_periods]
    else

        rep_periods = collect(values(subperiod_map))    # list of rep periods for each subperiod

        unscaled_weights = Int[length(findall(rep_periods .== p)) for p in unique_rep_periods]
    end

    weight_scaling_factor = total_hours_modeled / (sum(unscaled_weights) * hours_per_subperiod)

    scaled_weights = unscaled_weights * weight_scaling_factor

    return scaled_weights
end

function get_timedata_subperiod_map(time_data::AbstractDict{Symbol,Any})
    if haskey(time_data, :SubPeriodMap)
        return Dict(time_data[:SubPeriodMap][!, :Period_Index] .=> time_data[:SubPeriodMap][!, :Rep_Period])
    # if no period map, return a dictionary with the subperiods as keys and values
    # Note: this is the default behavior for the period map
    else
        number_of_subperiods = time_data[:NumberOfSubperiods]
        return Dict(1:number_of_subperiods .=> 1:number_of_subperiods)
    end
end
