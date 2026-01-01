#!/usr/bin/env python
"""
merge_sbiad499.py - Convert S-BIAD499 zebrafish gastrulation data to pipeline format

This script takes the separate TIFF files from S-BIAD499 (per timepoint, per channel)
and merges them into a single 5D TIFF file compatible with CopenhagenWorkflow.

S-BIAD499 Dataset:
- Stage: Zebrafish gastrulation (shield stage onwards, ~6-14 hpf)
- Channel 0 (C0): drl:GFP - mesoderm marker
- Channel 1 (C1): H2B-RFP - all nuclei
- Format: Individual TIFF z-stacks per timepoint and channel

Output Format:
- TZCYX (Time, Z, Channel, Y, X)
- Channel 0: Mesoderm (for membrane-like segmentation)
- Channel 1: Nuclei (for nuclear segmentation)

Usage:
    python merge_sbiad499.py --input /path/to/wildtype-1 --output /path/to/output --name embryo1

Author: CopenhagenWorkflow
"""

import os
import argparse
import numpy as np
from tifffile import imread, imwrite
from glob import glob
from natsort import natsorted
from tqdm import tqdm


def parse_args():
    parser = argparse.ArgumentParser(
        description="Merge S-BIAD499 data into pipeline-compatible format"
    )
    parser.add_argument(
        "--input",
        "-i",
        required=True,
        help="Directory containing downloaded S-BIAD499 files (e.g., wildtype-1/)",
    )
    parser.add_argument(
        "--output", "-o", required=True, help="Output directory for merged TIFF"
    )
    parser.add_argument(
        "--name",
        "-n",
        default="zebrafish_gastrulation",
        help="Name prefix for output file",
    )
    parser.add_argument(
        "--max-timepoints",
        "-t",
        type=int,
        default=None,
        help="Maximum number of timepoints to process (for testing)",
    )
    parser.add_argument(
        "--chunk-size",
        "-c",
        type=int,
        default=50,
        help="Process in chunks of this many timepoints (for memory management)",
    )
    parser.add_argument(
        "--voxel-xy", type=float, default=0.5, help="XY pixel size in micrometers"
    )
    parser.add_argument(
        "--voxel-z", type=float, default=1.774, help="Z spacing in micrometers"
    )
    return parser.parse_args()


def find_files(input_dir):
    """Find and pair channel 0 and channel 1 files."""
    c0_files = natsorted(glob(os.path.join(input_dir, "*-C0.tiff")))
    c1_files = natsorted(glob(os.path.join(input_dir, "*-C1.tiff")))

    if len(c0_files) != len(c1_files):
        raise ValueError(
            f"Mismatch: {len(c0_files)} C0 files vs {len(c1_files)} C1 files"
        )

    if len(c0_files) == 0:
        # Try alternative extension
        c0_files = natsorted(glob(os.path.join(input_dir, "*-C0.tif")))
        c1_files = natsorted(glob(os.path.join(input_dir, "*-C1.tif")))

    return c0_files, c1_files


def get_dimensions(filepath):
    """Get dimensions from first file."""
    sample = imread(filepath)
    return sample.shape  # (Z, Y, X)


def merge_timepoints(c0_files, c1_files, max_t=None):
    """
    Merge all timepoints into single array.

    Returns:
        np.ndarray: Shape (T, Z, C, Y, X)
    """
    if max_t is not None:
        c0_files = c0_files[:max_t]
        c1_files = c1_files[:max_t]

    # Get dimensions from first file
    nz, ny, nx = get_dimensions(c0_files[0])
    nt = len(c0_files)
    nc = 2

    print(f"Dimensions: T={nt}, Z={nz}, C={nc}, Y={ny}, X={nx}")
    print(f"Estimated memory: {nt * nz * nc * ny * nx * 2 / 1e9:.1f} GB")

    # Allocate array
    merged = np.zeros((nt, nz, nc, ny, nx), dtype=np.uint16)

    # Load data
    for t, (f0, f1) in enumerate(
        tqdm(zip(c0_files, c1_files), total=nt, desc="Loading timepoints")
    ):
        # Channel 0 = mesoderm/membrane-like
        merged[t, :, 0, :, :] = imread(f0)
        # Channel 1 = nuclei
        merged[t, :, 1, :, :] = imread(f1)

    return merged


def save_merged(data, output_path, voxel_xy, voxel_z):
    """Save merged data as ImageJ-compatible TIFF."""
    print(f"Saving to: {output_path}")
    print(f"Shape: {data.shape} (TZCYX)")

    imwrite(
        output_path,
        data,
        imagej=True,
        photometric="minisblack",
        resolution=(1 / voxel_xy, 1 / voxel_xy),
        metadata={
            "spacing": voxel_z,
            "unit": "um",
            "axes": "TZCYX",
            "Channel": {0: "Mesoderm (drl:GFP)", 1: "Nuclei (H2B-RFP)"},
        },
    )

    print("Done!")


def main():
    args = parse_args()

    # Create output directory
    os.makedirs(args.output, exist_ok=True)

    # Find files
    print(f"Scanning: {args.input}")
    c0_files, c1_files = find_files(args.input)
    print(f"Found {len(c0_files)} timepoints")

    # Merge
    merged = merge_timepoints(c0_files, c1_files, args.max_timepoints)

    # Save
    output_path = os.path.join(args.output, f"{args.name}_Merged.tif")
    save_merged(merged, output_path, args.voxel_xy, args.voxel_z)

    print("\n" + "=" * 60)
    print("S-BIAD499 DATA MERGED SUCCESSFULLY")
    print("=" * 60)
    print(f"Output: {output_path}")
    print(f"Shape: {merged.shape}")
    print("\nChannel mapping:")
    print("  Channel 0: Mesoderm (drl:GFP) - use as 'membrane' channel")
    print("  Channel 1: Nuclei (H2B-RFP) - use as 'nuclei' channel")
    print("\nNext steps:")
    print("  1. Copy to your data directory")
    print("  2. Update conf/experiment_data_paths/zebrafish_gastrulation.yaml")
    print("  3. Run 00_create_nuclei_membrane_splits.py")


if __name__ == "__main__":
    main()
