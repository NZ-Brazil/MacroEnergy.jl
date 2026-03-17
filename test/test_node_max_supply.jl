module TestNodeMaxSupply

using Test
using CSV
using DataFrames
import MacroEnergy:
    Node,
    Electricity,
    Biomass,
    commodity_type,
    TimeData,
    UniformResolution,
    load_system,
    load_time_series_data,
    load_time_series_data!,
    empty_system,
    max_supply,
    price_supply,
    supply_segments,
    supply_flow,
    time_steps,
    any_supply_capacity,
    compute_supply_cost,
    scaling!

const test_path = joinpath(@__DIR__, "test_inputs")

"""
TDD tests for time-varying max_supply.
These tests specify the desired API; they will fail (red) until implementation.
"""

function make_time_data()
    return TimeData(;
        resolution = UniformResolution(1, 3),
        period_index = 1,
        subperiods = [1:1, 2:2, 3:3],
        subperiod_indices = [1, 2, 3],
        subperiod_weights = Dict(1 => 1/3, 2 => 1/3, 3 => 1/3),
        subperiod_map = Dict(1 => 1, 2 => 2, 3 => 3)
    )
end

@testset "max_supply: Parsing (legacy format)" begin
    time_data = make_time_data()
    data = Dict(
        :id => :test,
        :max_supply => [100.0, 200.0],
        :demand => [0.0],
        :balance_data => Dict(:demand => Dict{Symbol,Float64}())
    )
    n = Node(data, time_data, Electricity)
    # Legacy: one value per segment, constant over all time steps
    @test max_supply(n, 1, 1) == 100.0
    @test max_supply(n, 1, 2) == 100.0
    @test max_supply(n, 2, 3) == 200.0
end

@testset "max_supply: Parsing (time-varying format)" begin
    time_data = make_time_data()
    data = Dict(
        :id => :test,
        :max_supply => [[100.0, 101.0, 102.0], [200.0, 201.0, 202.0]],
        :demand => [0.0],
        :balance_data => Dict(:demand => Dict{Symbol,Float64}())
    )
    n = Node(data, time_data, Electricity)
    @test max_supply(n, 1, 1) == 100.0
    @test max_supply(n, 1, 2) == 101.0
    @test max_supply(n, 1, 3) == 102.0
    @test max_supply(n, 2, 1) == 200.0
    @test max_supply(n, 2, 3) == 202.0
end

@testset "max_supply: Accessor max_supply(n,s,t)" begin
    time_data = make_time_data()
    data = Dict(
        :id => :test,
        :max_supply => [50.0],
        :demand => [0.0],
        :balance_data => Dict(:demand => Dict{Symbol,Float64}())
    )
    n = Node(data, time_data, Electricity)
    @test max_supply(n, 1, 1) == 50.0
    @test max_supply(n, 1, 2) == 50.0
end

@testset "max_supply: supply_segments unchanged" begin
    time_data = make_time_data()
    data = Dict(
        :id => :test,
        :max_supply => [10.0, 20.0, 30.0],
        :demand => [0.0],
        :balance_data => Dict(:demand => Dict{Symbol,Float64}())
    )
    n = Node(data, time_data, Electricity)
    @test collect(supply_segments(n)) == [1, 2, 3]
end

@testset "max_supply: any_supply_capacity gate" begin
    time_data = make_time_data()
    data_zero = Dict(
        :id => :test,
        :max_supply => [0.0],
        :demand => [0.0],
        :balance_data => Dict(:demand => Dict{Symbol,Float64}())
    )
    data_nonzero = Dict(
        :id => :test,
        :max_supply => [100.0],
        :demand => [0.0],
        :balance_data => Dict(:demand => Dict{Symbol,Float64}())
    )
    n_zero = Node(data_zero, time_data, Electricity)
    n_nonzero = Node(data_nonzero, time_data, Electricity)
    @test !any_supply_capacity(n_zero)
    @test any_supply_capacity(n_nonzero)
end

@testset "max_supply: Integration - load system with Biomass nodes" begin
    system = load_system(test_path)
    biomass_nodes = filter(system.locations) do loc
        loc isa Node && commodity_type(loc) == Biomass
    end
    @test !isempty(biomass_nodes)
    # At least one Biomass node should have max_supply (legacy format)
    has_supply = false
    for n in biomass_nodes
        if any_supply_capacity(n)
            has_supply = true
            @test length(supply_segments(n)) >= 1
            break
        end
    end
    @test has_supply
end

@testset "max_supply: compute_supply_cost with zero supply" begin
    time_data = make_time_data()
    data = Dict(
        :id => :test,
        :max_supply => [0.0],
        :demand => [0.0],
        :balance_data => Dict(:demand => Dict{Symbol,Float64}())
    )
    n = Node(data, time_data, Electricity)
    @test compute_supply_cost(n) == 0.0
end

@testset "max_supply: scaling! does not error" begin
    time_data = make_time_data()
    data = Dict(
        :id => :test,
        :max_supply => [100.0, 200.0],
        :demand => [0.0],
        :balance_data => Dict(:demand => Dict{Symbol,Float64}())
    )
    n = Node(data, time_data, Electricity)
    scaling!(n)
    # After scaling, values should be reduced
    @test max_supply(n, 1, 1) ≈ 0.1 atol = 1e-10  # 100/1000
    @test max_supply(n, 2, 1) ≈ 0.2 atol = 1e-10  # 200/1000
end

@testset "max_supply: Import from file (timeseries headers)" begin
    # Test that load_time_series_data with headers returns Vector{Vector{Float64}}
    # and that make_node correctly parses it
    csv_path = joinpath(test_path, "system", "demand.csv")
    @test isfile(csv_path)
    loaded = load_time_series_data(csv_path, ["Demand_MW_z1", "Demand_MW_z2"])
    @test loaded isa Vector{Vector{Float64}}
    @test length(loaded) == 2
    @test length(loaded[1]) == length(loaded[2]) > 1
    # Use first 3 rows to match make_time_data resolution (3 steps)
    seg1 = Float64.(loaded[1][1:3])
    seg2 = Float64.(loaded[2][1:3])
    time_data = make_time_data()
    data = Dict(
        :id => :test,
        :max_supply => [seg1, seg2],
        :demand => [0.0],
        :balance_data => Dict(:demand => Dict{Symbol,Float64}())
    )
    n = Node(data, time_data, Electricity)
    @test max_supply(n, 1, 1) == seg1[1]
    @test max_supply(n, 1, 2) == seg1[2]
    @test max_supply(n, 2, 3) == seg2[3]
end

@testset "max_supply: Import from file (header + segments convention)" begin
    # Convention: segment 1 = header, segment 2 = header_2, segment 3 = header_3, ...
    time_data = make_time_data()
    tmpdir = abspath(mktempdir("."))
    try
        csv_path = joinpath(tmpdir, "max_supply.csv")
        df = DataFrame(
            conv_test = [10.0, 11.0, 12.0],
            conv_test_2 = [20.0, 21.0, 22.0],
            conv_test_3 = [30.0, 31.0, 32.0]
        )
        CSV.write(csv_path, df)
        sys = empty_system(tmpdir)
        data = Dict(
            :id => :test,
            :max_supply => Dict(
                :timeseries => Dict(
                    :path => "max_supply.csv",
                    :header => "conv_test",
                    :segments => 3
                )
            ),
            :demand => [0.0],
            :balance_data => Dict(:demand => Dict{Symbol,Float64}())
        )
        load_time_series_data!(sys, data)
        loaded = data[:max_supply]
        @test loaded isa Vector{Vector{Float64}}
        @test length(loaded) == 3
        @test loaded[1] == [10.0, 11.0, 12.0]
        @test loaded[2] == [20.0, 21.0, 22.0]
        @test loaded[3] == [30.0, 31.0, 32.0]
        data[:price_supply] = [40.0, 60.0, 80.0]  # legacy, must match segment count
        n = Node(data, time_data, Electricity)
        @test max_supply(n, 1, 1) == 10.0
        @test max_supply(n, 1, 3) == 12.0
        @test max_supply(n, 3, 2) == 31.0
    finally
        rm(tmpdir, recursive = true, force = true)
    end
end

@testset "price_supply: Parsing (legacy and time-varying)" begin
    time_data = make_time_data()
    # Legacy
    data_legacy = Dict(
        :id => :test,
        :max_supply => [100.0],
        :price_supply => [40.0],
        :demand => [0.0],
        :balance_data => Dict(:demand => Dict{Symbol,Float64}())
    )
    n = Node(data_legacy, time_data, Electricity)
    @test price_supply(n, 1, 1) == 40.0
    @test price_supply(n, 1, 2) == 40.0
    # Time-varying
    data_tv = Dict(
        :id => :test,
        :max_supply => [[100.0, 100.0, 100.0]],
        :price_supply => [[40.0, 41.0, 42.0]],
        :demand => [0.0],
        :balance_data => Dict(:demand => Dict{Symbol,Float64}())
    )
    n2 = Node(data_tv, time_data, Electricity)
    @test price_supply(n2, 1, 1) == 40.0
    @test price_supply(n2, 1, 2) == 41.0
    @test price_supply(n2, 1, 3) == 42.0
end

@testset "price_supply: Import from file (header + segments convention)" begin
    time_data = make_time_data()
    tmpdir = abspath(mktempdir("."))
    try
        csv_path = joinpath(tmpdir, "price_supply.csv")
        df = DataFrame(
            conv_test = [40.0, 41.0, 42.0],
            conv_test_2 = [60.0, 61.0, 62.0],
            conv_test_3 = [80.0, 81.0, 82.0]
        )
        CSV.write(csv_path, df)
        sys = empty_system(tmpdir)
        data = Dict(
            :id => :test,
            :max_supply => [100.0, 200.0, 300.0],
            :price_supply => Dict(
                :timeseries => Dict(
                    :path => "price_supply.csv",
                    :header => "conv_test",
                    :segments => 3
                )
            ),
            :demand => [0.0],
            :balance_data => Dict(:demand => Dict{Symbol,Float64}())
        )
        load_time_series_data!(sys, data)
        loaded = data[:price_supply]
        @test loaded isa Vector{Vector{Float64}}
        @test length(loaded) == 3
        @test loaded[1] == [40.0, 41.0, 42.0]
        @test loaded[2] == [60.0, 61.0, 62.0]
        @test loaded[3] == [80.0, 81.0, 82.0]
        n = Node(data, time_data, Electricity)
        @test price_supply(n, 1, 1) == 40.0
        @test price_supply(n, 1, 3) == 42.0
        @test price_supply(n, 3, 2) == 81.0
    finally
        rm(tmpdir, recursive = true, force = true)
    end
end

@testset "price_supply: scaling! does not error" begin
    time_data = make_time_data()
    data = Dict(
        :id => :test,
        :max_supply => [100.0, 200.0],
        :price_supply => [40.0, 60.0],
        :demand => [0.0],
        :balance_data => Dict(:demand => Dict{Symbol,Float64}())
    )
    n = Node(data, time_data, Electricity)
    scaling!(n)
    # After scaling, price_supply values should be reduced (divide by 1000)
    @test price_supply(n, 1, 1) ≈ 0.04 atol = 1e-10  # 40/1000
    @test price_supply(n, 2, 1) ≈ 0.06 atol = 1e-10  # 60/1000
end

end # module
