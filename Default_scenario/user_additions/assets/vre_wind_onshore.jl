# `WindOnshore` is the `VRE` variant for onshore wind, i.e. `VRE{:WindOnshore}`.
# It reuses the struct, `default_data` and `make` defined in `src/model/assets/vre.jl`.
# Inputs select it with `type: "WindOnshore"` (same as `type: "VRE"` with
# `technology: "WindOnshore"`), and outputs report it as `VRE{WindOnshore}`.
const WindOnshore = VRE{:WindOnshore}
