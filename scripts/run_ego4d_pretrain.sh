#!/bin/bash
#PBS -q R1538111
#PBS -P gch51606
#PBS -v RTYPE=rt_HF
#PBS -V
#PBS -l select=8
#PBS -l walltime=96:00:00
#PBS -j oe
#PBS -o /home/acg17479bs/VITRA/logs/ego4d_pretrain.log
#PBS -N ego4d_pretrain

# Ego4D pretraining on ABCI (multi-node via mpirun, 8 GPUs per node)
#
# Prerequisites:
#   1. Set HF_TOKEN in ~/.bashrc (PaliGemma2 is gated)
#   2. Set WANDB_API_KEY in ~/.bashrc
#
# Usage:
#   qsub scripts/run_ego4d_pretrain.sh

set -euo pipefail

cd "${PBS_O_WORKDIR:-$HOME/VITRA}"

# Load MPI runtime for multi-node launch
source /etc/profile.d/modules.sh
module load hpcx/2.20

# Activate pixi environment
set +u
eval "$(pixi shell-hook)"
set -u

if [[ -z "${HF_TOKEN:-}" ]]; then
    echo "ERROR: HF_TOKEN is not set. PaliGemma2 is a gated model." >&2
    exit 1
fi
if [[ -z "${WANDB_API_KEY:-}" ]]; then
    echo "WARNING: WANDB_API_KEY is not set. W&B logging will be disabled."
fi

# Create output directories
mkdir -p /groups/gch51606/dataset/vitra/checkpoints/ego4d_pretrain
mkdir -p /groups/gch51606/dataset/vitra/logs/ego4d_pretrain
mkdir -p /groups/gch51606/dataset/vitra/cache/ego4d_pretrain
mkdir -p logs

# === Multi-node configuration ===
NODES=($(sort -u "$PBS_NODEFILE"))
NNODES=${#NODES[@]}
NPROC_PER_NODE=8
MASTER_ADDR=${NODES[0]}
MASTER_PORT=29500

# Keep total_batch_size=512 (same training dynamics); reduce per-device batch to compensate
export BATCH_SIZE=8
export TOTAL_BATCH_SIZE=512

# Auto-detect latest checkpoint for resume
MODEL_LOAD_ARG=""
OLD_CKPT_BASE="/groups/gch51606/dataset/vitra/checkpoints/ego4d_pretrain/pretrain_ego4d_TB512_B64_bf16True/checkpoints"
NEW_CKPT_BASE="/groups/gch51606/dataset/vitra/checkpoints/ego4d_pretrain/pretrain_ego4d_TB${TOTAL_BATCH_SIZE}_B${BATCH_SIZE}_bf16True/checkpoints"

CKPT_SEARCH_DIR="$NEW_CKPT_BASE"
if [[ ! -d "$NEW_CKPT_BASE" ]] || [[ -z "$(ls -A "$NEW_CKPT_BASE" 2>/dev/null)" ]]; then
    CKPT_SEARCH_DIR="$OLD_CKPT_BASE"
fi

if [[ -d "$CKPT_SEARCH_DIR" ]]; then
    LATEST_CKPT=$(python3 -c "
import os, re
d = '$CKPT_SEARCH_DIR'
ckpts = [f for f in os.listdir(d)
         if f.endswith('.ckpt') and os.path.isfile(os.path.join(d, f, 'weights.pt'))]
if ckpts:
    best = max(ckpts, key=lambda x: int(re.search(r'step=(\d+)', x).group(1)))
    print(os.path.join(d, best))
" 2>/dev/null || true)
    if [[ -n "${LATEST_CKPT:-}" ]]; then
        MODEL_LOAD_ARG="--model_load_path ${LATEST_CKPT}"
    fi
fi

# Export variables needed by the worker script
export MASTER_ADDR MASTER_PORT NNODES NPROC_PER_NODE MODEL_LOAD_ARG

# Real-time log
LOG="logs/ego4d_pretrain_live.log"

echo "=== Ego4D Multi-Node Pretraining ===" | tee "$LOG"
echo "Start: $(date)" | tee -a "$LOG"
echo "Nodes ($NNODES): ${NODES[*]}" | tee -a "$LOG"
echo "Master: $MASTER_ADDR:$MASTER_PORT" | tee -a "$LOG"
echo "Per-device batch size: $BATCH_SIZE" | tee -a "$LOG"
echo "Total batch size: $TOTAL_BATCH_SIZE (grad_accum=$((TOTAL_BATCH_SIZE / BATCH_SIZE / (NPROC_PER_NODE * NNODES))))" | tee -a "$LOG"
echo "Resume from: ${LATEST_CKPT:-none (fresh start)}" | tee -a "$LOG"

# === Launch via mpirun (one process per GPU across all nodes) ===
# Use --oversubscribe to bypass PBS slot limits; -map-by ppr:8:node ensures 8 procs/node
mpirun -np $((NNODES * NPROC_PER_NODE)) \
    --oversubscribe \
    -map-by "ppr:${NPROC_PER_NODE}:node" \
    -bind-to none \
    -x PATH -x LD_LIBRARY_PATH \
    -x HOME -x PBS_O_WORKDIR \
    -x HF_TOKEN -x WANDB_API_KEY \
    -x MASTER_ADDR -x MASTER_PORT -x NNODES -x NPROC_PER_NODE \
    -x BATCH_SIZE -x TOTAL_BATCH_SIZE -x MODEL_LOAD_ARG \
    -x NCCL_IB_DISABLE=0 \
    -x NCCL_DEBUG=INFO \
    bash scripts/_worker_ego4d_pretrain.sh \
    2>&1 | tee -a "$LOG"

echo "End: $(date)" | tee -a "$LOG"
echo "=== Done ===" | tee -a "$LOG"
