###### ###### ###### ###### ###### ######
# Time Series with Resolution-Aware Data
###### ###### ###### ###### ###### ######

"""
MacroTimeSeries: A time series that knows its own resolution.
"""
struct MacroTimeSeries{T <: Real, R <: AbstractResolution}
    data::Vector{T}
    resolution::R
    name::String

    function MacroTimeSeries(data::Vector{T}, resolution::R, name::String="") where {T <: Real, R <: AbstractResolution}
        # Validate that data length matches resolution number of time steps
        validate_data_resolution_match(data, resolution)
        new{T, R}(data, resolution, name)
    end
end

# Default ctor
MacroTimeSeries() = MacroTimeSeries(Float64[], UniformResolution(), "")

# Convenience ctors
MacroTimeSeries(data::Vector{T}, resolution::R) where {T, R} = MacroTimeSeries(data, resolution, "")

"""Validate that data length matches the resolution number of time steps."""
function validate_data_resolution_match(data::Vector, resolution::AbstractResolution)
    steps = time_steps(resolution)
    if length(data)!== 1 && (length(data) != length(steps))
        error("Data length $(length(data)) doesn't match expected length $(length(steps)) for resolution $(resolution)")
    end
end

# Delegate methods to make it look like a vector
Base.length(ts::MacroTimeSeries) = length(ts.data)
Base.size(ts::MacroTimeSeries) = size(ts.data)
Base.getindex(ts::MacroTimeSeries, i) = ts.data[i]
Base.setindex!(ts::MacroTimeSeries, val, i) = ts.data[i] = val
Base.iterate(ts::MacroTimeSeries, args...) = iterate(ts.data, args...)

# Accessors
get_data(ts::MacroTimeSeries) = ts.data
get_resolution(ts::MacroTimeSeries) = ts.resolution
get_name(ts::MacroTimeSeries) = ts.name

"""
Create a MacroTimeSeries from a regular vector and resolution.
"""
function make(data::Vector{T}, resolution::AbstractResolution, name::String="") where T
    return MacroTimeSeries(data, resolution, name)
end