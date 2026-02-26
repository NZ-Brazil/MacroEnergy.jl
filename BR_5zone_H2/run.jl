using MacroEnergy
using Gurobi
using TimerOutputs
using JuMP

const to = TimerOutput()

peak_memory_gb = 0.0
peak_stage = ""

println("="^80)
println("MacroEnergy Performance Benchmark - Peak Memory Tracking")
println("="^80)

function track_peak_memory(stage::String)
    global peak_memory_gb, peak_stage
    
    GC.gc()  # Garbage collection execution
    
    current_mem_gb = Sys.maxrss() / 1024^3
    
    system_used_gb = (Sys.total_memory() - Sys.free_memory()) / 1024^3
    system_total_gb = Sys.total_memory() / 1024^3
    
    if current_mem_gb > peak_memory_gb
        peak_memory_gb = current_mem_gb
        peak_stage = stage
    end
    
    println("[$stage]")
    println("  Julia Process: $(round(current_mem_gb, digits=2)) GB (RSS)")
    println("  System Total:  $(round(system_used_gb, digits=2)) / $(round(system_total_gb, digits=2)) GB")
    println("  ** Peak so far: $(round(peak_memory_gb, digits=2)) GB at [$peak_stage]")
    
    return current_mem_gb
end

track_peak_memory("Initial")

local system, model, case

@timeit to "Total" begin
    
    @timeit to "Load case" begin
        println("\n[1/5] Loading case...")
        case = MacroEnergy.load_case(@__DIR__)
        track_peak_memory("After Load")
    end
    
    @timeit to "Generate model" begin
        println("\n[2/5] Generating model...")
        model = MacroEnergy.generate_model(case)
        track_peak_memory("After Generate")
        println("  ✓ Variables: $(num_variables(model))")
        println("  ✓ Constraints: $(num_constraints(model; count_variable_in_set_constraints=true))")
    end
    
    @timeit to "Set optimizer" begin
        println("\n[3/5] Setting optimizer...")
        set_optimizer(model, Gurobi.Optimizer)
        set_optimizer_attribute(model, "Method", 2)
        set_optimizer_attribute(model, "Crossover", 0)
        set_optimizer_attribute(model, "BarConvTol", 1e-3)
        track_peak_memory("After Set Optimizer")
    end
    
    @timeit to "Optimize" begin
        println("\n[4/5] Solving...")
        optimize!(model)
        track_peak_memory("After Optimize")
        println("  ✓ Status: $(termination_status(model))")
        if has_values(model)
            println("  ✓ Objective: $(round(objective_value(model), sigdigits=6))")
            println("  ✓ Solve Time: $(round(solve_time(model), digits=2)) sec")
        end
    end
    
    @timeit to "Write outputs" begin
        println("\n[5/5] Writing results...")
        MacroEnergy.write_outputs(@__DIR__, case, model)
        track_peak_memory("After Write")
    end
    
    system = case.systems[1]
end

println("\n" * "="^80)
println("PERFORMANCE SUMMARY")
println("="^80)
show(to)
println("\n" * "="^80)

println("\nMODEL STATISTICS")
println("="^80)
println("Variables:          $(num_variables(model))")
println("Constraints:        $(num_constraints(model; count_variable_in_set_constraints=true))")
if has_values(model)
    println("Objective Value:    $(round(objective_value(model), sigdigits=6))")
    println("Termination Status: $(termination_status(model))")
    println("Solve Time:         $(round(solve_time(model), digits=2)) sec")
end
println("="^80)

println("\n" * "="^80)
println("★ PEAK MEMORY SUMMARY ★")
println("="^80)
println("Peak Memory Usage:  $(round(peak_memory_gb, digits=2)) GB")
println("Peak occurred at:   [$peak_stage]")
println("Available RAM:      $(round(Sys.total_memory() / 1024^3, digits=2)) GB")
println("Peak / Available:   $(round(100 * peak_memory_gb / (Sys.total_memory() / 1024^3), digits=1))%")

if peak_memory_gb < 0.8 * Sys.total_memory() / 1024^3
    println("   (Peak usage: $(round(100 * peak_memory_gb / (Sys.total_memory() / 1024^3), digits=1))% of available RAM)")
else
    println("   (Peak usage: $(round(100 * peak_memory_gb / (Sys.total_memory() / 1024^3), digits=1))% of available RAM)")
    println("   Consider closing other applications or simplifying the model.")
end
println("="^80)

(system, model)