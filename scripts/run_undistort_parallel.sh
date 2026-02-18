#!/bin/bash
#PBS -q R1538111
#PBS -P gch51606
#PBS -v RTYPE=rt_HF
#PBS -l select=1
#PBS -l walltime=24:00:00
#PBS -J 1-8
#PBS -j oe
#PBS -o /home/acg17479bs/VITRA/logs/undistort/
#PBS -N undistort_ego4d

# Ego4D video undistortion — PBS array job (8 nodes, 32 parallel workers each)
#
# Usage:
#   1. bash scripts/prepare_undistort_list.sh   # generate video list
#   2. qsub scripts/run_undistort_parallel.sh   # submit array job
#
# Each array task processes a chunk of the video list using xargs -P 32.

set -euo pipefail

DATA_ROOT="/groups/gch51606/dataset/vitra"
VIDEO_LIST="${DATA_ROOT}/undistort_video_list.txt"
LOG_DIR="${HOME}/VITRA/logs/undistort"

# Use PBS_O_WORKDIR if available (batch mode), otherwise current dir
cd "${PBS_O_WORKDIR:-$HOME/VITRA}"
SCRIPT_DIR="$(pwd)/scripts"

# Activate pixi environment (temporarily disable nounset for conda activate scripts)
set +u
eval "$(pixi shell-hook)"
set -u

# Fix opencv conflict: ultralytics pulls in opencv-python which shadows opencv-contrib-python
# Only node 0 does the fix; others wait for it to complete
LOCK_FILE="${HOME}/.opencv_fix_done"
if [[ "$(( PBS_ARRAY_INDEX - 1 ))" -eq 0 ]]; then
    rm -f "$LOCK_FILE"
    pip install --force-reinstall --no-deps opencv-contrib-python
    python -c "import cv2; assert hasattr(cv2.omnidir, 'initUndistortRectifyMap'), 'cv2.omnidir broken'; print('opencv-contrib OK')"
    touch "$LOCK_FILE"
else
    echo "Waiting for node 0 to fix opencv..."
    for i in $(seq 1 120); do
        [[ -f "$LOCK_FILE" ]] && break
        sleep 5
    done
    [[ -f "$LOCK_FILE" ]] || { echo "ERROR: opencv fix timed out"; exit 1; }
    python -c "import cv2; assert hasattr(cv2.omnidir, 'initUndistortRectifyMap'), 'cv2.omnidir broken'; print('opencv-contrib OK')"
fi

PARALLEL_WORKERS=20
TOTAL_NODES=8

mkdir -p "$LOG_DIR"

# Validate video list
if [[ ! -f "$VIDEO_LIST" ]]; then
    echo "ERROR: Video list not found: $VIDEO_LIST" >&2
    echo "Run scripts/prepare_undistort_list.sh first." >&2
    exit 1
fi

TOTAL_VIDEOS=$(wc -l < "$VIDEO_LIST")
if [[ "$TOTAL_VIDEOS" -eq 0 ]]; then
    echo "No videos to process."
    exit 0
fi

# Calculate chunk for this array task
IDX=$(( PBS_ARRAY_INDEX - 1 ))  # PBS array is 1-based, convert to 0-based
CHUNK_SIZE=$(( (TOTAL_VIDEOS + TOTAL_NODES - 1) / TOTAL_NODES ))
START=$(( IDX * CHUNK_SIZE + 1 ))  # sed is 1-indexed
END=$(( START + CHUNK_SIZE - 1 ))
if [[ "$END" -gt "$TOTAL_VIDEOS" ]]; then
    END=$TOTAL_VIDEOS
fi

NODE_LOG="${LOG_DIR}/undistort_node${IDX}.log"

echo "=== Undistort Array Task ${IDX} ===" | tee "$NODE_LOG"
echo "Total videos: ${TOTAL_VIDEOS}" | tee -a "$NODE_LOG"
echo "This node: lines ${START}-${END} ($(( END - START + 1 )) videos)" | tee -a "$NODE_LOG"
echo "Parallel workers: ${PARALLEL_WORKERS}" | tee -a "$NODE_LOG"
echo "Start time: $(date)" | tee -a "$NODE_LOG"

# Extract this node's chunk and process with xargs
sed -n "${START},${END}p" "$VIDEO_LIST" | \
    xargs -P "$PARALLEL_WORKERS" -I {} \
    python "$SCRIPT_DIR/undistort_single_video.py" --video_name {} \
    2>&1 | tee -a "$NODE_LOG"

echo "End time: $(date)" | tee -a "$NODE_LOG"
echo "=== Node ${IDX} complete ===" | tee -a "$NODE_LOG"
