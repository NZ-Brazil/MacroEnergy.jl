struct GeneralFuelsEndUse <: AbstractAsset
    id::AssetId
    generalfuelsenduse_transform::Transformation
    fuel_edge::Edge{<:Commodity}
    fuel_demand_edge::Edge{<:Commodity}
    co2_emission_edge::Edge{<:CO2}       # 연소 배출 전용 (신규 추가)
    co2_edge::Edge{<:CO2}                # co2_content (negative emissions) 전용
    co2_captured_edge::Edge{<:CO2Captured}
end


function default_data(t::Type{GeneralFuelsEndUse}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

function full_default_data(::Type{GeneralFuelsEndUse}, id=missing)
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
            :fuel_edge => @edge_data(
                :commodity => "LiquidFuels",
            ),
            :fuel_demand_edge => @edge_data(
                :commodity => "LiquidFuels",
            ),
            # 연소 배출용 (emission_rate 적용)
            :co2_emission_edge => @edge_data(
                :commodity => "CO2",
                :co2_sink => missing,
            ),
            # negative emissions용 (co2_content 적용, BiomassTransformation의 co2_edge와 동일 역할)
            :co2_edge => @edge_data(
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

function simple_default_data(::Type{GeneralFuelsEndUse}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :location => missing,
        :co2_sink => missing,
        :emission_rate => 0.0,
        :co2_content => 0.0,
        :conversion_rate => 1.0,
        :capture_rate => 0.0,
        :fuel_commodity => "LiquidFuels",
        :fuel_demand_commodity => "LiquidFuels",
        :fuel_demand_end_vertex => missing,
        :timedata => "LiquidFuels",
    )
end

function set_commodity!(::Type{GeneralFuelsEndUse}, commodity::Type{<:Commodity}, data::AbstractDict{Symbol,Any})
    if haskey(data, :fuel_commodity)
        data[:fuel_commodity] = string(commodity)
    end
    # fuel_demand_commodity는 의도적으로 건드리지 않음 (다른 commodity일 수 있으므로)
    if haskey(data, :edges)
        if haskey(data[:edges], :fuel_edge)
            if haskey(data[:edges][:fuel_edge], :commodity)
                data[:edges][:fuel_edge][:commodity] = string(commodity)
            end
        end
    end
    return nothing
end

function make(asset_type::Type{GeneralFuelsEndUse}, data::AbstractDict{Symbol,Any}, system::System)
    id = AssetId(data[:id])
    # Fix 3: location 추출 추가
    location = as_symbol_or_missing(get(data, :location, missing))

    @setup_data(asset_type, data, id)

    # --- Transformation ---
    GeneralFuelsEndUse_key = :transforms
    @process_data(
        transform_data,
        data[GeneralFuelsEndUse_key],
        [
            (data[GeneralFuelsEndUse_key], key),
            (data[GeneralFuelsEndUse_key], Symbol("transform_", key)),
            (data, Symbol("transform_", key)),
            (data, key),
        ]
    )
    generalfuelsenduse_transform = Transformation(;
        id = Symbol(id, "_", GeneralFuelsEndUse_key),
        timedata = system.time_data[Symbol(transform_data[:timedata])],
        location = location,    # Fix 3: location 전달
        constraints = transform_data[:constraints],
    )

    # --- fuel_edge (input) ---
    fuel_edge_key = :fuel_edge
    @process_data(
        fuel_edge_data,
        data[:edges][fuel_edge_key],
        [
            (data[:edges][fuel_edge_key], key),
            (data[:edges][fuel_edge_key], Symbol("fuel_", key)),
            (data, Symbol("fuel_", key)),
        ]
    )
    commodity_symbol = Symbol(fuel_edge_data[:commodity])
    commodity = commodity_types()[commodity_symbol]
    @start_vertex(
        fuel_start_node,
        fuel_edge_data,
        commodity,
        [(fuel_edge_data, :start_vertex), (data, :location)],
    )
    fuel_end_node = generalfuelsenduse_transform
    fuel_edge = Edge(
        Symbol(id, "_", fuel_edge_key),
        fuel_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        fuel_start_node,
        fuel_end_node,
    )

    # --- fuel_demand_edge (output) ---
    fuel_demand_edge_key = :fuel_demand_edge
    @process_data(
        fuel_demand_edge_data,
        data[:edges][fuel_demand_edge_key],
        [
            (data[:edges][fuel_demand_edge_key], key),
            (data[:edges][fuel_demand_edge_key], Symbol("fuel_demand_", key)),
            (data, Symbol("fuel_demand_", key)),
        ]
    )
    fuel_demand_commodity_symbol = Symbol(
        get(fuel_demand_edge_data, :commodity,
            get(data, :fuel_demand_commodity, fuel_edge_data[:commodity]))
    )
    fuel_demand_commodity = commodity_types()[fuel_demand_commodity_symbol]
    fuel_demand_start_node = generalfuelsenduse_transform
    @end_vertex(
        fuel_demand_end_node,
        fuel_demand_edge_data,
        fuel_demand_commodity,
        [(fuel_demand_edge_data, :end_vertex), (data, :location)],
    )
    fuel_demand_edge = Edge(
        Symbol(id, "_", fuel_demand_edge_key),
        fuel_demand_edge_data,
        system.time_data[fuel_demand_commodity_symbol],
        fuel_demand_commodity,
        fuel_demand_start_node,
        fuel_demand_end_node,
    )

    # --- co2_emission_edge (연소 배출, emission_rate 적용) ---
    # Fix 2: BiomassTransformation의 co2_emission_edge와 동일한 역할로 분리
    co2_emission_edge_key = :co2_emission_edge
    @process_data(
        co2_emission_edge_data,
        data[:edges][co2_emission_edge_key],
        [
            (data[:edges][co2_emission_edge_key], key),
            (data[:edges][co2_emission_edge_key], Symbol("co2_emission_", key)),
            (data, Symbol("co2_emission_", key)),
            (data, Symbol("co2_", key)),
        ]
    )
    co2_emission_start_node = generalfuelsenduse_transform
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

    # --- co2_edge (negative emissions, co2_content 적용) ---
    # Fix 2: BiomassTransformation의 co2_edge와 동일한 역할 (흡수 방향)
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
    co2_end_node = generalfuelsenduse_transform
    co2_edge = Edge(
        Symbol(id, "_", co2_edge_key),
        co2_edge_data,
        system.time_data[:CO2],
        CO2,
        co2_start_node,
        co2_end_node,
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
    co2_captured_start_node = generalfuelsenduse_transform
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
    # Fix 1: :fuel_demand → :demand (프레임워크 표준 키)
    # Fix 2: emissions(연소)와 negative_emissions(탄소함량)을 별도 edge로 분리
    generalfuelsenduse_transform.balance_data = Dict(
        # Fix 1: :demand 키 사용
        :demand => Dict(
            fuel_edge.id        => get(transform_data, :conversion_rate, 1.0),
            fuel_demand_edge.id => 1.0,
        ),
        # Fix 2: 연소 배출 → co2_emission_edge (BiomassTransformation의 :emissions와 동일)
        :emissions => Dict(
            fuel_edge.id         => get(transform_data, :emission_rate, 0.0),
            co2_emission_edge.id => 1.0,
        ),
        # Fix 2: 연료 내 탄소 → co2_edge 음수 방향 (BiomassTransformation의 :negative_emissions와 동일)
        :negative_emissions => Dict(
            fuel_edge.id => get(transform_data, :co2_content, 0.0),
            co2_edge.id  => -1.0,
        ),
        :capture => Dict(
            fuel_edge.id         => get(transform_data, :capture_rate, 0.0),
            co2_captured_edge.id => 1.0,
        ),
    )

    return GeneralFuelsEndUse(id, generalfuelsenduse_transform, fuel_edge, fuel_demand_edge, co2_emission_edge, co2_edge, co2_captured_edge)
end