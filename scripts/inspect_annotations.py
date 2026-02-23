#!/usr/bin/env python3
"""Inspect Ego4D annotation structure and language instructions.

Usage:
    python scripts/inspect_annotations.py
    python scripts/inspect_annotations.py --num_episodes 5
    python scripts/inspect_annotations.py --dataset ego4d_other
"""

import argparse
import os
import numpy as np
from pathlib import Path


def inspect_episode(npy_path):
    """Load and inspect a single episode annotation."""
    epi = np.load(npy_path, allow_pickle=True).item()

    print(f"\n{'='*80}")
    print(f"Episode file: {os.path.basename(npy_path)}")
    print(f"{'='*80}")

    # Top-level keys
    print(f"\nTop-level keys: {list(epi.keys())}")

    # Video info
    print(f"\nvideo_name: {epi.get('video_name', 'N/A')}")
    print(f"anno_type (primary hand): {epi.get('anno_type', 'N/A')}")

    # Shapes
    if 'extrinsics' in epi:
        print(f"extrinsics shape: {epi['extrinsics'].shape}  (T, 4, 4) => T={epi['extrinsics'].shape[0]} frames")
    if 'intrinsics' in epi:
        print(f"intrinsics shape: {epi['intrinsics'].shape}")
    if 'video_decode_frame' in epi:
        vdf = epi['video_decode_frame']
        print(f"video_decode_frame: len={len(vdf)}, range=[{vdf.min()}, {vdf.max()}]")

    # Hand data summary
    for hand in ['left', 'right']:
        if hand in epi:
            h = epi[hand]
            print(f"\n--- {hand} hand ---")
            print(f"  keys: {list(h.keys())}")
            if 'kept_frames' in h:
                kept = h['kept_frames']
                print(f"  kept_frames: {kept.sum()}/{len(kept)} frames tracked ({kept.sum()/len(kept)*100:.1f}%)")
            if 'global_orient_worldspace' in h:
                print(f"  global_orient shape: {h['global_orient_worldspace'].shape}")
            if 'hand_pose' in h:
                print(f"  hand_pose shape: {h['hand_pose'].shape}")
            if 'beta' in h:
                print(f"  beta shape: {np.array(h['beta']).shape}")

    # === Language instructions (main focus) ===
    print(f"\n{'~'*60}")
    print(f"LANGUAGE INSTRUCTIONS")
    print(f"{'~'*60}")

    if 'text' in epi:
        text = epi['text']
        print(f"\ntext keys: {list(text.keys())}")
        for hand in ['left', 'right']:
            if hand in text:
                instructions = text[hand]
                print(f"\n  [{hand}] {len(instructions)} instruction(s):")
                for i, item in enumerate(instructions):
                    if isinstance(item, tuple) and len(item) == 2:
                        txt, (start, end) = item
                        duration = end - start
                        print(f"    [{i}] frames {start:>5d}-{end:>5d} ({duration:>4d} frames): \"{txt}\"")
                    else:
                        print(f"    [{i}] {item}")
    else:
        print("  No 'text' key found!")

    # Rephrased instructions
    if 'text_rephrase' in epi and epi['text_rephrase'] is not None:
        text_rephrase = epi['text_rephrase']
        print(f"\ntext_rephrase keys: {list(text_rephrase.keys()) if isinstance(text_rephrase, dict) else type(text_rephrase)}")
        for hand in ['left', 'right']:
            if isinstance(text_rephrase, dict) and hand in text_rephrase:
                rp = text_rephrase[hand]
                print(f"\n  [{hand}] rephrase entries: {len(rp)}")
                for i, item in enumerate(rp[:3]):  # show first 3
                    if isinstance(item, (list, tuple)) and len(item) > 0:
                        if isinstance(item[0], list):
                            print(f"    [{i}] {len(item[0])} rephrases: {item[0][:2]}...")
                        else:
                            print(f"    [{i}] {item}")
    else:
        print("\n  No text_rephrase (or None)")

    return epi


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data_root", default="/groups/gch51606/dataset/vitra")
    parser.add_argument("--dataset", default="ego4d_cooking_and_cleaning",
                        choices=["ego4d_cooking_and_cleaning", "ego4d_other"])
    parser.add_argument("--num_episodes", type=int, default=3)
    args = parser.parse_args()

    anno_dir = Path(args.data_root) / "Annotation" / args.dataset / "episodic_annotations"

    # Also inspect the index file
    index_path = Path(args.data_root) / "Annotation" / args.dataset / "episode_frame_index.npz"
    if index_path.exists():
        idx = np.load(index_path, allow_pickle=True)
        print(f"=== Index file: {index_path.name} ===")
        print(f"Keys: {list(idx.keys())}")
        if 'index_frame_pair' in idx:
            ifp = idx['index_frame_pair']
            print(f"index_frame_pair: shape={ifp.shape}, dtype={ifp.dtype}")
            print(f"  Total training samples: {len(ifp)}")
            print(f"  First 5: {ifp[:5]}")
        if 'index_to_episode_id' in idx:
            ite = idx['index_to_episode_id']
            print(f"index_to_episode_id: {len(ite)} unique episodes")
            print(f"  First 5: {ite[:5]}")

    # Pick some episode files
    npy_files = sorted(anno_dir.glob("*.npy"))
    print(f"\nTotal episode files in {args.dataset}: {len(npy_files)}")

    # Sample diverse episodes (beginning, middle, end)
    if len(npy_files) > args.num_episodes:
        step = len(npy_files) // args.num_episodes
        selected = [npy_files[i * step] for i in range(args.num_episodes)]
    else:
        selected = npy_files[:args.num_episodes]

    all_instructions = []
    for f in selected:
        epi = inspect_episode(f)
        if 'text' in epi:
            for hand in ['left', 'right']:
                if hand in epi['text']:
                    for item in epi['text'][hand]:
                        if isinstance(item, tuple) and len(item) == 2:
                            all_instructions.append(item[0])

    # Summary
    print(f"\n{'='*80}")
    print(f"SUMMARY")
    print(f"{'='*80}")
    print(f"Inspected {len(selected)} episodes")
    print(f"Total instruction segments found: {len(all_instructions)}")
    print(f"\nAll unique instructions:")
    for i, txt in enumerate(sorted(set(all_instructions))):
        print(f"  {i+1}. \"{txt}\"")


if __name__ == "__main__":
    main()
