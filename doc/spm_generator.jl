using LinearAlgebra

# --- システム定数 ---
const N_RHO = 16            # 半径方向の解像度
const N_THETA = 16          # 角度方向の解像度
const FOV_DEG = 210.0       # 視野角 (210度)
const FOV_RAD = deg2rad(FOV_DEG)
const R_ROBOT = 1.5         # ロボットの本体半径
const SENSING_RATIO = 15.0  # 視野距離係数 (D = 15 * r_total)
const SIGMA_SPM = 0.25      # 領域投影のボケ幅 (Gaussian Sigma)

"""
SPMのグリッド設定を保持する構造体
"""
struct SPMConfig
    rho_grid::Vector{Float64}
    theta_grid::Vector{Float64}
    d_max_log::Float64
end

"""
SPMグリッドの初期化
対数スケールおよび210度視野に基づいた座標系を生成する
"""
function init_spm()
    d_max_log = log(SENSING_RATIO)
    
    # セルの中心がサンプリング点となるよう配置
    rho_grid = collect(range(d_max_log/(2*N_RHO), d_max_log * (1 - 1/(2*N_RHO)), length=N_RHO))
    theta_grid = collect(range(-FOV_RAD/2 * (1 - 1/N_THETA), FOV_RAD/2 * (1 - 1/N_THETA), length=N_THETA))
    
    return SPMConfig(rho_grid, theta_grid, d_max_log)
end

"""
表面距離に基づいた正規化対数距離の計算
d = log(||r|| / r_total)
"""
function calc_log_dist(rel_p, r_total)
    d_center = norm(rel_p)
    # 接触時に 0, 遠方ほど正の値。自動微分のために微小値を加算
    return log(max(1.0, d_center / (r_total + 1e-6)))
end

"""
SPM 3チャネル画像の生成
1ch: Occupancy (占有度)
2ch: Saliency (近接顕著性 - 表面距離ベース)
3ch: Risk (衝突危険性 - TTCベース)
"""
function generate_spm_3ch(config::SPMConfig, agents_rel_pos, agents_rel_vel, r_agent)
    # 出力テンソル (H, W, C)
    spm = zeros(N_RHO, N_THETA, 3)
    r_total = R_ROBOT + r_agent
    
    for (idx, p_rel) in enumerate(agents_rel_pos)
        # 1. 基本座標の算出
        rho_val = calc_log_dist(p_rel, r_total)
        theta_val = atan(p_rel[2], p_rel[1])
        
        # 210度視野のマスク（微分を壊さないよう、急激なifではなく重みとして扱うことも可能だが
        # 基本的なFOV外排除は計算コスト削減のため continue とする）
        if abs(theta_val) > FOV_RAD/2
            continue
        end

        # 2. 物理量の計算
        # 近接度 (Saliency): 表面距離が近いほど 1.0 に近づく
        saliency = exp(-rho_val) 
        
        # 衝突リスク (Risk): TTC (Time to Collision) の近似
        # v_rel はロボットに対するエージェントの相対速度
        v_rel = agents_rel_vel[idx]
        radial_vel = -dot(p_rel, v_rel) / (norm(p_rel) + 1e-6) # 接近速度
        ttc = max(0.0, radial_vel) / (exp(rho_val) + 1e-6)     # 簡易的な逆TTC
        risk = min(1.0, ttc)

        # 3. 領域投影 (Blurred Projection)
        # 16x16の全ピクセルに対してガウシアンカーネルで加算
        for j in 1:N_THETA, i in 1:N_RHO
            d_rh = rho_val - config.rho_grid[i]
            d_th = theta_val - config.theta_grid[j]
            
            # ガウス重み
            weight = exp(-(d_rh^2 + d_th^2) / (2 * SIGMA_SPM^2))
            
            # 各チャネルへの書き込み (max集約)
            spm[i, j, 1] = max(spm[i, j, 1], weight)           # Occupancy
            spm[i, j, 2] = max(spm[i, j, 2], weight * saliency) # Saliency
            spm[i, j, 3] = max(spm[i, j, 3], weight * risk)     # Risk
        end
    end
    
    return spm
end

# --- 動作テスト用 ---
# config = init_spm()
# test_pos = [[5.0, 2.0], [-3.0, 10.0]]
# test_vel = [[-1.0, 0.0], [0.0, -0.5]]
# img = generate_spm_3ch(config, test_pos, test_vel, 1.5)