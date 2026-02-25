module TestMultiResolution

using Test
import MacroEnergy:
    UniformResolution,
    FlexibleResolution,
    period_length,
    time_interval,
    time_steps,
    can_span_subperiods,
    validate_time_resolution,
    validate_temporal_resolution,
    create_subperiods,
    find_common_time_intervals,
    map_time_steps_to_common_time_intervals,
    Transformation,
    Edge,
    TimeData,
    Electricity,
    Node,
    update_time_intervals_in_balance_equations!,
    update_balance!,
    balance_data,
    get_balance,
    balance_ids,
    MacroTimeSeries,
    get_data,
    get_resolution,
    get_name,
    make
using JuMP


function test_uniform_resolution()
    @testset "Constructor - Basic Cases" begin
        # Simple case: block_length=1, period_length=5
        res = UniformResolution(1, 5)
        @test res.block_length == 1
        @test res.period_length == 5
        @test res.first_steps_in_time_interval == 1:1:5
        @test res.time_steps == 1:5
        @test res.time_interval == [1:1, 2:2, 3:3, 4:4, 5:5]

        # Case: block_length=2, period_length=6
        res2 = UniformResolution(2, 6)
        @test res2.block_length == 2
        @test res2.period_length == 6
        @test res2.first_steps_in_time_interval == 1:2:6
        @test res2.time_steps == 1:3
        @test res2.time_interval == [1:2, 3:4, 5:6]

        # Case: block_length=3, period_length=10
        res3 = UniformResolution(3, 10)
        @test res3.block_length == 3
        @test res3.period_length == 10
        @test res3.first_steps_in_time_interval == 1:3:10
        @test res3.time_steps == 1:4
        @test res3.time_interval == [1:3, 4:6, 7:9, 10:10]
    end

    @testset "Constructor - Edge Cases" begin
        # block_length equals period_length
        res = UniformResolution(5, 5)
        @test res.block_length == 5
        @test res.period_length == 5
        @test res.first_steps_in_time_interval == 1:5:1
        @test res.time_steps == 1:1
        @test res.time_interval == [1:5]

        # block_length larger than period_length (should still work)
        res2 = UniformResolution(10, 5)
        @test res2.block_length == 10
        @test res2.period_length == 5
        @test res2.time_steps == 1:1
        @test res2.time_interval == [1:5]

        # Large period_length
        res3 = UniformResolution(24, 8760)
        @test res3.block_length == 24
        @test res3.period_length == 8760
        @test length(res3.time_steps) == 365
        @test res3.time_interval[1] == 1:24
        @test res3.time_interval[end] == 8737:8760

        # Non multiple of block_length
        res4 = UniformResolution(24, 8761)
        @test res4.block_length == 24
        @test res4.period_length == 8761
        @test res4.first_steps_in_time_interval == 1:24:8761
        @test length(res4.time_steps) == 366
        @test res4.time_interval[1] == 1:24
        @test res4.time_interval[end] == 8761:8761
    end

    # Default constructor is UniformResolution(1, 0)
    @testset "Default Constructor" begin
        res = UniformResolution()
        @test res.block_length == 1
        @test res.period_length == 0
        @test res.time_steps == 1:0  # Empty range
        @test isempty(res.time_interval)
    end

    @testset "Constructor - Error Cases" begin
        # Zero block_length should error
        @test_throws AssertionError UniformResolution(0, 10)

        # Negative block_length should error
        @test_throws AssertionError UniformResolution(-1, 10)
    end

    @testset "Interface Functions - UniformResolution" begin
        res = UniformResolution(3, 9)

        # Test period_length accessor
        @test period_length(res) == 9

        # Test time_interval accessor
        expected_intervals = [1:3, 4:6, 7:9]
        @test time_interval(res) == expected_intervals

        # Test time_steps accessor
        @test time_steps(res) == 1:3
    end
end

function test_flexible_resolution()

    @testset "Constructor - Basic Cases" begin
        # Simple case: [1, 1, 1] with period_length=3
        res = FlexibleResolution([1, 1, 1], 3)
        @test res.block_lengths == [1, 1, 1]
        @test res.period_length == 3
        @test res.first_steps_in_time_interval == [1, 2, 3]
        @test res.time_steps == 1:3
        @test res.time_interval == [1:1, 2:2, 3:3]

        # Case: [2, 3, 2] with period_length=7
        res2 = FlexibleResolution([2, 3, 2], 7)
        @test res2.block_lengths == [2, 3, 2]
        @test res2.period_length == 7
        @test res2.first_steps_in_time_interval == [1, 3, 6]
        @test res2.time_steps == 1:3
        @test res2.time_interval == [1:2, 3:5, 6:7]

        # Case: [1, 2, 2, 1] with period_length=6
        res3 = FlexibleResolution([1, 2, 2, 1], 6)
        @test res3.block_lengths == [1, 2, 2, 1]
        @test res3.period_length == 6
        @test res3.first_steps_in_time_interval == [1, 2, 4, 6]
        @test res3.time_steps == 1:4
        @test res3.time_interval == [1:1, 2:3, 4:5, 6:6]
    end

    @testset "Constructor - Complex Cases" begin
        # Single block
        res = FlexibleResolution([10], 10)
        @test res.block_lengths == [10]
        @test res.period_length == 10
        @test res.first_steps_in_time_interval == [1]
        @test res.time_steps == 1:1
        @test res.time_interval == [1:10]

        # Many blocks
        res2 = FlexibleResolution([1, 2, 3, 4, 5], 15)
        @test res2.block_lengths == [1, 2, 3, 4, 5]
        @test res2.period_length == 15
        @test res2.first_steps_in_time_interval == [1, 2, 4, 7, 11]
        @test res2.time_steps == 1:5
        @test res2.time_interval == [1:1, 2:3, 4:6, 7:10, 11:15]

        # Large block_lengths
        res3 = FlexibleResolution([24, 24, 24], 72)
        @test res3.block_lengths == [24, 24, 24]
        @test res3.period_length == 72
        @test res3.first_steps_in_time_interval == [1, 25, 49]
        @test res3.time_steps == 1:3
        @test res3.time_interval == [1:24, 25:48, 49:72]
    end

    @testset "Constructor - Variable Block Lengths" begin
        # Example from docstring: [1,3,4,6,7]
        block_lengths = [1, 3, 4, 6, 7]
        period_length = sum(block_lengths)  # 21
        res = FlexibleResolution(block_lengths, period_length)
        @test res.block_lengths == block_lengths
        @test res.period_length == period_length
        @test res.first_steps_in_time_interval == [1, 2, 5, 9, 15]
        @test res.time_steps == 1:5
        @test res.time_interval == [1:1, 2:4, 5:8, 9:14, 15:21]
    end

    @testset "Constructor - Error Cases" begin
        # Zero block_length should error
        @test_throws AssertionError FlexibleResolution([0, 1, 2], 3)

        # Negative block_length should error
        @test_throws AssertionError FlexibleResolution([-1, 2, 3], 4)

        # Multiple zeros should error
        @test_throws AssertionError FlexibleResolution([1, 0, 0, 2], 3)

        # Empty block_lengths should error
        @test_throws ErrorException FlexibleResolution(Int[], 0)
        @test_throws ErrorException FlexibleResolution(Int[], 1)
        @test_throws ErrorException FlexibleResolution(Int[1, 2, 3], 0)
        @test_throws ErrorException FlexibleResolution(Int[1, 2, 3], -1)
    end

    @testset "Interface Functions - FlexibleResolution" begin
        res = FlexibleResolution([2, 3, 2], 7)

        # Test period_length accessor
        @test period_length(res) == 7

        # Test time_interval accessor
        expected_intervals = [1:2, 3:5, 6:7]
        @test time_interval(res) == expected_intervals

        # Test time_steps accessor
        @test time_steps(res) == 1:3
    end

    @testset "First Steps Calculation" begin
        # Verify first_steps_in_time_interval calculation
        res = FlexibleResolution([3, 5, 2, 4], 14)
        # First step is always 1
        # Second step starts at 1 + 3 = 4
        # Third step starts at 1 + 3 + 5 = 9
        # Fourth step starts at 1 + 3 + 5 + 2 = 11
        @test res.first_steps_in_time_interval == [1, 4, 9, 11]
    end

    @testset "Time Interval Continuity" begin
        # Verify that time intervals are continuous and non-overlapping
        res = FlexibleResolution([2, 3, 4, 1], 10)
        intervals = res.time_interval

        # Check that intervals are continuous
        @test intervals[1].stop + 1 == intervals[2].start
        @test intervals[2].stop + 1 == intervals[3].start
        @test intervals[3].stop + 1 == intervals[4].start

        # Check that sum of block_lengths equals period_length
        @test sum(res.block_lengths) == res.period_length
    end
end

function test_interface_functions()

    @testset "period_length" begin
        uniform_res = UniformResolution(3, 12)
        flexible_res = FlexibleResolution([2, 3, 4, 3], 12)

        @test period_length(uniform_res) == 12
        @test period_length(flexible_res) == 12
    end

    @testset "time_interval" begin
        uniform_res = UniformResolution(2, 6)
        flexible_res = FlexibleResolution([2, 2, 2], 6)

        uniform_intervals = time_interval(uniform_res)
        flexible_intervals = time_interval(flexible_res)

        @test uniform_intervals == [1:2, 3:4, 5:6]
        @test flexible_intervals == [1:2, 3:4, 5:6]
    end

    @testset "time_steps" begin
        uniform_res = UniformResolution(3, 9)
        flexible_res = FlexibleResolution([3, 3, 3], 9)

        @test time_steps(uniform_res) == 1:3
        @test time_steps(flexible_res) == 1:3
    end
end

function test_equivalence_tests()

    @testset "Uniform vs Flexible - Same Structure" begin
        # UniformResolution(2, 6) should be equivalent to FlexibleResolution([2, 2, 2], 6)
        uniform_res = UniformResolution(2, 6)
        flexible_res = FlexibleResolution([2, 2, 2], 6)

        @test period_length(uniform_res) == period_length(flexible_res)
        @test time_interval(uniform_res) == time_interval(flexible_res)
        @test time_steps(uniform_res) == time_steps(flexible_res)
    end

    @testset "Different Structures - Same Period Length" begin
        uniform_res = UniformResolution(1, 10)
        flexible_res = FlexibleResolution([3, 4, 3], 10)

        @test period_length(uniform_res) == period_length(flexible_res)
        @test period_length(uniform_res) == 10
        # But they have different time intervals
        @test length(time_interval(uniform_res)) != length(time_interval(flexible_res))
    end
    
    @testset "Equality and Hash" begin
        # Test that equal objects have equal hashes
        res1 = UniformResolution(3, 9)
        res2 = UniformResolution(3, 9)
        @test res1 == res2
        @test hash(res1) == hash(res2)
        
        res3 = FlexibleResolution([1, 2, 2, 1], 6)
        res4 = FlexibleResolution([1, 2, 2, 1], 6)
        @test res3 == res4
        @test hash(res3) == hash(res4)
        
        # Test that different objects have different hashes
        res5 = UniformResolution(2, 6)
        @test res1 != res5
        
        # Test default constructor
        default1 = UniformResolution()
        default2 = UniformResolution()
        @test default1 == default2
        @test hash(default1) == hash(default2)
    end
    
    @testset "Using as Dictionary Keys" begin
        # Test that resolutions can be used as Dict keys
        res1 = UniformResolution(3, 9)
        res2 = UniformResolution(3, 9)
        res3 = UniformResolution(2, 6)
        
        dict = Dict{UniformResolution, String}()
        dict[res1] = "first"
        @test haskey(dict, res2)
        @test dict[res2] == "first"
        
        dict[res3] = "second"
        @test dict[res1] == "first"
        @test dict[res3] == "second"
        @test length(dict) == 2
    end
    
    @testset "Using in Sets" begin
        # Test that resolutions can be used in Sets
        res1 = UniformResolution(3, 9)
        res2 = UniformResolution(3, 9)
        res3 = UniformResolution(2, 6)
        
        resolution_set = Set{UniformResolution}([res1, res3])
        @test res1 in resolution_set
        @test res2 in resolution_set
        @test res3 in resolution_set
        @test length(resolution_set) == 2
    end
end

function test_can_span_subperiods()
    @testset "can_span_subperiods" begin
        @testset "Basic Cases - Valid" begin
            # Simple case: blocks sum exactly to target
            @test can_span_subperiods([1, 1, 1], 1) == true
            @test can_span_subperiods([2, 2, 2], 2) == true
            @test can_span_subperiods([3, 3, 3], 3) == true
            
            # Multiple subperiods
            @test can_span_subperiods([2, 2, 2, 2], 2) == true  # 4 subperiods of length 2
            @test can_span_subperiods([3, 3, 3, 3], 6) == true  # 2 subperiods of length 6
            
            # Variable block lengths that sum correctly
            @test can_span_subperiods([1, 2, 1], 4) == true  # 1+2+1 = 4
            @test can_span_subperiods([2, 3, 2], 7) == true  # 2+3+2 = 7
            @test can_span_subperiods([1, 1, 1, 1], 2) == true  # (1+1) + (1+1) = 2+2
        end
        
        @testset "Complex Cases - Valid" begin
            # Example from docstring: [1,2,2,1] can span subperiods of length 6
            @test can_span_subperiods([1, 2, 2, 1], 6) == true  # (1+2+2+1) = 6
            
            # Multiple subperiods with variable blocks
            # [24, 24, 24, 24, 48, 24] can span subperiods of length 168
            # First subperiod: 24+24+24+24+48+24 = 168
            @test can_span_subperiods([24, 24, 24, 24, 48, 24], 168) == true
            
            # Multiple subperiods
            block_lengths = [24, 24, 24, 24, 48, 24, 24, 24, 24, 48, 24, 24]
            @test can_span_subperiods(block_lengths, 168) == true  # Two subperiods of 168
            
            # Blocks that form multiple subperiods
            @test can_span_subperiods([1, 1, 1, 1, 1, 1], 3) == true  # (1+1+1) + (1+1+1) = 3+3
        end
        
        @testset "Edge Cases - Valid" begin
            # Single block equals target
            @test can_span_subperiods([10], 10) == true
            
            # Single subperiod with many blocks
            @test can_span_subperiods([1, 2, 3, 4, 5], 15) == true
            
            # Large numbers
            @test can_span_subperiods([168], 168) == true
            @test can_span_subperiods([24, 24, 24, 24, 24, 24, 24], 168) == true
        end
        
        @testset "Invalid Cases" begin
            # Blocks don't sum to target
            @test can_span_subperiods([1, 1, 1], 2) == false  # Can't form 2 from [1,1,1]
            @test can_span_subperiods([2, 2, 2], 5) == false  # Can't form 5 from [2,2,2]
            @test can_span_subperiods([3, 3, 3], 7) == false  # Can't form 7 from [3,3,3]
            
            # Sum exceeds target
            @test can_span_subperiods([5, 5], 7) == false  # 5+5=10 > 7, can't form exactly 7
            
            # Blocks don't align properly for multiple subperiods
            @test can_span_subperiods([1, 2, 1, 1], 3) == false  # (1+2) = 3, but then (1+1) = 2 ≠ 3
            @test can_span_subperiods([2, 1, 1, 1], 3) == false  # (2+1) = 3, but then (1+1) = 2 ≠ 3
            @test can_span_subperiods([24, 12, 12, 12], 48) == false # 24+12+12 = 48, but then 12 remains < 48
            
            # Remaining blocks don't form complete subperiod
            @test can_span_subperiods([3, 3, 2], 6) == false  # (3+3) = 6, but then 2 remains < 6

            # Large numbers
            @test can_span_subperiods([120, 25, 12], 168) == false # 120+25+12 = 157 < 168
        end
        
        @testset "Empty and Special Cases" begin
            # Empty blocks
            @test_throws ErrorException can_span_subperiods(Int[], 0)  # Empty case
            @test_throws ErrorException can_span_subperiods(Int[], 1)  # Can't form 1 from empty
            
            # Target is 0
            @test_throws ErrorException can_span_subperiods([0], 0)  # Edge case (though 0 blocks shouldn't happen in practice)
        end
    end
end

function test_validate_time_resolution()
    @testset "validate_time_resolution" begin
        @testset "Integer Resolution - Valid Cases" begin
            # time_steps_per_subperiod is divisible by resolution
            time_res = Dict(:Electricity => 1, :NaturalGas => 24)
            @test_nowarn validate_time_resolution(time_res, 168)  # 168 % 1 == 0, 168 % 24 == 0
            
            time_res2 = Dict(:Electricity => 2)
            @test_nowarn validate_time_resolution(time_res2, 168)  # 168 % 2 == 0
            
            time_res3 = Dict(:Electricity => 24)
            @test_nowarn validate_time_resolution(time_res3, 168)  # 168 % 24 == 0
        end
        
        @testset "Integer Resolution - Invalid Cases" begin
            # time_steps_per_subperiod is not divisible by resolution
            time_res = Dict(:Electricity => 5)
            @test_throws ErrorException validate_time_resolution(time_res, 168)  # 168 % 5 != 0
            
            time_res2 = Dict(:Electricity => 10)
            @test_throws ErrorException validate_time_resolution(time_res2, 168)  # 168 % 10 != 0
            
            time_res3 = Dict(:Electricity => 13)
            @test_throws ErrorException validate_time_resolution(time_res3, 168)  # 168 % 13 != 0
        end
        
        @testset "Integer Resolution - Error Cases" begin
            # Zero or negative resolution
            time_res_zero = Dict(:Electricity => 0)
            @test_throws AssertionError validate_time_resolution(time_res_zero, 168)
            
            time_res_neg = Dict(:Electricity => -1)
            @test_throws AssertionError validate_time_resolution(time_res_neg, 168)
        end
        
        @testset "Vector Resolution - Valid Cases" begin
            # Blocks can span subperiods
            time_res = Dict(:Electricity => [24, 24, 24, 24, 48, 24])
            @test_nowarn validate_time_resolution(time_res, 168)  # Can span 168
            
            time_res2 = Dict(:Electricity => [1, 2, 2, 1])
            @test_nowarn validate_time_resolution(time_res2, 6)  # Can span 6
            
            time_res3 = Dict(:Electricity => [1, 1, 1, 1])
            @test_nowarn validate_time_resolution(time_res3, 2)  # Can span 2 (multiple times)
        end
        
        @testset "Vector Resolution - Invalid Cases" begin
            # Blocks cannot span subperiods
            time_res = Dict(:Electricity => [1, 1, 1])
            @test_throws ErrorException validate_time_resolution(time_res, 2)  # Can't span 2
            
            time_res2 = Dict(:Electricity => [2, 2, 2])
            @test_throws ErrorException validate_time_resolution(time_res2, 5)  # Can't span 5
        end
        
        @testset "Vector Resolution - Error Cases" begin
            # Zero or negative block lengths
            time_res_zero = Dict(:Electricity => [0, 1, 2])
            @test_throws AssertionError validate_time_resolution(time_res_zero, 3)
            
            time_res_neg = Dict(:Electricity => [-1, 2, 3])
            @test_throws AssertionError validate_time_resolution(time_res_neg, 4)
            
            time_res_mixed = Dict(:Electricity => [1, 0, -1, 2])
            @test_throws AssertionError validate_time_resolution(time_res_mixed, 2)
        end
        
        @testset "Mixed Resolution Types" begin
            # Mix of integer and vector resolutions
            time_res_mixed = Dict(
                :Electricity => 24,  # Integer
                :NaturalGas => [24, 24, 24, 24, 48, 24]  # Vector
            )
            @test_nowarn validate_time_resolution(time_res_mixed, 168)

            time_res_mixed2 = Dict(
                :Electricity => [12, 12, 24, 12],
                :NaturalGas => 25
            )
            @test_throws ErrorException validate_time_resolution(time_res_mixed2, 24)

            time_res_mixed3 = Dict(
                :Electricity => [12, 12, 24, 12],
                :NaturalGas => [25, 25]
            )
            @test_throws ErrorException validate_time_resolution(time_res_mixed3, 70)
            @test_throws ErrorException validate_time_resolution(time_res_mixed3, 24)
        end
    end
end

function test_validate_temporal_resolution()
    @testset "validate_temporal_resolution" begin
        @testset "UniformResolution - Always Valid" begin
            # For now, UniformResolution should always pass (no validation needed)
            uniform_res = UniformResolution(24, 8760)
            @test_nowarn validate_temporal_resolution(8760, uniform_res)
            
            uniform_res2 = UniformResolution(1, 100)
            @test_nowarn validate_temporal_resolution(100, uniform_res2)
            
            # Even if period_length doesn't match, UniformResolution doesn't check
            uniform_res3 = UniformResolution(24, 8760)
            @test_nowarn validate_temporal_resolution(1000, uniform_res3)  # Different period_length, but no error
        end
        
        @testset "FlexibleResolution - Valid Cases" begin
            # Sum of block_lengths equals period_length
            flexible_res = FlexibleResolution([1, 2, 2, 1], 6)
            @test_nowarn validate_temporal_resolution(6, flexible_res)
            
            flexible_res2 = FlexibleResolution([24, 24, 24, 24, 48, 24], 168)
            @test_nowarn validate_temporal_resolution(168, flexible_res2)
            
            flexible_res3 = FlexibleResolution([1, 3, 4, 6, 7], 21)
            @test_nowarn validate_temporal_resolution(21, flexible_res3)
        end
        
        @testset "FlexibleResolution - Invalid Cases" begin
            # Sum of block_lengths does not equal period_length
            flexible_res = FlexibleResolution([1, 2, 2, 1], 6)
            @test_throws ErrorException validate_temporal_resolution(7, flexible_res)  # 6 != 7
            
            flexible_res2 = FlexibleResolution([24, 24, 24], 72)
            @test_throws ErrorException validate_temporal_resolution(100, flexible_res2)  # 72 != 100
            
            flexible_res3 = FlexibleResolution([1, 1, 1], 3)
            @test_throws ErrorException validate_temporal_resolution(4, flexible_res3)  # 3 != 4
        end
    end
end

function test_create_subperiods()
    @testset "create_subperiods" begin
        @testset "UniformResolution - Basic Cases" begin
            # Simple case: block_length=24, time_steps_per_subperiod=168, num_subperiods=2
            time_data = Dict(
                :NumberOfSubperiods => 2,
                :TimeStepsPerSubperiod => 168
            )
            resolution = UniformResolution(24, 336)  # 2 * 168 = 336
            subperiods = create_subperiods(time_data, resolution)
            
            # Should have 2 subperiods, each with 7 timesteps (168/24 = 7)
            @test length(subperiods) == 2
            @test subperiods[1] == 1:7
            @test subperiods[2] == 8:14
            
            # Case: block_length=1, time_steps_per_subperiod=24, num_subperiods=3
            time_data2 = Dict(
                :NumberOfSubperiods => 3,
                :TimeStepsPerSubperiod => 24
            )
            resolution2 = UniformResolution(1, 72)  # 3 * 24 = 72
            subperiods2 = create_subperiods(time_data2, resolution2)
            
            @test length(subperiods2) == 3
            @test subperiods2[1] == 1:24
            @test subperiods2[2] == 25:48
            @test subperiods2[3] == 49:72
        end
        
        @testset "UniformResolution - Weekly Subperiods" begin
            # Weekly subperiods: 52 weeks, 168 hours per week, 24-hour blocks
            time_data = Dict(
                :NumberOfSubperiods => 52,
                :TimeStepsPerSubperiod => 168
            )
            resolution = UniformResolution(24, 52 * 168)  # 8760 hours
            subperiods = create_subperiods(time_data, resolution)
            
            @test length(subperiods) == 52
            @test subperiods[1] == 1:7  # First week: 7 days
            @test subperiods[2] == 8:14  # Second week: 7 days
            @test length(subperiods[1]) == 7  # Each subperiod has 7 timesteps (168/24)
        end
        
        @testset "UniformResolution - Error Cases" begin
            # time_steps_per_subperiod not divisible by block_length
            time_data = Dict(
                :NumberOfSubperiods => 2,
                :TimeStepsPerSubperiod => 168
            )
            resolution = UniformResolution(25, 336)  # 168 % 25 != 0
            @test_throws ErrorException create_subperiods(time_data, resolution)
            
            time_data2 = Dict(
                :NumberOfSubperiods => 2,
                :TimeStepsPerSubperiod => 100
            )
            resolution2 = UniformResolution(30, 200)  # 100 % 30 != 0
            @test_throws ErrorException create_subperiods(time_data2, resolution2)
        end
        
        @testset "FlexibleResolution - Basic Cases" begin
            # Simple case: blocks [24, 24, 24, 24, 48, 24] = 168, one subperiod
            time_data = Dict(
                :NumberOfSubperiods => 1,
                :TimeStepsPerSubperiod => 168
            )
            resolution = FlexibleResolution([24, 24, 24, 24, 48, 24], 168)
            subperiods = create_subperiods(time_data, resolution)
            
            @test length(subperiods) == 1
            @test subperiods[1] == 1:6  # All 6 blocks in first subperiod
            
            # Two subperiods: [24, 24, 24, 24, 48, 24, 24, 24, 24, 48, 24, 24] = 336
            time_data2 = Dict(
                :NumberOfSubperiods => 2,
                :TimeStepsPerSubperiod => 168
            )
            resolution2 = FlexibleResolution([24, 24, 24, 24, 48, 24, 24, 24, 24, 48, 24, 24], 336)
            subperiods2 = create_subperiods(time_data2, resolution2)
            
            @test length(subperiods2) == 2
            @test subperiods2[1] == 1:6  # First 6 blocks = 168
            @test subperiods2[2] == 7:12  # Next 6 blocks = 168
        end
        
        @testset "FlexibleResolution - Variable Block Lengths" begin
            # Example: [1, 2, 2, 1] = 6, one subperiod
            time_data = Dict(
                :NumberOfSubperiods => 1,
                :TimeStepsPerSubperiod => 6
            )
            resolution = FlexibleResolution([1, 2, 2, 1], 6)
            subperiods = create_subperiods(time_data, resolution)
            
            @test length(subperiods) == 1
            @test subperiods[1] == 1:4  # All 4 blocks
            
            # Multiple subperiods with variable blocks
            # [1, 2, 2, 1, 1, 2, 2, 1] = 12, two subperiods of 6
            time_data2 = Dict(
                :NumberOfSubperiods => 2,
                :TimeStepsPerSubperiod => 6
            )
            resolution2 = FlexibleResolution([1, 2, 2, 1, 1, 2, 2, 1], 12)
            subperiods2 = create_subperiods(time_data2, resolution2)
            
            @test length(subperiods2) == 2
            @test subperiods2[1] == 1:4  # First 4 blocks = 6
            @test subperiods2[2] == 5:8  # Next 4 blocks = 6
        end
        
        @testset "FlexibleResolution - Complex Mapping" begin
            # Blocks that don't align perfectly with subperiod boundaries
            # This tests the cumulative time mapping logic
            time_data = Dict(
                :NumberOfSubperiods => 2,
                :TimeStepsPerSubperiod => 10
            )
            # Blocks: [3, 3, 4, 3, 3, 4] = 20
            # Cumulative: [3, 6, 10, 13, 16, 20]
            # Subperiod 1: 1:10 -> blocks 1:3 (cumulative 3, 6, 10)
            # Subperiod 2: 11:20 -> blocks 4:6 (cumulative 13, 16, 20)
            resolution = FlexibleResolution([3, 3, 4, 3, 3, 4], 20)
            subperiods = create_subperiods(time_data, resolution)
            
            @test length(subperiods) == 2
            @test subperiods[1] == 1:3  # Blocks 1-3 cover 1:10
            @test subperiods[2] == 4:6  # Blocks 4-6 cover 11:20
        end
    end
end

function test_find_common_time_intervals()
    @testset "find_common_time_intervals" begin
        @testset "Single Resolution" begin
            # Single UniformResolution
            uniform_res = UniformResolution(3, 9)
            common = find_common_time_intervals(uniform_res, 9)
            @test common == [1:3, 4:6, 7:9]
            
            # Single FlexibleResolution
            flexible_res = FlexibleResolution([1, 2, 2, 1], 6)
            common2 = find_common_time_intervals(flexible_res, 6)
            @test common2 == [1:1, 2:3, 4:5, 6:6]
        end
        
        @testset "Two Resolutions - Example from Docstring" begin
            # Example from docstring: UniformResolution(3, 6) and FlexibleResolution([1,2,2,1], 6)
            uniform_res = UniformResolution(3, 6)
            flexible_res = FlexibleResolution([1, 2, 2, 1], 6)
            
            # Uniform boundaries: [1, 4, 7] (blocks at 1:3, 4:6)
            # Flexible boundaries: [1, 2, 4, 6, 7] (blocks at 1:1, 2:3, 4:5, 6:6)
            # Common boundaries: [1, 4, 7] (intersection)
            common = find_common_time_intervals(uniform_res, flexible_res, 6)
            @test common == [1:3, 4:6]
            
            # Test with vector input
            common_vec = find_common_time_intervals([uniform_res, flexible_res], 6)
            @test common_vec == [1:3, 4:6]
        end
        
        @testset "Two Uniform Resolutions" begin
            # UniformResolution(2, 12) and UniformResolution(3, 12)
            res1 = UniformResolution(2, 12)
            res2 = UniformResolution(3, 12)
            
            # res1 boundaries: [1, 3, 5, 7, 9, 11, 13] (blocks of 2)
            # res2 boundaries: [1, 4, 7, 10, 13] (blocks of 3)
            # Common boundaries: [1, 7, 13] (intersection)
            common = find_common_time_intervals(res1, res2, 12)
            @test common == [1:6, 7:12]
            
            # UniformResolution(2, 12) and UniformResolution(4, 12)
            res3 = UniformResolution(4, 12)
            common2 = find_common_time_intervals(res1, res3, 12)
            # res1 boundaries: [1, 3, 5, 7, 9, 11, 13]
            # res3 boundaries: [1, 5, 9, 13]
            # Common boundaries: [1, 5, 9, 13]
            @test common2 == [1:4, 5:8, 9:12]
        end
        
        @testset "Two Flexible Resolutions" begin
            # FlexibleResolution([1, 2, 1], 4) and FlexibleResolution([2, 2], 4)
            res1 = FlexibleResolution([1, 2, 1], 4)
            res2 = FlexibleResolution([2, 2], 4)
            
            # res1 boundaries: [1, 2, 4, 5] (blocks at 1:1, 2:3, 4:4)
            # res2 boundaries: [1, 3, 5] (blocks at 1:2, 3:4)
            # Common boundaries: [1, 5]
            common = find_common_time_intervals(res1, res2, 4)
            @test common == [1:4]
            
            # FlexibleResolution([2, 3, 2], 7) and FlexibleResolution([1, 2, 2, 2], 7)
            res3 = FlexibleResolution([2, 3, 2], 7)
            res4 = FlexibleResolution([1, 2, 2, 2], 7)
            
            # res3 boundaries: [1, 3, 6, 8] (blocks at 1:2, 3:5, 6:7)
            # res4 boundaries: [1, 2, 4, 6, 8] (blocks at 1:1, 2:3, 4:5, 6:7)
            # Common boundaries: [1, 6, 8]
            common2 = find_common_time_intervals(res3, res4, 7)
            @test common2 == [1:5, 6:7]
        end
        
        @testset "Multiple Resolutions" begin
            # Three resolutions
            res1 = UniformResolution(2, 12)
            res2 = UniformResolution(3, 12)
            res3 = UniformResolution(4, 12)
            
            # res1 boundaries: [1, 3, 5, 7, 9, 11, 13]
            # res2 boundaries: [1, 4, 7, 10, 13]
            # res3 boundaries: [1, 5, 9, 13]
            # Common boundaries: [1, 13] (only start and end)
            common = find_common_time_intervals([res1, res2, res3], 12)
            @test common == [1:12]
            
            # Four resolutions with some common boundaries
            res4 = UniformResolution(6, 12)
            # res4 boundaries: [1, 7, 13]
            # Common boundaries: [1, 7, 13]
            common2 = find_common_time_intervals([res1, res2, res4], 12)
            @test common2 == [1:6, 7:12]
        end
        
        @testset "Edge Cases" begin
            # Same resolution twice
            res = UniformResolution(3, 9)
            common = find_common_time_intervals(res, res, 9)
            @test common == [1:3, 4:6, 7:9]
            
            # One resolution is a subset of another
            res1 = UniformResolution(1, 6)  # Every timestep
            res2 = UniformResolution(3, 6)  # Blocks of 3
            common = find_common_time_intervals(res1, res2, 6)
            # res1 boundaries: [1, 2, 3, 4, 5, 6, 7]
            # res2 boundaries: [1, 4, 7]
            # Common: [1, 4, 7]
            @test common == [1:3, 4:6]
            
            # Period length smaller than sum of blocks
            flexible_res = FlexibleResolution([10, 10, 10], 30)
            uniform_res = UniformResolution(5, 20)
            common = find_common_time_intervals(flexible_res, uniform_res, 20)
            # flexible boundaries: [1, 11, 21, 31] but limited to 20
            # uniform boundaries: [1, 6, 11, 16, 21]
            # Common: [1, 11, 21]
            @test common == [1:10, 11:20]
        end
        
        @testset "Error Cases" begin
            # Zero or negative total_timesteps
            res = UniformResolution(3, 6)
            @test_throws AssertionError find_common_time_intervals(res, 0)
            @test_throws AssertionError find_common_time_intervals(res, -1)
            
            # total_timesteps > sum of block_lengths for FlexibleResolution
            flexible_res = FlexibleResolution([1, 2, 2, 1], 6)
            @test_throws AssertionError find_common_time_intervals(flexible_res, 10)
        end
    end
end

function test_map_time_steps_to_common_time_intervals()
    @testset "map_time_steps_to_common_time_intervals" begin
        @testset "Example from Docstring" begin
            uniform_res = UniformResolution(3, 6)
            flexible_res = FlexibleResolution([1, 2, 2, 1], 6)
            common_intervals = find_common_time_intervals(uniform_res, flexible_res, 6)
            @test common_intervals == [1:3, 4:6]
            
            # Map uniform resolution
            uniform_mapping = map_time_steps_to_common_time_intervals(uniform_res, common_intervals)
            # Common interval 1:3 maps to uniform block 1 (covers 1:3)
            # Common interval 4:6 maps to uniform block 2 (covers 4:6)
            @test uniform_mapping == [[1], [2]]
            
            # Map flexible resolution
            flexible_mapping = map_time_steps_to_common_time_intervals(flexible_res, common_intervals)
            # Common interval 1:3 overlaps with flexible blocks 1 (1:1) and 2 (2:3)
            # Common interval 4:6 overlaps with flexible blocks 3 (4:5) and 4 (6:6)
            @test flexible_mapping == [[1, 2], [3, 4]]
        end
        
        @testset "UniformResolution - Basic Cases" begin
            # UniformResolution(2, 8) with common intervals [1:4, 5:8]
            uniform_res = UniformResolution(2, 8)
            common_intervals = [1:4, 5:8]
            mapping = map_time_steps_to_common_time_intervals(uniform_res, common_intervals)
            # Interval 1:4 overlaps with blocks 1 (1:2) and 2 (3:4)
            # Interval 5:8 overlaps with blocks 3 (5:6) and 4 (7:8)
            @test mapping == [[1, 2], [3, 4]]
            
            # UniformResolution(4, 12) with common intervals [1:4, 5:8, 9:12]
            uniform_res2 = UniformResolution(4, 12)
            common_intervals2 = [1:4, 5:8, 9:12]
            mapping2 = map_time_steps_to_common_time_intervals(uniform_res2, common_intervals2)
            # Each interval maps to exactly one block
            @test mapping2 == [[1], [2], [3]]
        end
        
        @testset "UniformResolution - Partial Overlaps" begin
            # UniformResolution(3, 12) with common intervals [1:5, 6:10, 11:12]
            uniform_res = UniformResolution(3, 12)
            common_intervals = [1:5, 6:10, 11:12]
            mapping = map_time_steps_to_common_time_intervals(uniform_res, common_intervals)
            # Interval 1:5 overlaps with blocks 1 (1:3) and 2 (4:6)
            # Interval 6:10 overlaps with blocks 2 (4:6) and 3 (7:9) and 4 (10:12)
            # Interval 11:12 overlaps with block 4 (10:12)
            @test mapping == [[1, 2], [2, 3, 4], [4]]
        end
        
        @testset "FlexibleResolution - Basic Cases" begin
            # FlexibleResolution([2, 3, 2], 7) with common intervals [1:5, 6:7]
            flexible_res = FlexibleResolution([2, 3, 2], 7)
            common_intervals = [1:5, 6:7]
            mapping = map_time_steps_to_common_time_intervals(flexible_res, common_intervals)
            # Interval 1:5 overlaps with blocks 1 (1:2) and 2 (3:5)
            # Interval 6:7 overlaps with block 3 (6:7)
            @test mapping == [[1, 2], [3]]
            
            # FlexibleResolution([1, 2, 2, 1], 6) with common intervals [1:3, 4:6]
            flexible_res2 = FlexibleResolution([1, 2, 2, 1], 6)
            common_intervals2 = [1:3, 4:6]
            mapping2 = map_time_steps_to_common_time_intervals(flexible_res2, common_intervals2)
            # Interval 1:3 overlaps with blocks 1 (1:1), 2 (2:3)
            # Interval 4:6 overlaps with blocks 3 (4:5), 4 (6:6)
            @test mapping2 == [[1, 2], [3, 4]]
        end
        
        @testset "FlexibleResolution - Complex Overlaps" begin
            # FlexibleResolution([3, 3, 4, 3, 3, 4], 20) with common intervals [1:10, 11:20]
            flexible_res = FlexibleResolution([3, 3, 4, 3, 3, 4], 20)
            common_intervals = [1:10, 11:20]
            mapping = map_time_steps_to_common_time_intervals(flexible_res, common_intervals)
            # Blocks: 1 (1:3), 2 (4:6), 3 (7:10), 4 (11:13), 5 (14:16), 6 (17:20)
            # Interval 1:10 overlaps with blocks 1, 2, 3
            # Interval 11:20 overlaps with blocks 4, 5, 6
            @test mapping == [[1, 2, 3], [4, 5, 6]]
        end
        
        @testset "Multiple Common Intervals" begin
            # UniformResolution(2, 12) and UniformResolution(3, 12)
            res1 = UniformResolution(2, 12)
            res2 = UniformResolution(3, 12)
            common_intervals = find_common_time_intervals(res1, res2, 12)
            @test common_intervals == [1:6, 7:12]
            
            # Map res1 (block_length=2)
            mapping1 = map_time_steps_to_common_time_intervals(res1, common_intervals)
            # Interval 1:6 overlaps with blocks 1, 2, 3
            # Interval 7:12 overlaps with blocks 4, 5, 6
            @test mapping1 == [[1, 2, 3], [4, 5, 6]]
            
            # Map res2 (block_length=3)
            mapping2 = map_time_steps_to_common_time_intervals(res2, common_intervals)
            # Interval 1:6 overlaps with blocks 1, 2
            # Interval 7:12 overlaps with blocks 3, 4
            @test mapping2 == [[1, 2], [3, 4]]
        end
        
        @testset "Single Block Intervals" begin
            # When common intervals align exactly with resolution blocks
            uniform_res = UniformResolution(3, 9)
            common_intervals = [1:3, 4:6, 7:9]
            mapping = map_time_steps_to_common_time_intervals(uniform_res, common_intervals)
            # Each interval maps to exactly one block
            @test mapping == [[1], [2], [3]]
            
            flexible_res = FlexibleResolution([3, 3, 3], 9)
            mapping2 = map_time_steps_to_common_time_intervals(flexible_res, common_intervals)
            @test mapping2 == [[1], [2], [3]]
        end
        
        @testset "Empty Common Intervals" begin
            uniform_res = UniformResolution(3, 9)
            empty_intervals = UnitRange{Int}[]
            mapping = map_time_steps_to_common_time_intervals(uniform_res, empty_intervals)
            @test mapping == []
        end
        
        @testset "Non-Overlapping Intervals" begin
            # Common intervals that don't overlap with resolution blocks
            # This shouldn't happen in practice, but test the behavior
            uniform_res = UniformResolution(3, 9)
            # Resolution blocks: 1:3, 4:6, 7:9
            # Common interval: 10:12 (outside resolution)
            common_intervals = [10:12]
            mapping = map_time_steps_to_common_time_intervals(uniform_res, common_intervals)
            # Should return empty for blocks that don't overlap
            @test mapping == [[]]
        end

        @testset "Integration Test with Find Common Time Intervals" begin
            uniform_res = UniformResolution(24, 8760)
            flexible_res = FlexibleResolution([672, 1344, 1344, 5376, 24], 8760)
            common_intervals = find_common_time_intervals(uniform_res, flexible_res, 8760)
            mapping = map_time_steps_to_common_time_intervals(uniform_res, common_intervals)
            @test mapping[1] == [i for i in 1:Int(672/24)]
            @test mapping[2] == [i for i in Int(672/24)+1:Int((1344+672)/24)]
            @test mapping[3] == [i for i in Int((1344+672)/24)+1:Int((1344+1344+672)/24)]
            @test mapping[4] == [i for i in Int((1344+1344+672)/24)+1:Int((5376+1344+1344+672)/24)]
            @test mapping[5] == [i for i in Int((5376+1344+1344+672)/24)+1:Int(8760/24)]
        end
    end
end

function test_update_time_intervals_in_balance_equations()
    @testset "update_time_intervals_in_balance_equations!" begin
        @testset "Single Balance ID with Specific Edges" begin
            # Create a transformation with UniformResolution
            transform = Transformation(
                id=:transform1,
                timedata=TimeData(
                    resolution=UniformResolution(3, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                balance_time_intervals=Dict{Symbol,Vector{UnitRange{Int}}}()
            )
            
            # Create edges with different resolutions
            node1 = Node{Electricity}(id=:node1, timedata=TimeData(
                resolution=UniformResolution(1, 12),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            node2 = Node{Electricity}(id=:node2, timedata=TimeData(
                resolution=UniformResolution(1, 12),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            edge1 = Edge{Electricity}(
                id=:edge1,
                timedata=TimeData(
                    resolution=UniformResolution(2, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=transform
            )
            
            edge2 = Edge{Electricity}(
                id=:edge2,
                timedata=TimeData(
                    resolution=UniformResolution(3, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=transform,
                end_vertex=node2
            )
            
            # Without balance_data
            update_time_intervals_in_balance_equations!(transform, [edge1, edge2])
            @test isempty(transform.balance_time_intervals)

            # Test updating with specific balance_id and edges
            transform.balance_data = Dict(:balance1 => Dict(:edge1 => 1.0, :edge2 => -1.0))
            update_time_intervals_in_balance_equations!(transform, :balance1, [edge1, edge2])
            
            # Common intervals between UniformResolution(2, 12) and UniformResolution(3, 12) should be [1:6, 7:12]
            @test haskey(transform.balance_time_intervals, :balance1)
            @test transform.balance_time_intervals[:balance1] == [1:6, 7:12]

            # Test again without specific balance_id
            empty!(transform.balance_time_intervals)
            update_time_intervals_in_balance_equations!(transform, [edge1, edge2])
            @test haskey(transform.balance_time_intervals, :balance1)
            @test transform.balance_time_intervals[:balance1] == [1:6, 7:12]
        end
        
        @testset "Multiple Balance IDs with Edge Filtering" begin
            # Create transformation with balance_data
            transform = Transformation(
                id=:transform2,
                timedata=TimeData(
                    resolution=UniformResolution(3, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                balance_data=Dict(
                    :balance1 => Dict(:edge1 => 1.0, :edge2 => -1.0),
                    :balance2 => Dict(:edge3 => 2.0, :edge4 => -2.0)
                ),
                balance_time_intervals=Dict{Symbol,Vector{UnitRange{Int}}}()
            )
            
            node1 = Node{Electricity}(id=:node1, timedata=TimeData(
                resolution=UniformResolution(1, 12),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            node2 = Node{Electricity}(id=:node2, timedata=TimeData(
                resolution=UniformResolution(1, 12),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            # Create edges for balance1
            edge1 = Edge{Electricity}(
                id=:edge1,
                timedata=TimeData(
                    resolution=UniformResolution(2, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=transform
            )
            
            edge2 = Edge{Electricity}(
                id=:edge2,
                timedata=TimeData(
                    resolution=UniformResolution(3, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=transform,
                end_vertex=node2
            )
            
            # Create edges for balance2
            edge3 = Edge{Electricity}(
                id=:edge3,
                timedata=TimeData(
                    resolution=UniformResolution(4, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=transform
            )
            
            edge4 = Edge{Electricity}(
                id=:edge4,
                timedata=TimeData(
                    resolution=UniformResolution(6, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=transform,
                end_vertex=node2
            )
            
            # Create an edge that doesn't participate in any balance
            edge5 = Edge{Electricity}(
                id=:edge5,
                timedata=TimeData(
                    resolution=UniformResolution(1, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=node2
            )
            
            all_edges = [edge1, edge2, edge3, edge4, edge5]
            
            # Update all balance IDs
            update_time_intervals_in_balance_equations!(transform, all_edges)
            
            # Check balance1: edge1 (res=2) and edge2 (res=3) -> common: [1:6, 7:12]
            @test haskey(transform.balance_time_intervals, :balance1)
            @test transform.balance_time_intervals[:balance1] == [1:6, 7:12]
            
            # Check balance2: edge3 (res=4) and edge4 (res=6) -> common: [1:12]
            @test haskey(transform.balance_time_intervals, :balance2)
            @test transform.balance_time_intervals[:balance2] == [1:12]
        end
        
        @testset "FlexibleResolution Edges" begin
            transform = Transformation(
                id=:transform3,
                timedata=TimeData(
                    resolution=UniformResolution(3, 6),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                balance_data=Dict(:balance1 => Dict(:edge_flexible => 1.0, :edge_uniform => -1.0)),
                balance_time_intervals=Dict{Symbol,Vector{UnitRange{Int}}}()
            )
            
            node1 = Node{Electricity}(id=:node1, timedata=TimeData(
                resolution=UniformResolution(1, 6),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            node2 = Node{Electricity}(id=:node2, timedata=TimeData(
                resolution=UniformResolution(1, 6),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            # Example from docstring: UniformResolution(3, 6) and FlexibleResolution([1,2,2,1], 6)
            edge_flexible = Edge{Electricity}(
                id=:edge_flex,
                timedata=TimeData(
                    resolution=FlexibleResolution([1, 2, 2, 1], 6),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=node2
            )
            
            edge_uniform = Edge{Electricity}(
                id=:edge_unif,
                timedata=TimeData(
                    resolution=UniformResolution(3, 6),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=node2
            )
            
            update_time_intervals_in_balance_equations!(transform, :balance1, [edge_flexible, edge_uniform])
            
            # Common intervals should be [1:3, 4:6] as per docstring example
            @test haskey(transform.balance_time_intervals, :balance1)
            @test transform.balance_time_intervals[:balance1] == [1:3, 4:6]
        end
        
        @testset "Empty Balance Data" begin
            transform = Transformation(
                id=:transform4,
                timedata=TimeData(
                    resolution=UniformResolution(3, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                balance_data=Dict{Symbol,Dict{Symbol,Float64}}(),
                balance_time_intervals=Dict{Symbol,Vector{UnitRange{Int}}}()
            )
            
            node1 = Node{Electricity}(id=:node1, timedata=TimeData(
                resolution=UniformResolution(1, 12),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            node2 = Node{Electricity}(id=:node2, timedata=TimeData(
                resolution=UniformResolution(1, 12),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            edge1 = Edge{Electricity}(
                id=:edge1,
                timedata=TimeData(
                    resolution=UniformResolution(2, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=node2
            )
            
            # Should return nothing without error
            @test_nowarn update_time_intervals_in_balance_equations!(transform, [edge1])
            @test isempty(transform.balance_time_intervals)
        end
        
        @testset "Zero Coefficient Edges" begin
            transform = Transformation(
                id=:transform5,
                timedata=TimeData(
                    resolution=UniformResolution(3, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                balance_data=Dict(
                    :balance1 => Dict(:edge1 => 1.0, :edge2 => 0.0)  # edge2 has zero coefficient
                ),
                balance_time_intervals=Dict{Symbol,Vector{UnitRange{Int}}}()
            )
            
            node1 = Node{Electricity}(id=:node1, timedata=TimeData(
                resolution=UniformResolution(1, 12),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            node2 = Node{Electricity}(id=:node2, timedata=TimeData(
                resolution=UniformResolution(1, 12),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            edge1 = Edge{Electricity}(
                id=:edge1,
                timedata=TimeData(
                    resolution=UniformResolution(2, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=node2
            )
            
            edge2 = Edge{Electricity}(
                id=:edge2,
                timedata=TimeData(
                    resolution=UniformResolution(3, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=node2
            )
            
            # edge2 should not be included because it has zero coefficient
            update_time_intervals_in_balance_equations!(transform, [edge1, edge2])
            
            # Only edge1 participates, so balance_time_intervals should reflect only edge1's resolution
            # Since there's only one edge, common intervals are just edge1's intervals
            @test haskey(transform.balance_time_intervals, :balance1)
            # edge1 has UniformResolution(2, 12), so intervals are [1:2, 3:4, 5:6, 7:8, 9:10, 11:12]
            @test transform.balance_time_intervals[:balance1] == [1:2, 3:4, 5:6, 7:8, 9:10, 11:12]
        end
        
        @testset "No Participating Edges" begin
            transform = Transformation(
                id=:transform6,
                timedata=TimeData(
                    resolution=UniformResolution(3, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                balance_data=Dict(
                    :balance1 => Dict(:edge1 => 1.0)  # edge1 is in balance_data
                ),
                balance_time_intervals=Dict{Symbol,Vector{UnitRange{Int}}}()
            )
            
            node1 = Node{Electricity}(id=:node1, timedata=TimeData(
                resolution=UniformResolution(1, 12),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            node2 = Node{Electricity}(id=:node2, timedata=TimeData(
                resolution=UniformResolution(1, 12),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            # edge2 is not in balance_data, so it won't participate
            edge2 = Edge{Electricity}(
                id=:edge2,
                timedata=TimeData(
                    resolution=UniformResolution(2, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=node2
            )
            
            # Should not error, but balance1 should not be updated
            @test_nowarn update_time_intervals_in_balance_equations!(transform, [edge2])
            @test !haskey(transform.balance_time_intervals, :balance1)
        end
        
        @testset "Error Cases" begin
            transform = Transformation(
                id=:transform7,
                timedata=TimeData(
                    resolution=UniformResolution(3, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                balance_time_intervals=Dict{Symbol,Vector{UnitRange{Int}}}()
            )
            
            node1 = Node{Electricity}(id=:node1, timedata=TimeData(
                resolution=UniformResolution(1, 12),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            # Passing a non-Edge object should error
            @test_throws AssertionError update_time_intervals_in_balance_equations!(transform, :balance1, [node1])
        end
    end
end

function test_update_balance()
    @testset "update_balance!" begin
        @testset "Transformation Vertex - Uniform Resolutions" begin
            # Create a JuMP model
            model = Model()
            vref = @variable(model, vREF)
            
            # Create transformation with balance_time_intervals already set
            transform = Transformation(
                id=:transform1,
                timedata=TimeData(
                    resolution=UniformResolution(3, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                balance_data=Dict(:balance1 => Dict(:edge1 => 1.0, :edge2 => -1.0)),
                balance_time_intervals=Dict(:balance1 => [1:6, 7:12])  # Common intervals
            )
            
            # Initialize balance expression
            transform.operation_expr[:balance1] = @expression(model, [t in 1:2], 0 * vref)
            
            # Create edges with different resolutions
            node1 = Node{Electricity}(id=:node1, timedata=TimeData(
                resolution=UniformResolution(1, 12),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            edge1 = Edge{Electricity}(
                id=:edge1,
                timedata=TimeData(
                    resolution=UniformResolution(2, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=transform
            )
            
            edge2 = Edge{Electricity}(
                id=:edge2,
                timedata=TimeData(
                    resolution=UniformResolution(3, 12),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=transform,
                end_vertex=node1
            )
            
            # Create flow variables for edge1 (6 timesteps: 1:2, 3:4, 5:6, 7:8, 9:10, 11:12)
            flow1 = @variable(model, [1:6], base_name="flow1")
            flow1_array = JuMP.Containers.DenseAxisArray(flow1, 1:6)
            
            # Create flow variables for edge2 (4 timesteps: 1:3, 4:6, 7:9, 10:12)
            flow2 = @variable(model, [1:4], base_name="flow2")
            flow2_array = JuMP.Containers.DenseAxisArray(flow2, 1:4)
            
            # Update balance with edge1 (coeff = 1.0)
            # edge1 intervals map to common intervals: [[1, 2, 3], [4, 5, 6]]
            # So flow1[1:3] should be summed for interval 1, flow1[4:6] for interval 2
            update_balance!(edge1, transform, flow1_array, 1)
            
            # Update balance with edge2 (coeff = -1.0)
            # edge2 intervals map to common intervals: [[1], [2]]
            # So flow2[1] for interval 1, flow2[2] for interval 2
            update_balance!(edge2, transform, flow2_array, -1)
            
            # Check that balance expression was updated
            balance_expr = get_balance(transform, :balance1)
            @test length(balance_expr) == 2
            
            # The expressions should contain the flow variables
            @test balance_expr[1] == sum(flow1_array[t] for t in 1:3) + sum(flow2_array[t] for t in 1:2)
            @test balance_expr[2] == sum(flow1_array[t] for t in 4:6) + sum(flow2_array[t] for t in 3:4)
        end
        
        @testset "Transformation Vertex - Flexible Resolution" begin
            model = Model()
            vref = @variable(model, vREF)
            
            transform = Transformation(
                id=:transform2,
                timedata=TimeData(
                    resolution=UniformResolution(3, 6),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                balance_data=Dict(:balance1 => Dict(:edge_flex => 1.0)),
                balance_time_intervals=Dict(:balance1 => [1:3, 4:6])  # From docstring example
            )
            
            transform.operation_expr[:balance1] = @expression(model, [t in 1:2], 0 * vref)
            
            node1 = Node{Electricity}(id=:node1, timedata=TimeData(
                resolution=UniformResolution(1, 6),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            # FlexibleResolution edge: [1,2,2,1] -> intervals [1:1, 2:3, 4:5, 6:6]
            edge_flex = Edge{Electricity}(
                id=:edge_flex,
                timedata=TimeData(
                    resolution=FlexibleResolution([1, 2, 2, 1], 6),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=transform
            )
            
            # Flow for flexible edge (4 timesteps)
            flow_flex = @variable(model, [1:4], base_name="flow_flex")
            flow_flex_array = JuMP.Containers.DenseAxisArray(flow_flex, 1:4)
            
            # Update balance
            update_balance!(edge_flex, transform, flow_flex_array, 1)
            
            # Check balance expression
            balance_expr = get_balance(transform, :balance1)
            @test length(balance_expr) == 2
            @test balance_expr[1] == sum(flow_flex_array[t] for t in 1:2) * 1.0
            @test balance_expr[2] == sum(flow_flex_array[t] for t in 3:4) * 1.0
        end
        
        @testset "Non-Transformation Vertex (Node)" begin
            model = Model()
            vref = @variable(model, vREF)
            
            node = Node{Electricity}(
                id=:node1,
                timedata=TimeData(
                    resolution=UniformResolution(1, 6),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                balance_data=Dict(:demand => Dict(:edge1 => 1.0))
            )
            
            # Initialize balance expression (6 timesteps for hourly resolution)
            node.operation_expr[:demand] = @expression(model, [t in 1:6], 0 * vref)
            
            node2 = Node{Electricity}(id=:node2, timedata=TimeData(
                resolution=UniformResolution(1, 6),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            edge = Edge{Electricity}(
                id=:edge1,
                timedata=TimeData(
                    resolution=UniformResolution(1, 6),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node2,
                end_vertex=node
            )
            
            # Flow for edge (6 timesteps)
            flow = @variable(model, [1:6], base_name="flow")
            flow_array = JuMP.Containers.DenseAxisArray(flow, 1:6)
            
            # Update balance - should update each timestep directly
            update_balance!(edge, node, flow_array, 1)
            
            # Check balance expression
            balance_expr = get_balance(node, :demand)
            @test length(balance_expr) == 6
            for t in 1:6
                @test balance_expr[t] == flow_array[t] * 1.0
            end
        end
        
        @testset "Coefficient Sign" begin
            model = Model()
            vref = @variable(model, vREF)
            
            transform = Transformation(
                id=:transform3,
                timedata=TimeData(
                    resolution=UniformResolution(2, 6),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                balance_data=Dict(:balance1 => Dict(:edge1 => 1.0)),
                balance_time_intervals=Dict(:balance1 => [1:2, 3:4, 5:6])
            )
            
            transform.operation_expr[:balance1] = @expression(model, [t in 1:3], 0 * vref)
            
            node1 = Node{Electricity}(id=:node1, timedata=TimeData(
                resolution=UniformResolution(1, 6),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            edge = Edge{Electricity}(
                id=:edge1,
                timedata=TimeData(
                    resolution=UniformResolution(2, 6),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=transform
            )
            
            flow = @variable(model, [1:3], base_name="flow")
            flow_array = JuMP.Containers.DenseAxisArray(flow, 1:3)
            
            # Test with positive coefficient sign
            update_balance!(edge, transform, flow_array, 1)
            balance_expr_pos = get_balance(transform, :balance1)
            
            # Reset and test with negative coefficient sign
            transform.operation_expr[:balance1] = @expression(model, [t in 1:3], 0 * vref)
            update_balance!(edge, transform, flow_array, -1)
            balance_expr_neg = get_balance(transform, :balance1)
            
            # The expressions should be different (opposite signs)
            @test balance_expr_pos[1] != balance_expr_neg[1]
            @test balance_expr_pos[1] == -balance_expr_neg[1]

        end
        
        @testset "Multiple Balance IDs" begin
            model = Model()
            vref = @variable(model, vREF)
            
            transform = Transformation(
                id=:transform4,
                timedata=TimeData(
                    resolution=UniformResolution(2, 6),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                balance_data=Dict(
                    :balance1 => Dict(:edge1 => 1.0),
                    :balance2 => Dict(:edge1 => 2.0)
                ),
                balance_time_intervals=Dict(
                    :balance1 => [1:2, 3:4, 5:6],
                    :balance2 => [1:2, 3:4, 5:6]
                )
            )
            
            transform.operation_expr[:balance1] = @expression(model, [t in 1:3], 0 * vref)
            transform.operation_expr[:balance2] = @expression(model, [t in 1:3], 0 * vref)
            
            node1 = Node{Electricity}(id=:node1, timedata=TimeData(
                resolution=UniformResolution(1, 6),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            edge = Edge{Electricity}(
                id=:edge1,
                timedata=TimeData(
                    resolution=UniformResolution(2, 6),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=transform
            )
            
            flow = @variable(model, [1:3], base_name="flow")
            flow_array = JuMP.Containers.DenseAxisArray(flow, 1:3)
            
            # Update balance - should update both balance1 and balance2
            update_balance!(edge, transform, flow_array, 1)
            
            # Check both balance expressions were updated
            balance_expr1 = get_balance(transform, :balance1)
            balance_expr2 = get_balance(transform, :balance2)
            
            @test length(balance_expr1) == 3
            @test length(balance_expr2) == 3
            
            # Both should have been modified
            for t in 1:3
                @test balance_expr1[t] == flow_array[t] * 1.0
                @test balance_expr2[t] == flow_array[t] * 2.0
            end
        end
        
        @testset "Zero Coefficient Edge" begin
            model = Model()
            vref = @variable(model, vREF)
            
            transform = Transformation(
                id=:transform5,
                timedata=TimeData(
                    resolution=UniformResolution(2, 6),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                balance_data=Dict(:balance1 => Dict(:edge1 => 0.0)),  # Zero coefficient
                balance_time_intervals=Dict(:balance1 => [1:2, 3:4, 5:6])
            )
            
            transform.operation_expr[:balance1] = @expression(model, [t in 1:3], 0 * vref)
            
            node1 = Node{Electricity}(id=:node1, timedata=TimeData(
                resolution=UniformResolution(1, 6),
                period_index=1,
                subperiods=[],
                subperiod_indices=[],
                subperiod_weights=Dict{Int64,Float64}(),
                subperiod_map=Dict{Int64,Int64}()
            ))
            
            edge = Edge{Electricity}(
                id=:edge1,
                timedata=TimeData(
                    resolution=UniformResolution(2, 6),
                    period_index=1,
                    subperiods=[],
                    subperiod_indices=[],
                    subperiod_weights=Dict{Int64,Float64}(),
                    subperiod_map=Dict{Int64,Int64}()
                ),
                start_vertex=node1,
                end_vertex=transform
            )
            
            flow = @variable(model, [1:3], base_name="flow")
            flow_array = JuMP.Containers.DenseAxisArray(flow, 1:3)
            
            # Update balance with zero coefficient
            update_balance!(edge, transform, flow_array, 1)
            
            # Balance expression should remain unchanged
            balance_expr = get_balance(transform, :balance1)
            for t in 1:3
                # With zero coefficient, the expression should still be 0 * vref
                @test balance_expr[t] == 0 * vref || balance_expr[t] == AffExpr(0.0)
            end
        end
    end
end

function test_macro_time_series()
    @testset "MacroTimeSeries" begin
        @testset "Constructors" begin
            # Default constructor
            ts_default = MacroTimeSeries()
            @test ts_default.data == Float64[]
            @test ts_default.resolution == UniformResolution()
            @test ts_default.name == ""
            
            # Constructor with data and resolution
            data = [1.0, 2.0, 3.0, 4.0, 5.0]
            resolution = UniformResolution(1, 5)
            ts1 = MacroTimeSeries(data, resolution)
            @test ts1.data == data
            @test ts1.resolution == resolution
            @test ts1.name == ""
            
            # Constructor with data, resolution, and name
            ts2 = MacroTimeSeries(data, resolution, "test_series")
            @test ts2.data == data
            @test ts2.resolution == resolution
            @test ts2.name == "test_series"
            
            # Constructor with FlexibleResolution
            flex_data = [10.0, 20.0, 30.0]
            flex_res = FlexibleResolution([2, 3, 2], 7)
            ts3 = MacroTimeSeries(flex_data, flex_res, "flexible_series")
            @test ts3.data == flex_data
            @test ts3.resolution == flex_res
            @test ts3.name == "flexible_series"
            @test eltype(ts3.data) == Float64
            
            # Constructor with different numeric types
            int_data = [1, 2, 3, 4]
            ts4 = MacroTimeSeries(int_data, UniformResolution(1, 4))
            @test ts4.data == int_data
            @test eltype(ts4.data) == Int
        end
        
        @testset "Validation" begin
            # Valid: data length matches resolution time steps
            data = [1.0, 2.0, 3.0]
            resolution = UniformResolution(1, 3)
            @test_nowarn MacroTimeSeries(data, resolution)
            
            # Valid: single data point (special case)
            single_data = [42.0]
            @test_nowarn MacroTimeSeries(single_data, UniformResolution(1, 1))
            
            # Valid: FlexibleResolution
            flex_data = [1.0, 2.0, 3.0, 4.0]
            flex_res = FlexibleResolution([1, 2, 2, 1], 6)
            @test_nowarn MacroTimeSeries(flex_data, flex_res)
            
            # Invalid: data length doesn't match (should throw ErrorException)
            mismatched_data = [1.0, 2.0]
            @test_throws ErrorException MacroTimeSeries(mismatched_data, UniformResolution(1, 3))
            
            # Invalid: FlexibleResolution mismatch
            flex_data_wrong = [1.0, 2.0]  # Should be 4 elements for [1,2,2,1]
            @test_throws ErrorException MacroTimeSeries(flex_data_wrong, FlexibleResolution([1, 2, 2, 1], 6))
        end
        
        @testset "Vector-like Operations" begin
            data = [10.0, 20.0, 30.0, 40.0, 50.0]
            resolution = UniformResolution(1, 5)
            ts = MacroTimeSeries(data, resolution, "test")
            
            # length
            @test length(ts) == 5
            @test length(ts) == length(data)
            
            # size
            @test size(ts) == (5,)
            @test size(ts) == size(data)
            
            # getindex
            @test ts[1] == 10.0
            @test ts[2] == 20.0
            @test ts[5] == 50.0
            @test ts[1:3] == [10.0, 20.0, 30.0]
            
            # setindex!
            ts[1] = 100.0
            @test ts[1] == 100.0
            @test ts.data[1] == 100.0  # Should modify underlying data
            
            ts[2:3] = [200.0, 300.0]
            @test ts[2] == 200.0
            @test ts[3] == 300.0
            
            # iterate
            collected = collect(ts)
            @test collected == ts.data
            
            # Test iteration
            values = Float64[]
            for val in ts
                push!(values, val)
            end
            @test values == ts.data
        end
        
        @testset "Accessors" begin
            data = [1.0, 2.0, 3.0]
            resolution = UniformResolution(1, 3)
            name = "my_series"
            ts = MacroTimeSeries(data, resolution, name)
            
            # get_data
            @test get_data(ts) == data
            @test get_data(ts) === ts.data  # Should return the same reference
            
            # get_resolution
            @test get_resolution(ts) == resolution
            @test get_resolution(ts) === ts.resolution  # Should return the same reference
            
            # get_name
            @test get_name(ts) == name
            @test get_name(ts) == ts.name
        end
        
        @testset "make Function" begin
            data = [5.0, 10.0, 15.0]
            resolution = UniformResolution(1, 3)
            name = "created_series"
            
            ts = make(data, resolution, name)
            @test isa(ts, MacroTimeSeries)
            @test ts.data == data
            @test ts.resolution == resolution
            @test ts.name == name
            
            # make without name
            ts2 = make(data, resolution)
            @test ts2.data == data
            @test ts2.resolution == resolution
            @test ts2.name == ""
        end
        
        @testset "Different Resolution Types" begin
            # UniformResolution
            uniform_data = [1.0, 2.0, 3.0, 4.0]
            uniform_res = UniformResolution(2, 8)
            ts_uniform = MacroTimeSeries(uniform_data, uniform_res)
            @test get_resolution(ts_uniform) == uniform_res
            @test length(ts_uniform) == 4
            
            # FlexibleResolution
            flex_data = [10.0, 20.0, 30.0]
            flex_res = FlexibleResolution([2, 3, 2], 7)
            ts_flex = MacroTimeSeries(flex_data, flex_res)
            @test get_resolution(ts_flex) == flex_res
            @test length(ts_flex) == 3
        end
        
        @testset "Empty Time Series" begin
            # Empty data with default resolution
            ts_empty = MacroTimeSeries()
            @test isempty(ts_empty.data)
            @test length(ts_empty) == 0
            @test ts_empty.resolution == UniformResolution()
            
            # Empty data with specific resolution
            empty_data = Float64[]
            empty_res = UniformResolution(1, 0)
            ts_empty2 = MacroTimeSeries(empty_data, empty_res)
            @test isempty(ts_empty2.data)
            @test length(ts_empty2) == 0
        end
        
        @testset "Type Parameters" begin
            # Float64 data
            float_data = [1.5, 2.5, 3.5]
            ts_float = MacroTimeSeries(float_data, UniformResolution(1, 3))
            @test eltype(ts_float.data) == Float64
            
            # Int data
            int_data = [1, 2, 3]
            ts_int = MacroTimeSeries(int_data, UniformResolution(1, 3))
            @test eltype(ts_int.data) == Int
            
            # Type should be preserved
            @test typeof(ts_float) == MacroTimeSeries{Float64, UniformResolution}
            @test typeof(ts_int) == MacroTimeSeries{Int, UniformResolution}
        end
        
        @testset "Modification" begin
            data = [1.0, 2.0, 3.0]
            resolution = UniformResolution(1, 3)
            ts = MacroTimeSeries(data, resolution)
            
            # Modify via setindex!
            ts[1] = 100.0
            @test ts[1] == 100.0
            @test ts.data[1] == 100.0
            
            # Modify underlying data directly
            ts.data[2] = 200.0
            @test ts[2] == 200.0
            
            # Multiple modifications
            ts[1:3] = [10.0, 20.0, 30.0]
            @test ts.data == [10.0, 20.0, 30.0]
        end
        
        @testset "Edge Cases" begin
            # Single element
            single = MacroTimeSeries([42.0], UniformResolution(1, 1))
            @test length(single) == 1
            @test single[1] == 42.0
            
            # Large data
            large_data = collect(1.0:100.0)
            large_res = UniformResolution(1, 100)
            ts_large = MacroTimeSeries(large_data, large_res)
            @test length(ts_large) == 100
            @test ts_large[1] == 1.0
            @test ts_large[100] == 100.0
            
            # Zero values
            zero_data = [0.0, 0.0, 0.0]
            ts_zero = MacroTimeSeries(zero_data, UniformResolution(1, 3))
            @test all(x -> x == 0.0, ts_zero)
            
            # Negative values
            neg_data = [-1.0, -2.0, -3.0]
            ts_neg = MacroTimeSeries(neg_data, UniformResolution(1, 3))
            @test ts_neg[1] == -1.0
            @test ts_neg[3] == -3.0
        end
        
        @testset "Name Handling" begin
            # Empty name
            ts1 = MacroTimeSeries([1.0, 2.0], UniformResolution(1, 2), "")
            @test get_name(ts1) == ""
            
            # Named series
            ts2 = MacroTimeSeries([1.0, 2.0], UniformResolution(1, 2), "demand")
            @test get_name(ts2) == "demand"
            
            # Long name
            long_name = "very_long_time_series_name_with_many_words"
            ts3 = MacroTimeSeries([1.0], UniformResolution(1, 1), long_name)
            @test get_name(ts3) == long_name
        end
    end
end

function run_multi_resolution_tests()
    test_uniform_resolution()
    test_flexible_resolution()
    test_interface_functions()
    test_equivalence_tests()
    test_can_span_subperiods()
    test_validate_time_resolution()
    test_validate_temporal_resolution()
    test_create_subperiods()
    test_find_common_time_intervals()
    test_map_time_steps_to_common_time_intervals()
    test_update_time_intervals_in_balance_equations()
    test_update_balance()
    test_macro_time_series()
end

run_multi_resolution_tests()

end
