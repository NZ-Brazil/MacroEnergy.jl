# `SolarPV` is the `VRE` variant for utility-scale solar PV, i.e. `VRE{:SolarPV}`.
# It reuses the struct, `default_data` and `make` defined in `src/model/assets/vre.jl`.
# Inputs select it with `type: "SolarPV"` (same as `type: "VRE"` with
# `technology: "SolarPV"`), and outputs report it as `VRE{SolarPV}`.
const SolarPV = VRE{:SolarPV}
