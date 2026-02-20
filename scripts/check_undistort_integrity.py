#!/usr/bin/env python3
"""Check undistorted videos for frame count mismatches.

Compares frame counts between original and undistorted videos using decord.
Videos with fewer frames than the original are likely truncated (walltime issues).

Usage:
    python scripts/check_undistort_integrity.py [--delete]
    python scripts/check_undistort_integrity.py --delete  # also delete broken files
"""

import argparse
import os
import sys
from concurrent.futures import ProcessPoolExecutor, as_completed

def check_video(video_name, original_root, undistorted_root):
    """Compare frame counts between original and undistorted video."""
    try:
        from decord import VideoReader
    except ImportError:
        # fallback: use ffprobe
        import subprocess
        def get_frame_count(path):
            result = subprocess.run(
                ["ffprobe", "-v", "quiet", "-select_streams", "v:0",
                 "-show_entries", "stream=nb_frames", "-of", "csv=p=0", path],
                capture_output=True, text=True
            )
            val = result.stdout.strip()
            if val and val != "N/A":
                return int(val)
            # fallback: count frames
            result = subprocess.run(
                ["ffprobe", "-v", "quiet", "-count_frames", "-select_streams", "v:0",
                 "-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", path],
                capture_output=True, text=True
            )
            return int(result.stdout.strip())

        orig_path = os.path.join(original_root, f"{video_name}.mp4")
        undist_path = os.path.join(undistorted_root, f"{video_name}.mp4")
        orig_frames = get_frame_count(orig_path)
        undist_frames = get_frame_count(undist_path)
        return video_name, orig_frames, undist_frames

    orig_path = os.path.join(original_root, f"{video_name}.mp4")
    undist_path = os.path.join(undistorted_root, f"{video_name}.mp4")

    vr_orig = VideoReader(orig_path)
    orig_frames = len(vr_orig)
    del vr_orig

    vr_undist = VideoReader(undist_path)
    undist_frames = len(vr_undist)
    del vr_undist

    return video_name, orig_frames, undist_frames


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--original_root", default="/groups/gch51606/dataset/ego4d_airoa/raw/v2/full_scale")
    parser.add_argument("--undistorted_root", default="/groups/gch51606/dataset/vitra/Video/Ego4D_root")
    parser.add_argument("--workers", type=int, default=16)
    parser.add_argument("--delete", action="store_true", help="Delete broken undistorted files")
    parser.add_argument("--output", type=str, default=None, help="Save broken video list to file")
    args = parser.parse_args()

    # Get list of undistorted videos
    undistorted_files = [f[:-4] for f in os.listdir(args.undistorted_root) if f.endswith(".mp4")]
    print(f"Checking {len(undistorted_files)} undistorted videos...")

    broken = []
    ok = 0
    errors = []

    with ProcessPoolExecutor(max_workers=args.workers) as executor:
        futures = {
            executor.submit(check_video, name, args.original_root, args.undistorted_root): name
            for name in undistorted_files
        }
        for i, future in enumerate(as_completed(futures)):
            name = futures[future]
            try:
                video_name, orig_frames, undist_frames = future.result()
                if undist_frames < orig_frames:
                    diff = orig_frames - undist_frames
                    pct = diff / orig_frames * 100
                    broken.append((video_name, orig_frames, undist_frames))
                    print(f"BROKEN: {video_name} — orig={orig_frames} undist={undist_frames} (missing {diff} frames, {pct:.1f}%)")
                else:
                    ok += 1
            except Exception as e:
                errors.append((name, str(e)))
                print(f"ERROR: {name} — {e}")

            if (i + 1) % 100 == 0:
                print(f"  Progress: {i+1}/{len(undistorted_files)} checked, {len(broken)} broken so far")

    # Summary
    print(f"\n=== Summary ===")
    print(f"OK:     {ok}")
    print(f"Broken: {len(broken)}")
    print(f"Errors: {len(errors)}")

    if broken:
        print(f"\nBroken videos:")
        for name, orig, undist in sorted(broken):
            print(f"  {name}: {undist}/{orig} frames")

        if args.delete:
            print(f"\nDeleting {len(broken)} broken files...")
            for name, _, _ in broken:
                path = os.path.join(args.undistorted_root, f"{name}.mp4")
                os.remove(path)
                print(f"  Deleted: {path}")
            print("Done. Re-run prepare_undistort_list.sh to generate new list, then re-undistort.")

        if args.output:
            with open(args.output, "w") as f:
                for name, _, _ in sorted(broken):
                    f.write(f"{name}\n")
            print(f"\nBroken list saved to: {args.output}")


if __name__ == "__main__":
    main()
