#!/bin/bash
#PBS -P gch51606
#PBS -q rt_HC
#PBS -l select=1
#PBS -l walltime=06:00:00
#PBS -N vitra_download
#PBS -j oe
#PBS -o /home/acg17479bs/VITRA/logs/download_metadata.log

set -eo pipefail

cd /home/acg17479bs/VITRA

# Activate pixi environment (disable nounset temporarily for conda activate scripts)
set +u
eval "$(pixi shell-hook)"
set -u

DATA_ROOT="/groups/gch51606/dataset/vitra"
REPO="VITRA-VLA/VITRA-1M"

# Create directory structure
mkdir -p "${DATA_ROOT}/Annotation/statistics"
mkdir -p "${DATA_ROOT}/Video/Ego4D_root"
mkdir -p "${DATA_ROOT}/Video/EgoExo4D_root"
mkdir -p "${DATA_ROOT}/Video/Epic-Kitchen_root"
mkdir -p "${DATA_ROOT}/Video/Somethingsomething-v2_root"

echo "=== Downloading metadata archives from HuggingFace ==="

# Download all 5 tar.gz metadata archives (~85GB total)
for archive in ego4d_cooking_and_cleaning ego4d_other egoexo4d epic ssv2; do
    if [ -f "${DATA_ROOT}/${archive}.tar.gz" ]; then
        echo "Skipping ${archive}.tar.gz (already exists)"
    else
        echo "Downloading ${archive}.tar.gz ..."
        huggingface-cli download ${REPO} "${archive}.tar.gz" \
            --repo-type dataset \
            --local-dir "${DATA_ROOT}"
    fi
done

echo "=== Extracting archives ==="

for archive in ego4d_cooking_and_cleaning ego4d_other egoexo4d epic ssv2; do
    if [ -d "${DATA_ROOT}/Annotation/${archive}/episodic_annotations" ]; then
        echo "Skipping extraction of ${archive} (already extracted)"
    else
        echo "Extracting ${archive}.tar.gz ..."
        tar -xzf "${DATA_ROOT}/${archive}.tar.gz" -C "${DATA_ROOT}/Annotation/"
    fi
done

echo "=== Downloading statistics files ==="

huggingface-cli download ${REPO} \
    statistics/ego4d_cooking_and_cleaning_angle_statistics.json \
    statistics/ego4d_other_angle_statistics.json \
    statistics/egoexo4d_angle_statistics.json \
    statistics/epic_angle_statistics.json \
    statistics/ssv2_angle_statistics.json \
    --repo-type dataset \
    --local-dir "${DATA_ROOT}/Annotation"

echo "=== Downloading camera intrinsics ==="

huggingface-cli download ${REPO} \
    --include "intrinsics/**" \
    --repo-type dataset \
    --local-dir "${DATA_ROOT}"

echo "=== Verifying directory structure ==="

echo "--- Annotation directories ---"
for d in ego4d_cooking_and_cleaning ego4d_other egoexo4d epic ssv2; do
    count=$(ls "${DATA_ROOT}/Annotation/${d}/episodic_annotations/" 2>/dev/null | wc -l)
    echo "  ${d}: ${count} episode files"
done

echo "--- Statistics files ---"
ls -la "${DATA_ROOT}/Annotation/statistics/"

echo "--- Intrinsics ---"
for d in ego4d egoexo4d; do
    count=$(ls "${DATA_ROOT}/intrinsics/${d}/" 2>/dev/null | wc -l)
    echo "  ${d}: ${count} intrinsics files"
done

echo "=== Done ==="