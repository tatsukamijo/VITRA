#!/bin/bash
# Undistort progress monitor
# Usage: bash scripts/undistort_progress.sh

LOG_DIR="${HOME}/VITRA/logs/undistort"
OUTPUT_DIR="/groups/gch51606/dataset/vitra/Video/Ego4D_root"
TOTAL=2448

completed=$(ls "$OUTPUT_DIR"/*.mp4 2>/dev/null | wc -l)
pct=$(( completed * 100 / TOTAL ))

# Per-node stats
echo "=== Per Node ==="
printf "%-8s %6s %6s %10s\n" "Node" "Done" "Total" "Avg(min)"
total_done=0
total_time=0
for f in "$LOG_DIR"/undistort_node*.log; do
    [[ -f "$f" ]] || continue
    node=$(basename "$f" .log | sed 's/undistort_//')
    stats=$(cat "$f" | tr '\r' '\n' | grep "^DONE:" | awk -F'|' '{gsub(/[^0-9.]/, "", $2); sum+=$2; n++} END {if(n>0) printf "%d %.1f", n, sum/n/60; else print "0 0"}')
    done_count=$(echo "$stats" | awk '{print $1}')
    avg_min=$(echo "$stats" | awk '{print $2}')
    node_total=$(head -3 "$f" | tr '\r' '\n' | grep "This node:" | grep -oP '\d+ videos' | grep -oP '\d+')
    printf "%-8s %6s %6s %10s\n" "$node" "$done_count" "${node_total:-?}" "${avg_min}m"
    total_done=$((total_done + done_count))
    total_time=$(echo "$total_time + $done_count * $avg_min" | bc)
done

# Overall
echo ""
echo "=== Overall ==="
echo "Completed: ${completed} / ${TOTAL} (${pct}%)"

# Elapsed time from first node's start
start_time=$(head -5 "$LOG_DIR"/undistort_node0.log | tr '\r' '\n' | grep "Start time:" | sed 's/Start time: //')
if [[ -n "$start_time" ]]; then
    start_epoch=$(date -d "$start_time" +%s 2>/dev/null)
    now_epoch=$(date +%s)
    if [[ -n "$start_epoch" ]]; then
        elapsed_min=$(( (now_epoch - start_epoch) / 60 ))
        echo "Elapsed:   ${elapsed_min} min"

        if [[ "$completed" -gt 0 ]]; then
            remaining=$(( TOTAL - completed ))
            rate=$(echo "scale=2; $completed / $elapsed_min" | bc)
            eta_min=$(echo "scale=0; $remaining / $rate" | bc 2>/dev/null)
            echo "Rate:      ${rate} videos/min"
            echo "ETA:       ~${eta_min} min remaining"
            finish_epoch=$(( now_epoch + eta_min * 60 ))
            echo "Finish at: $(date -d @$finish_epoch '+%H:%M')"
        fi
    fi
fi

# Errors
err_count=0
for f in "$LOG_DIR"/undistort_node*.log; do
    n=$(cat "$f" | tr '\r' '\n' | grep -c -E "^ERROR|Traceback" 2>/dev/null || true)
    err_count=$((err_count + ${n:-0}))
done
if [[ "$err_count" -gt 0 ]]; then
    echo ""
    echo "WARNING: ${err_count} errors detected! Check logs."
fi

# Progress bar
bar_width=40
filled=$(( pct * bar_width / 100 ))
empty=$(( bar_width - filled ))
printf "\n[%s%s] %d%%\n" "$(printf '#%.0s' $(seq 1 $filled 2>/dev/null))" "$(printf '.%.0s' $(seq 1 $empty 2>/dev/null))" "$pct"