using MacroEnergy
using Gurobi

(system, model) = run_case(
    @__DIR__;
    optimizer = Gurobi.Optimizer,
    lazy_load = false,
    optimizer_attributes = ("Method" => 2, "Crossover" => 0, "BarConvTol" => 1e-3)
);