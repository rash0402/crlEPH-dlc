module DataLoader

using HDF5
using Random
using Flux

export load_spm_data, get_data_loader

"""
    load_spm_data(data_dir::String)

Loads SPM data from all .h5 files in the directory.
Returns a single array of shape (16, 16, 3, N_total).
Excludes files that don't match the expected SPM shape.
"""
function load_spm_data(data_dir::String)
    # Find all .h5 files
    files = filter(f -> endswith(f, ".h5"), readdir(data_dir, join=true))
    
    if isempty(files)
        @warn "No .h5 files found in $data_dir"
        return nothing
    end
    
    println("📂 Found $(length(files)) data files in $data_dir")
    
    all_spm = []
    total_samples = 0
    
    for file in files
        try
            h5open(file, "r") do h5
                if haskey(h5, "data/spm")
                    # Shape: (16, 16, 3, steps)
                    spm = read(h5["data/spm"])
                    
                    # Check actual_steps if available (to trim zero-padding)
                    steps = size(spm, 4)
                    if haskey(attributes(h5), "actual_steps")
                        steps = read(attributes(h5)["actual_steps"])
                        # Trim
                        spm = spm[:, :, :, 1:steps]
                    end
                    
                    # Basic validation of shape (must be 16x16x3)
                    if size(spm, 1) == 16 && size(spm, 2) == 16 && size(spm, 3) == 3
                        push!(all_spm, spm)
                        total_samples += steps
                    else
                        @warn "Skipping $file: Dimensions mismatch $(size(spm))"
                    end
                end
            end
        catch e
            @warn "Failed to read $file: $e"
        end
    end
    
    if isempty(all_spm)
        @warn "No valid SPM data found."
        return nothing
    end
    
    println("✅ Loaded $total_samples samples.")
    
    # Concatenate along batch dimension (4)
    # cat(A..., dims=4) converts list of 4D arrays into one big 4D array
    return cat(all_spm..., dims=4)
end

"""
    get_data_loader(data::Array{Float32, 4}, batch_size::Int; shuffle=true, split_ratio=0.8)

Creates Train and Test DataLoaders.
"""
function get_data_loader(data::Array{Float32, 4}, batch_size::Int; shuffle=true, split_ratio=0.8)
    n_samples = size(data, 4)
    indices = collect(1:n_samples)
    
    if shuffle
        Random.shuffle!(indices)
    end
    
    split_idx = floor(Int, n_samples * split_ratio)
    train_idx = indices[1:split_idx]
    test_idx = indices[split_idx+1:end]
    
    train_data = data[:, :, :, train_idx]
    test_data = data[:, :, :, test_idx]
    
    train_loader = Flux.DataLoader(train_data, batchsize=batch_size, shuffle=true)
    test_loader = Flux.DataLoader(test_data, batchsize=batch_size, shuffle=false)
    
    return train_loader, test_loader
end

end # module
