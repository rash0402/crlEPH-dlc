# Temporary config for M4 validation
using Random
Random.seed!(1)

# Override control params
const CONTROL_PARAMS_OVERRIDE = ControlParams(
    use_predictive_control=true,
    use_vae=true
)

const WORLD_PARAMS_OVERRIDE = WorldParams(
    max_steps=1000
)
