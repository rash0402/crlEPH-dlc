# M2 Mac (arm64) 環境に最適化された Julia 1.10 イメージを使用
FROM julia:1.10-bookworm

# システムの更新と、Python、ZMQ、HDF5 の依存関係をインストール
# ROS2は使用しないため、標準的な Debian パッケージのみを構成
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    libzmq3-dev \
    libhdf5-dev \
    pkg-config \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Python ライブラリのインストール
# pyzmq, msgpack (ZMQ通信用), matplotlib, numpy (可視化用), h5py (データ保存用)
RUN pip3 install --no-cache-dir \
    pyzmq \
    msgpack \
    numpy \
    matplotlib \
    h5py \
    --break-system-packages

# ワークスペースの設定
WORKDIR /root/eph_project

# Julia パッケージのインストール
# Project.toml と Manifest.toml をコピーして instantiate することで
# ローカル環境と完全に同じバージョン構成を再現する (再現性の確保)
COPY Project.toml Manifest.toml ./
RUN julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

# コンテナ起動時に Julia を起動
CMD ["julia"]