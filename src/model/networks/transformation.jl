"""
    Transformation <: AbstractVertex

    A mutable struct representing a transformation vertex in a network model, which models a conversion process between different commodities or energy forms.

    # Inherited Attributes
    - id::Symbol: Unique identifier for the transformation
    - timedata::TimeData: Time-related data for the transformation
    - balance_data::Dict{Symbol,Dict{Symbol,Float64}}: Dictionary mapping stoichiometric equation IDs to coefficients
    - constraints::Vector{AbstractTypeConstraint}: List of constraints applied to the transformation
    - operation_expr::Dict: Dictionary storing operational JuMP expressions for the transformation

    Transformations are used to model conversion processes between different commodities, such as power plants 
    converting fuel to electricity or electrolyzers converting electricity to hydrogen. The `balance_data` field 
    typically contains conversion efficiencies and other relationships between input and output flows.
"""
Base.@kwdef mutable struct Transformation <: AbstractVertex
    @AbstractVertexBaseAttributes()
    balance_time_intervals::Dict{Symbol,Vector{UnitRange{Int}}} = Dict{Symbol,Vector{UnitRange{Int}}}()
end

function add_linking_variables!(g::Transformation, model::Model)
    return nothing
end

function planning_model!(g::Transformation, model::Model)

    return nothing
end

function define_available_capacity!(g::Transformation, model::Model)
    return nothing
end

function operation_model!(g::Transformation, model::Model)
    if !isempty(balance_ids(g))
        for i in balance_ids(g)
            g.operation_expr[i] =
                @expression(model, [t in time_steps(g, i)], 0 * model[:vREF])
        end
    end
    return nothing
end

time_steps(g::Transformation, i::Symbol) = 1:length(balance_time_intervals(g, i))

function balance_time_intervals(g::Transformation, balance_id::Symbol)
    return g.balance_time_intervals[balance_id]
end

"""
    update_time_intervals_in_balance_equations!(asset::AbstractAsset)

Update time intervals for all balance IDs in a transformation. See [update_time_intervals_in_balance_equations!(transform::Transformation, balance_id::Symbol, edges::Vector{<:MacroObject})](@ref)

# Arguments
- `asset::AbstractAsset`: The asset with transformations to update the time intervals for

# Returns
- `nothing`
"""
function update_time_intervals_in_balance_equations!(asset::AbstractAsset)
    # Get all edges and transformations from the asset
    asset_edges = get_edges(asset)
    transformations = get_transformations(asset)

    for transform in transformations
        update_time_intervals_in_balance_equations!(transform, asset_edges)
    end

    return nothing
end

"""
    update_time_intervals_in_balance_equations!(transform::Transformation, edges::Vector{<:AbstractEdge})
Update time intervals for all balance IDs in a transformation. See [update_time_intervals_in_balance_equations!(g::Transformation, balance_id::Symbol, edges::Vector{<:MacroObject})](@ref)
This function inspects the `balance_data` in the transformation and automatically calls `update_time_intervals_in_balance_equations!`
for each balance ID with its corresponding edges.
"""
function update_time_intervals_in_balance_equations!(transform::Transformation, edges::Vector{<:AbstractEdge})
    if isempty(balance_data(transform))
        return nothing
    end

    # For each balance ID, find the edges that participate in that balance
    for (balance_id, balance_data_values) in balance_data(transform)

        participating_edges = AbstractEdge[]

        # Find edges that have non-zero coefficients in this balance
        for edge in edges
            if haskey(balance_data_values, id(edge)) && balance_data_values[id(edge)] != 0.0
                push!(participating_edges, edge)
            end
        end

        # Update time resolution for this balance if we found participating edges
        if !isempty(participating_edges)
            update_time_intervals_in_balance_equations!(transform, balance_id, participating_edges)
        end
    end

    return nothing
end

"""
    update_time_intervals_in_balance_equations!(g::Transformation, balance_id::Symbol, edges::Vector{<:MacroObject})
Update time intervals for a specific balance ID in a transformation. 
This function calls `find_common_time_intervals` to find the time intervals that are common to all time resolutions of the edges participating in the balance.
Once the time intervals are found, they are stored in the `balance_time_intervals` dictionary of the transformation.
"""
function update_time_intervals_in_balance_equations!(g::Transformation, balance_id::Symbol, edges::Vector{<:MacroObject})
    @assert all(isa.(edges, AbstractEdge)) "All edges must be subtypes of AbstractEdge"
    constraint_blocks = find_common_time_intervals(time_resolution.(edges), period_length(time_resolution(g)))
    g.balance_time_intervals[balance_id] = constraint_blocks
    return nothing
end