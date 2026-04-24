struct CommodityTransform <: AbstractAsset
    id::AssetId
    commodity_transform::Transformation
    origin_edge::Edge{<:Commodity}          # input commodity
    output_edge::Edge{<:Commodity}          # output commodity (다른 commodity 가능)
    co2_edge::Edge{<:CO2}                   # negative emissions (co2_content, input 방향)
    co2_emission_edge::Edge{<:CO2}          # 연소/변환 배출 (emission_rate, output 방향)
    co2_captured_edge::Edge{<:CO2Captured}  # CCS capture
end

function default_data(t::Type{CommodityTransform}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

function full_default_data(::Type{CommodityTransform}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :transforms => @transform_data(
            :timedata => "LiquidFuels",
            :constraints => Dict{Symbol,Bool}(
                :BalanceConstraint => true,
            ),
            :conversion_rate => 1.0,
            :emission_rate => 0.0,
            :co2_content => 0.0,
            :capture_rate => 0.0,
        ),
        :edges => Dict{Symbol,Any}(
            :origin_edge => @edge_data(
                :commodity => "LiquidFuels",
                :has_capacity => true,
                :can_expand => true,
                :can_retire => true,
                :constraints => Dict{Symbol,Bool}(
                    :CapacityConstraint => true,
                )
            ),
            :output_edge => @edge_data(
                :commodity => "LiquidFuels",
            ),
            :co2_edge => @edge_data(
                :commodity => "CO2",
                :co2_sink => missing,
            ),
            :co2_emission_edge => @edge_data(
                :commodity => "CO2",
                :co2_sink => missing,
            ),
            :co2_captured_edge => @edge_data(
                :commodity => "CO2Captured",
                :has_capacity => false,
                :can_expand => false,
                :can_retire => false,
            ),
        ),
    )
end

function simple_default_data(::Type{CommodityTransform}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :location => missing,
        :co2_sink => missing,
        :conversion_rate => 1.0,
        :emission_rate => 0.0,
        :co2_content => 0.0,
        :capture_rate => 0.0,
        :origin_commodity => "LiquidFuels",
        :output_commodity => "LiquidFuels",
        :timedata => "LiquidFuels",
    )
end

function set_commodity!(::Type{CommodityTransform}, commodity::Type{<:Commodity}, data::AbstractDict{Symbol,Any})
    # origin commodity만 업데이트 (output은 의도적으로 다를 수 있으므로 건드리지 않음)
    if haskey(data, :origin_commodity)
        data[:origin_commodity] = string(commodity)
    end
    if haskey(data, :edges)
        if haskey(data[:edges], :origin_edge)
            if haskey(data[:edges][:origin_edge], :commodity)
                data[:edges][:origin_edge][:commodity] = string(commodity)
            end
        end
    end
    return nothing
end

function make(asset_type::Type{CommodityTransform}, data::AbstractDict{Symbol,Any}, system::System)
    id = AssetId(data[:id])
    location = as_symbol_or_missing(get(data, :location, missing))

    @setup_data(asset_type, data, id)

    # --- Transformation ---
    commodity_transform_key = :transforms
    @process_data(
        transform_data,
        data[commodity_transform_key],
        [
            (data[commodity_transform_key], key),
            (data[commodity_transform_key], Symbol("transform_", key)),
            (data, Symbol("transform_", key)),
            (data, key),
        ]
    )
    commodity_transform = Transformation(;
        id = Symbol(id, "_", commodity_transform_key),
        timedata = system.time_data[Symbol(transform_data[:timedata])],
        location = location,
        constraints = transform_data[:constraints],
    )

    # --- origin_edge (input) ---
    origin_edge_key = :origin_edge
    @process_data(
        origin_edge_data,
        data[:edges][origin_edge_key],
        [
            (data[:edges][origin_edge_key], key),
            (data[:edges][origin_edge_key], Symbol("origin_", key)),
            (data, Symbol("origin_", key)),
            (data, key),
        ]
    )
    origin_commodity_symbol = Symbol(origin_edge_data[:commodity])
    origin_commodity = commodity_types()[origin_commodity_symbol]
    @start_vertex(
        origin_start_node,
        origin_edge_data,
        origin_commodity,
        [(origin_edge_data, :start_vertex), (data, :location)],
    )
    origin_end_node = commodity_transform
    origin_edge = Edge(
        Symbol(id, "_", origin_edge_key),
        origin_edge_data,
        system.time_data[origin_commodity_symbol],
        origin_commodity,
        origin_start_node,
        origin_end_node,
    )

    # --- output_edge (output, 다른 commodity 가능) ---
    output_edge_key = :output_edge
    @process_data(
        output_edge_data,
        data[:edges][output_edge_key],
        [
            (data[:edges][output_edge_key], key),
            (data[:edges][output_edge_key], Symbol("output_", key)),
            (data, Symbol("output_", key)),
        ]
    )
    # output commodity 우선순위: output_edge.commodity > output_commodity > origin_edge.commodity
    output_commodity_symbol = Symbol(
        get(output_edge_data, :commodity,
            get(data, :output_commodity, origin_edge_data[:commodity]))
    )
    output_commodity = commodity_types()[output_commodity_symbol]
    output_start_node = commodity_transform
    @end_vertex(
        output_end_node,
        output_edge_data,
        output_commodity,
        [(output_edge_data, :end_vertex), (data, :location)],
    )
    output_edge = Edge(
        Symbol(id, "_", output_edge_key),
        output_edge_data,
        system.time_data[output_commodity_symbol],
        output_commodity,
        output_start_node,
        output_end_node,
    )

    # --- co2_edge (negative emissions, co2_content 적용, input 방향) ---
    co2_edge_key = :co2_edge
    @process_data(
        co2_edge_data,
        data[:edges][co2_edge_key],
        [
            (data[:edges][co2_edge_key], key),
            (data[:edges][co2_edge_key], Symbol("co2_", key)),
            (data, Symbol("co2_", key)),
        ]
    )
    @start_vertex(
        co2_start_node,
        co2_edge_data,
        CO2,
        [(co2_edge_data, :start_vertex), (data, :co2_sink), (data, :location)],
    )
    co2_end_node = commodity_transform
    co2_edge = Edge(
        Symbol(id, "_", co2_edge_key),
        co2_edge_data,
        system.time_data[:CO2],
        CO2,
        co2_start_node,
        co2_end_node,
    )

    # --- co2_emission_edge (연소/변환 배출, emission_rate 적용, output 방향) ---
    co2_emission_edge_key = :co2_emission_edge
    @process_data(
        co2_emission_edge_data,
        data[:edges][co2_emission_edge_key],
        [
            (data[:edges][co2_emission_edge_key], key),
            (data[:edges][co2_emission_edge_key], Symbol("co2_emission_", key)),
            (data, Symbol("co2_emission_", key)),
        ]
    )
    co2_emission_start_node = commodity_transform
    @end_vertex(
        co2_emission_end_node,
        co2_emission_edge_data,
        CO2,
        [(co2_emission_edge_data, :end_vertex), (data, :co2_sink), (data, :location)],
    )
    co2_emission_edge = Edge(
        Symbol(id, "_", co2_emission_edge_key),
        co2_emission_edge_data,
        system.time_data[:CO2],
        CO2,
        co2_emission_start_node,
        co2_emission_end_node,
    )

    # --- co2_captured_edge ---
    co2_captured_edge_key = :co2_captured_edge
    @process_data(
        co2_captured_edge_data,
        data[:edges][co2_captured_edge_key],
        [
            (data[:edges][co2_captured_edge_key], key),
            (data[:edges][co2_captured_edge_key], Symbol("co2_captured_", key)),
            (data, Symbol("co2_captured_", key)),
        ]
    )
    co2_captured_start_node = commodity_transform
    @end_vertex(
        co2_captured_end_node,
        co2_captured_edge_data,
        CO2Captured,
        [(co2_captured_edge_data, :end_vertex), (data, :location)],
    )
    co2_captured_edge = Edge(
        Symbol(id, "_", co2_captured_edge_key),
        co2_captured_edge_data,
        system.time_data[:CO2Captured],
        CO2Captured,
        co2_captured_start_node,
        co2_captured_end_node,
    )

    # --- balance_data ---
    # :demand             : origin * conversion_rate == output
    # :negative_emissions : origin * co2_content     == co2 흡수 (음수 방향)
    # :emissions          : origin * emission_rate    == co2_emission 배출
    # :capture            : origin * capture_rate     == co2_captured
    commodity_transform.balance_data = Dict(
        :demand => Dict(
            origin_edge.id => get(transform_data, :conversion_rate, 1.0),
            output_edge.id => 1.0,
        ),
        :negative_emissions => Dict(
            origin_edge.id => get(transform_data, :co2_content, 0.0),
            co2_edge.id    => -1.0,
        ),
        :emissions => Dict(
            origin_edge.id       => get(transform_data, :emission_rate, 0.0),
            co2_emission_edge.id => 1.0,
        ),
        :capture => Dict(
            origin_edge.id         => get(transform_data, :capture_rate, 0.0),
            co2_captured_edge.id   => 1.0,
        ),
    )

    return CommodityTransform(id, commodity_transform, origin_edge, output_edge, co2_edge, co2_emission_edge, co2_captured_edge)
end