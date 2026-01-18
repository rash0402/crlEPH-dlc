#!/usr/bin/env julia
"""
Generic VAE Training Entry Point
Delegates to version-specific implementation
"""

# Detect version (default: v72)
const VERSION = get(ENV, "EPH_VERSION", "v72")
const SCRIPT_DIR = @__DIR__
const VERSION_SCRIPT = joinpath(SCRIPT_DIR, VERSION, "train_vae.jl")

if !isfile(VERSION_SCRIPT)
    println("❌ Error: Version $VERSION not found")
    println("   Available versions:")
    for dir in readdir(SCRIPT_DIR)
        if startswith(dir, "v") && isdir(joinpath(SCRIPT_DIR, dir))
            println("   - $dir")
        end
    end
    exit(1)
end

println("🤖 EPH VAE Training (version: $VERSION)")
println()

# Execute version-specific script
include(VERSION_SCRIPT)
