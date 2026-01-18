#!/usr/bin/env python3
"""Check random obstacles scenario data"""
import h5py
import numpy as np

filepath = "data/vae_training/raw_v72/v72_random_d10_n30_s1_20260117_122900.h5"

with h5py.File(filepath, 'r') as f:
    # Read metadata
    print("Random Obstacles Scenario Analysis")
    print("="*70)
    print(f"File: {filepath}")
    print()

    # Metadata
    if 'metadata' in f:
        print("Metadata:")
        for key in f['metadata'].keys():
            val = f[f'metadata/{key}'][()]
            print(f"  {key}: {val}")
        print()

    # Position data
    pos_raw = np.array(f['trajectory/pos'])
    pos = np.transpose(pos_raw, (2, 1, 0))  # [steps, agents, dims]

    print(f"Position Data:")
    print(f"  Shape: {pos.shape} (steps, agents, dims)")
    print(f"  X range: [{pos[:,:,0].min():.2f}, {pos[:,:,0].max():.2f}]")
    print(f"  Y range: [{pos[:,:,1].min():.2f}, {pos[:,:,1].max():.2f}]")
    print()

    # Initial positions
    print(f"Initial Positions (t=0):")
    for i in range(pos.shape[1]):
        x, y = pos[0, i, 0], pos[0, i, 1]
        print(f"  Agent {i+1:2d}: ({x:6.2f}, {y:6.2f})")
    print()

    # Check if agents are clustered or dispersed
    x_std = np.std(pos[0, :, 0])
    y_std = np.std(pos[0, :, 1])
    print(f"Initial Position Spread:")
    print(f"  X std dev: {x_std:.2f}m")
    print(f"  Y std dev: {y_std:.2f}m")
    print()

    # Obstacles
    if 'obstacles/data' in f:
        obs_raw = np.array(f['obstacles/data'])
        print(f"Obstacles:")
        print(f"  Count: {len(obs_raw)}")
        if len(obs_raw) > 0:
            if obs_raw.shape[1] == 2:
                # Center coordinates
                print(f"  X range: [{obs_raw[:,0].min():.2f}, {obs_raw[:,0].max():.2f}]")
                print(f"  Y range: [{obs_raw[:,1].min():.2f}, {obs_raw[:,1].max():.2f}]")
