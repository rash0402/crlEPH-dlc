"""
Data Schema Module for EPH v5.6
Provides unified API for loading/saving VAE training data
"""

module DataSchema

using HDF5

export VAEDataSample, VAEDataset
export load_dataset, save_dataset, create_dataset
export load_simulation_log, get_vae_samples

# ===== Data Structures =====

"""
Single VAE training sample
"""
struct VAEDataSample
    spm_current::Array{Float32, 3}   # (16, 16, 3) - y[k]
    action::Vector{Float32}          # (2,) - u[k]
    spm_next::Array{Float32, 3}      # (16, 16, 3) - y[k+1]
end

"""
VAE Dataset with train/val/test splits
"""
struct VAEDataset
    # Training data
    train_spms_current::Array{Float32, 4}   # (N_train, 16, 16, 3)
    train_actions::Array{Float32, 2}        # (N_train, 2)
    train_spms_next::Array{Float32, 4}      # (N_train, 16, 16, 3)
    train_metadata::Dict{String, Any}

    # Validation data
    val_spms_current::Array{Float32, 4}
    val_actions::Array{Float32, 2}
    val_spms_next::Array{Float32, 4}
    val_metadata::Dict{String, Any}

    # Test data (IID)
    test_iid_spms_current::Array{Float32, 4}
    test_iid_actions::Array{Float32, 2}
    test_iid_spms_next::Array{Float32, 4}
    test_iid_metadata::Dict{String, Any}

    # Test data (OOD - out of distribution)
    test_ood_spms_current::Array{Float32, 4}
    test_ood_actions::Array{Float32, 2}
    test_ood_spms_next::Array{Float32, 4}
    test_ood_metadata::Dict{String, Any}
end

# ===== HDF5 I/O Functions =====

"""
Load VAE dataset from HDF5 file

# Arguments
- `filepath::String`: Path to dataset_v56.h5

# Returns
- `VAEDataset`: Loaded dataset
"""
function load_dataset(filepath::String)
    h5open(filepath, "r") do file
        # Load training data
        train_spms_current = read(file, "/train/spms_current")
        train_actions = read(file, "/train/actions")
        train_spms_next = read(file, "/train/spms_next")
        train_metadata = Dict{String, Any}()
        if exists(file, "/train/metadata")
            # Load metadata attributes
            train_metadata["description"] = "Training data"
        end

        # Load validation data
        val_spms_current = read(file, "/val/spms_current")
        val_actions = read(file, "/val/actions")
        val_spms_next = read(file, "/val/spms_next")
        val_metadata = Dict{String, Any}()

        # Load test IID data
        test_iid_spms_current = read(file, "/test_iid/spms_current")
        test_iid_actions = read(file, "/test_iid/actions")
        test_iid_spms_next = read(file, "/test_iid/spms_next")
        test_iid_metadata = Dict{String, Any}()

        # Load test OOD data
        test_ood_spms_current = read(file, "/test_ood/spms_current")
        test_ood_actions = read(file, "/test_ood/actions")
        test_ood_spms_next = read(file, "/test_ood/spms_next")
        test_ood_metadata = Dict{String, Any}()

        return VAEDataset(
            train_spms_current, train_actions, train_spms_next, train_metadata,
            val_spms_current, val_actions, val_spms_next, val_metadata,
            test_iid_spms_current, test_iid_actions, test_iid_spms_next, test_iid_metadata,
            test_ood_spms_current, test_ood_actions, test_ood_spms_next, test_ood_metadata
        )
    end
end

"""
Save VAE dataset to HDF5 file

# Arguments
- `filepath::String`: Output path
- `dataset::VAEDataset`: Dataset to save
"""
function save_dataset(filepath::String, dataset::VAEDataset)
    h5open(filepath, "w") do file
        # Create metadata group
        create_group(file, "/metadata")
        attrs(file["/metadata"])["version"] = "5.6.0"
        attrs(file["/metadata"])["creation_date"] = string(now())
        attrs(file["/metadata"])["description"] = "Action-Dependent VAE with Surprise"

        # Save training data
        create_group(file, "/train")
        file["/train/spms_current"] = dataset.train_spms_current
        file["/train/actions"] = dataset.train_actions
        file["/train/spms_next"] = dataset.train_spms_next

        # Save validation data
        create_group(file, "/val")
        file["/val/spms_current"] = dataset.val_spms_current
        file["/val/actions"] = dataset.val_actions
        file["/val/spms_next"] = dataset.val_spms_next

        # Save test IID data
        create_group(file, "/test_iid")
        file["/test_iid/spms_current"] = dataset.test_iid_spms_current
        file["/test_iid/actions"] = dataset.test_iid_actions
        file["/test_iid/spms_next"] = dataset.test_iid_spms_next

        # Save test OOD data
        create_group(file, "/test_ood")
        file["/test_ood/spms_current"] = dataset.test_ood_spms_current
        file["/test_ood/actions"] = dataset.test_ood_actions
        file["/test_ood/spms_next"] = dataset.test_ood_spms_next
    end
    println("✅ Dataset saved to: $filepath")
end

"""
Create empty dataset with given sizes

# Arguments
- `n_train::Int`: Number of training samples
- `n_val::Int`: Number of validation samples
- `n_test_iid::Int`: Number of IID test samples
- `n_test_ood::Int`: Number of OOD test samples

# Returns
- `VAEDataset`: Empty dataset
"""
function create_dataset(n_train::Int, n_val::Int, n_test_iid::Int, n_test_ood::Int)
    return VAEDataset(
        zeros(Float32, n_train, 16, 16, 3),
        zeros(Float32, n_train, 2),
        zeros(Float32, n_train, 16, 16, 3),
        Dict{String, Any}(),
        zeros(Float32, n_val, 16, 16, 3),
        zeros(Float32, n_val, 2),
        zeros(Float32, n_val, 16, 16, 3),
        Dict{String, Any}(),
        zeros(Float32, n_test_iid, 16, 16, 3),
        zeros(Float32, n_test_iid, 2),
        zeros(Float32, n_test_iid, 16, 16, 3),
        Dict{String, Any}(),
        zeros(Float32, n_test_ood, 16, 16, 3),
        zeros(Float32, n_test_ood, 2),
        zeros(Float32, n_test_ood, 16, 16, 3),
        Dict{String, Any}()
    )
end

"""
Load simulation log and extract (spm[k], action[k], spm[k+1]) samples

# Arguments
- `log_filepath::String`: Path to simulation HDF5 log
- `agent_id::Int`: Agent ID to extract (default: 1)

# Returns
- `samples::Vector{VAEDataSample}`: Extracted samples
"""
function load_simulation_log(log_filepath::String; agent_id::Int=1)
    samples = VAEDataSample[]

    h5open(log_filepath, "r") do file
        # Read SPM data: (n_steps, n_agents, 16, 16, 3)
        spms = read(file, "/spm")
        # Read action data: (n_steps, n_agents, 2)
        actions = read(file, "/actions")

        n_steps, n_agents, _, _, _ = size(spms)

        # Extract sequential samples for specified agent
        for t in 1:(n_steps-1)
            spm_current = Float32.(spms[t, agent_id, :, :, :])
            action = Float32.(actions[t, agent_id, :])
            spm_next = Float32.(spms[t+1, agent_id, :, :, :])

            push!(samples, VAEDataSample(spm_current, action, spm_next))
        end
    end

    return samples
end

"""
Extract VAE samples from multiple simulation logs

# Arguments
- `log_dir::String`: Directory containing simulation logs
- `pattern::Regex`: Filename pattern (e.g., r"sim_.*\\.h5")

# Returns
- `samples::Vector{VAEDataSample}`: All extracted samples
"""
function get_vae_samples(log_dir::String, pattern::Regex=r"sim_.*\.h5")
    all_samples = VAEDataSample[]

    for filename in readdir(log_dir)
        if occursin(pattern, filename)
            filepath = joinpath(log_dir, filename)
            println("  Loading: $filename")
            samples = load_simulation_log(filepath)
            append!(all_samples, samples)
        end
    end

    println("✅ Total samples extracted: $(length(all_samples))")
    return all_samples
end

end # module
