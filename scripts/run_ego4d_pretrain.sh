#!/bin/bash
#PBS -q R1538111
#PBS -P gch51606
#PBS -v RTYPE=rt_HF
#PBS -V
#PBS -l select=1
#PBS -l walltime=96:00:00
#PBS -j oe
#PBS -o /home/acg17479bs/VITRA/logs/ego4d_pretrain.log
#PBS -N ego4d_pretrain

# Ego4D-only pretraining on ABCI (single node, 8 GPUs)
#
# Prerequisites:
#   1. Set HF_TOKEN in ~/.bashrc or below (PaliGemma2 is gated)
#   2. Set WANDB_API_KEY in ~/.bashrc or below
#
# Usage:
#   qsub scripts/run_ego4d_pretrain.sh

set -euo pipefail

cd "${PBS_O_WORKDIR:-$HOME/VITRA}"

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
mkdir -p /home/acg17479bs/VITRA/logs

# Real-time log (PBS -o only writes after job ends)
LOG="/home/acg17479bs/VITRA/logs/ego4d_pretrain_live.log"

echo "=== Ego4D Pretraining ===" | tee "$LOG"
echo "Start time: $(date)" | tee -a "$LOG"
echo "Node: $(hostname)" | tee -a "$LOG"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | tee -a "$LOG" || echo "(no GPU info)" | tee -a "$LOG"

torchrun --nproc_per_node=8 --standalone \
    scripts/train.py \
    --config vitra/configs/ego4d_pretrain.json \
    2>&1 | tee -a "$LOG"

echo "End time: $(date)" | tee -a "$LOG"
echo "=== Done ===" | tee -a "$LOG"
