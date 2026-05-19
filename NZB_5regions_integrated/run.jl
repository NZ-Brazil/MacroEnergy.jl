using MacroEnergy
using Gurobi

(system, model) = run_case(
    @__DIR__;
    optimizer = Gurobi.Optimizer,
    lazy_load = true,
    optimizer_attributes = (
        "Method"          => 2,
        "Crossover"       => 0,
        "NumericFocus"    => 3,
        "BarConvTol"      => 1e-1,
        "BarHomogeneous"  => 1,
        "Threads"         => 24,
        "OutputFlag"      => 1,
        "LogToConsole"    => 1,
        "LogFile"         => "gurobi_run.log",
        "DisplayInterval" => 1,
        "MemLimit"        => 110,
    )
);
