#!/bin/bash
# Generate a filtered list of Ego4D video UUIDs that:
#   1. Have intrinsics (.npy files)
#   2. Have raw source videos (.mp4 in full_scale)
#   3. Have NOT already been undistorted (.mp4 in Ego4D_root)

set -euo pipefail

DATA_ROOT="/groups/gch51606/dataset/vitra"
INTRINSICS_DIR="${DATA_ROOT}/intrinsics/ego4d"
VIDEO_SOURCE_DIR="/groups/gch51606/dataset/ego4d_airoa/raw/v2/full_scale"
OUTPUT_DIR="${DATA_ROOT}/Video/Ego4D_root"
OUTPUT_LIST="${DATA_ROOT}/undistort_video_list.txt"

# Validate directories exist
for dir in "$INTRINSICS_DIR" "$VIDEO_SOURCE_DIR"; do
    if [[ ! -d "$dir" ]]; then
        echo "ERROR: Directory not found: $dir" >&2
        exit 1
    fi
done

# Create output directory if needed
mkdir -p "$OUTPUT_DIR"

# Count stats
total_intrinsics=0
missing_source=0
already_done=0
to_process=0

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

# Extract UUIDs from intrinsics .npy files, filter, and write to list
for npy in "${INTRINSICS_DIR}"/*.npy; do
    [[ -f "$npy" ]] || continue
    uuid=$(basename "$npy" .npy)
    total_intrinsics=$((total_intrinsics + 1))

    # Check source video exists
    if [[ ! -f "${VIDEO_SOURCE_DIR}/${uuid}.mp4" ]]; then
        missing_source=$((missing_source + 1))
        continue
    fi

    # Check if already undistorted
    if [[ -f "${OUTPUT_DIR}/${uuid}.mp4" ]]; then
        already_done=$((already_done + 1))
        continue
    fi

    echo "$uuid" >> "$tmpfile"
    to_process=$((to_process + 1))
done

# Sort for deterministic ordering and write final list
sort "$tmpfile" > "$OUTPUT_LIST"

echo "=== Undistort Video List Summary ==="
echo "Intrinsics found:    $total_intrinsics"
echo "Missing source video: $missing_source"
echo "Already undistorted:  $already_done"
echo "To process:           $to_process"
echo "Output list:          $OUTPUT_LIST"
