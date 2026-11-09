# `WindOffshore` is the `VRE` variant for offshore wind, i.e. `VRE{:WindOffshore}`.
# It reuses the struct, `default_data` and `make` defined in `src/model/assets/vre.jl`.
# Inputs select it with `type: "WindOffshore"` (same as `type: "VRE"` with
# `technology: "WindOffshore"`), and outputs report it as `VRE{WindOffshore}`.
const WindOffshore = VRE{:WindOffshore}
