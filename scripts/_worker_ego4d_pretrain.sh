#!/bin/bash
# Per-GPU worker script launched by mpirun.
# Maps OpenMPI environment variables to PyTorch distributed equivalents.
set -euo pipefail

cd "${PBS_O_WORKDIR:-$HOME/VITRA}"

# Activate pixi environment for Python/PyTorch
set +u
eval "$(pixi shell-hook)"
set -u

# Force-load hpcx NCCL RDMA plugin so NCCL uses InfiniBand instead of Socket
HPCX_BASE=/apps/rocky9/hpcx/2.20/gcc11.4.1/cuda12.6
NCCL_PLUGIN="${HPCX_BASE}/nccl_rdma_sharp_plugin/lib/libnccl-net.so"
PIXI_LIB="${PBS_O_WORKDIR:-$HOME/VITRA}/.pixi/envs/default/lib"
export LD_LIBRARY_PATH="${HPCX_BASE}/nccl_rdma_sharp_plugin/lib:${HPCX_BASE}/sharp/lib:${HPCX_BASE}/ucx/lib/ucx:${HPCX_BASE}/ucx/lib:${PIXI_LIB}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_PRELOAD="${NCCL_PLUGIN}${LD_PRELOAD:+:$LD_PRELOAD}"

# Map MPI rank info → PyTorch distributed env vars
export RANK="${OMPI_COMM_WORLD_RANK}"
export WORLD_SIZE="${OMPI_COMM_WORLD_SIZE}"
export LOCAL_RANK="${OMPI_COMM_WORLD_LOCAL_RANK}"

# Debug: print once per node (LOCAL_RANK=0 only)
if [[ "$LOCAL_RANK" == "0" ]]; then
    echo "[rank${RANK}] node=$(hostname) world_size=${WORLD_SIZE}"
    echo "[rank${RANK}] LD_LIBRARY_PATH=${LD_LIBRARY_PATH}"
    echo "[rank${RANK}] LD_PRELOAD=${LD_PRELOAD}"
    echo "[rank${RANK}] plugin exists: $(ls -la "$NCCL_PLUGIN" 2>&1)"
    echo "[rank${RANK}] IB devices: $(ibv_devinfo 2>&1 | head -20)"
fi

python scripts/train.py \
    --config vitra/configs/ego4d_pretrain.json \
    --batch_size "${BATCH_SIZE}" \
    --total_batch_size "${TOTAL_BATCH_SIZE}" \
    ${MODEL_LOAD_ARG}
