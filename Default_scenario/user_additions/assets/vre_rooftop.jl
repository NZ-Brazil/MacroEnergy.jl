# `RooftopPV` is the `VRE` variant for rooftop (distributed) solar PV, i.e. `VRE{:RooftopPV}`.
# It reuses the struct, `default_data` and `make` defined in `src/model/assets/vre.jl`.
# Inputs select it with `type: "RooftopPV"` (same as `type: "VRE"` with
# `technology: "RooftopPV"`), and outputs report it as `VRE{RooftopPV}`.
const RooftopPV = VRE{:RooftopPV}
