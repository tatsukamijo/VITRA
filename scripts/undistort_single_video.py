#!/usr/bin/env python3
"""Thin wrapper to undistort a single Ego4D video.

Calls process_single_video() from data/preprocessing/undistort_video.py.
Designed to be invoked by xargs in the parallel batch job.
"""

import argparse
import os
import resource
import sys
import time

def main():
    parser = argparse.ArgumentParser(description="Undistort a single Ego4D video.")
    parser.add_argument("--video_name", type=str, required=True,
                        help="Video UUID (without .mp4 extension)")
    parser.add_argument("--video_root", type=str,
                        default="/groups/gch51606/dataset/ego4d_airoa/raw/v2/full_scale",
                        help="Directory containing raw source videos")
    parser.add_argument("--intrinsics_root", type=str,
                        default="/groups/gch51606/dataset/vitra/intrinsics/ego4d",
                        help="Directory containing intrinsics .npy files")
    parser.add_argument("--save_root", type=str,
                        default="/groups/gch51606/dataset/vitra/Video/Ego4D_root",
                        help="Directory for saving undistorted videos")
    parser.add_argument("--batch_size", type=int, default=1000,
                        help="Frames per TS chunk")
    parser.add_argument("--crf", type=int, default=22,
                        help="CRF for ffmpeg encoding quality")
    args = parser.parse_args()

    # Idempotency: skip if output already exists
    output_path = os.path.join(args.save_root, f"{args.video_name}.mp4")
    if os.path.exists(output_path):
        print(f"SKIP: {args.video_name} (already exists at {output_path})")
        return

    # Validate inputs exist
    video_path = os.path.join(args.video_root, f"{args.video_name}.mp4")
    intrinsics_path = os.path.join(args.intrinsics_root, f"{args.video_name}.npy")
    if not os.path.exists(video_path):
        print(f"ERROR: Source video not found: {video_path}", file=sys.stderr)
        sys.exit(1)
    if not os.path.exists(intrinsics_path):
        print(f"ERROR: Intrinsics not found: {intrinsics_path}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(args.save_root, exist_ok=True)

    # Import process_single_video from existing preprocessing code
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "data", "preprocessing"))
    from undistort_video import process_single_video

    t0 = time.time()
    ru0_self = resource.getrusage(resource.RUSAGE_SELF)
    ru0_children = resource.getrusage(resource.RUSAGE_CHILDREN)

    process_single_video(
        video_name=args.video_name,
        video_root=args.video_root,
        intrinsics_root=args.intrinsics_root,
        save_root=args.save_root,
        batch_size=args.batch_size,
        crf=args.crf,
    )

    elapsed = time.time() - t0
    ru1_self = resource.getrusage(resource.RUSAGE_SELF)
    ru1_children = resource.getrusage(resource.RUSAGE_CHILDREN)
    # CPU time = self (cv2.remap) + children (ffmpeg subprocess)
    cpu_self = (ru1_self.ru_utime - ru0_self.ru_utime) + (ru1_self.ru_stime - ru0_self.ru_stime)
    cpu_children = (ru1_children.ru_utime - ru0_children.ru_utime) + (ru1_children.ru_stime - ru0_children.ru_stime)
    cpu_total = cpu_self + cpu_children
    avg_cores = cpu_total / elapsed if elapsed > 0 else 0
    output_size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f"DONE: {args.video_name} | {elapsed:.1f}s | {output_size_mb:.1f}MB | "
          f"CPU: {cpu_total:.1f}s (self:{cpu_self:.1f} ffmpeg:{cpu_children:.1f}) | "
          f"avg {avg_cores:.1f} cores")


if __name__ == "__main__":
    main()
