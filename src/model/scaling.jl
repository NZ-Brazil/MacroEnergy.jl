function scaling!(y::Union{AbstractVertex,AbstractEdge})
    atts_vec = attributes_to_scale(y)
    ScalingFactor = 1e3
    for f in atts_vec
        attr = getfield(y, f)
        setfield!(y, f, _scale_attr(attr, ScalingFactor))
    end

end

"""Scale a single attribute; handles MacroTimeSeries and Vector{MacroTimeSeries}."""
function _scale_attr(attr, factor::Real)
    if attr isa MacroTimeSeries
        attr.data ./= factor
        return attr
    elseif attr isa Vector{<:MacroTimeSeries}
        for ts in attr
            ts.data ./= factor
        end
        return attr
    else
        return attr / factor
    end
end

function scaling!(a::AbstractAsset)
    for t in fieldnames(typeof(a))
        scaling!(getfield(a, t))
    end
    return nothing
end

function scaling!(system::System)

    @info("Scaling system data to GWh | ktons | M\$")

    scaling!.(system.locations)

    scaling!.(system.assets)

    return nothing
end

function attributes_to_scale(n::Node)
    return [:demand, :max_supply, :price, :price_nsd, :price_supply, :price_unmet_policy, :rhs_policy]
end

function attributes_to_scale(e::Edge)
    return [:capacity_size, :existing_capacity, :fixed_om_cost, :investment_cost, :max_capacity, :min_capacity, :variable_om_cost]
end

function attributes_to_scale(e::EdgeWithUC)
    return [:capacity_size, :existing_capacity, :fixed_om_cost, :investment_cost, :max_capacity, :min_capacity, :variable_om_cost, :startup_cost]
end

function attributes_to_scale(g::AbstractStorage)
    return [:capacity_size,:existing_capacity,:fixed_om_cost,:investment_cost,:max_capacity,:min_capacity]
end

function attributes_to_scale(t::Transformation)
    return Symbol[]
end


function /(d::AbstractDict, factor::Float64)
    for (k, v) in d
        if isa(v, Number)
            d[k] = v / factor
        elseif isa(v, AbstractVector)
            d[k] = Float64.(v) ./ factor
        elseif isa(v, AbstractDict)
            d[k] = v / factor
        else
            throw(ArgumentError("Cannot scale dictionary value of type $(typeof(v))"))
        end
    end
    return d
end

# MacroEnergyScaling.scale_constraints!
function scale_constraints!(system::System, model::Model)
    if system.settings.ConstraintScaling
        @info "Scaling constraints and RHS"
        scale_constraints!(model)
    end
    return nothing
end

# MacroEnergyScaling.scale_constraints!
function scale_constraints!(systems::Vector{System}, models::Vector{Model})
    @assert length(systems) == length(models)
    for (system, model) in zip(systems, models)
        scale_constraints!(system, model)
    end
    return nothing
end

# MacroEnergyScaling.scale_constraints!
function scale_constraints!(case::Case, models::Vector{Model})
    scale_constraints!(case.systems, models)
    return nothing
end