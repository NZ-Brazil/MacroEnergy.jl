using MacroEnergy
using Gurobi

(system, model) = run_case(
    @__DIR__;
    optimizer = Gurobi.Optimizer,
    lazy_load = true,
    # optimizer_attributes = ("Method" => 2, "Crossover" => 0, "BarConvTol" => 1e-3)
    # optimizer_attributes=("Method" => 2, "Crossover" => 0, "NumericFocus" => 1, "BarConvTol" => 1e-3)
    optimizer_attributes=("Method" => 2, "Crossover" => 0, "NumericFocus" => 3, "BarConvTol" => 1e-1, "BarHomogeneous" => 1)

    # optimizer_attributes=(
    #     "Method" => 2,
    #     "Crossover" => 0,
    #     "NumericFocus" => 2,
    #     "BarConvTol" => 1e0,
    #     "BarHomogeneous" => 1,
    #     "ScaleFlag" => 2,           
    #     "ObjScale" => -1,           
    # )
);
