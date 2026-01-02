#!/usr/bin/env python
"""
CZI to TIF Converter for CopenhagenWorkflow Pipeline

Converts multi-position CZI files from fluorescence microscopes to individual
TIFF files suitable for the CopenhagenWorkflow pipeline.

Author: CopenhagenWorkflow Team
Usage: python czi_to_tif_converter.py --input /path/to/file.czi --output /path/to/output_dir

For each position (embryo) in the CZI file, this creates:
  - A Merged.tif file with dimensions TZCYX
  - A metadata JSON file with acquisition parameters

Dependencies:
  - aicspylibczi (Zeiss CZI reader)
  - tifffile (TIFF writing)
  - numpy
"""

import os
import sys
import json
import argparse
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import numpy as np

try:
    from aicspylibczi import CziFile
    HAS_AICSPYLIBCZI = True
except ImportError:
    HAS_AICSPYLIBCZI = False

try:
    from czifile import CziFile as CziFileBackup
    HAS_CZIFILE = True
except ImportError:
    HAS_CZIFILE = False

from tifffile import imwrite


def get_czi_metadata(czi_path: str) -> Dict:
    """
    Extract metadata from CZI file.

    Returns dict with:
      - dimensions: {T, Z, C, Y, X, S (scenes/positions)}
      - voxel_size: [X, Y, Z] in micrometers
      - time_interval: in seconds
      - channel_names: list of channel names
      - positions: number of positions/scenes
    """
    if HAS_AICSPYLIBCZI:
        czi = CziFile(czi_path)

        # Get dimensions using aicspylibczi API
        # The size property returns the full bounding box shape
        # czi.dims gives dimension string like "STCZYX"
        # We need to use the size array along with dims string
        dims_str = czi.dims  # String like "STCZYX"
        size = czi.size  # Tuple of sizes for each dimension

        # Build dimension dictionary from dims string and size tuple
        dim_dict = {}
        if len(dims_str) == len(size):
            for i, dim_name in enumerate(dims_str):
                dim_dict[dim_name] = size[i]

        # Default values (will be overridden by actual metadata if available)
        voxel_x = 1.0
        voxel_y = 1.0
        voxel_z = 1.0
        time_interval = 300.0  # 5 minutes default

        # Try to extract from XML metadata
        try:
            # Pixel sizes are typically in Scaling/Items/Distance
            scaling = meta.find('.//Scaling')
            if scaling is not None:
                for item in scaling.findall('.//Distance'):
                    id_attr = item.get('Id')
                    value_elem = item.find('Value')
                    if value_elem is not None and value_elem.text:
                        # CZI stores in meters, convert to micrometers
                        value_um = float(value_elem.text) * 1e6
                        if id_attr == 'X':
                            voxel_x = value_um
                        elif id_attr == 'Y':
                            voxel_y = value_um
                        elif id_attr == 'Z':
                            voxel_z = value_um
        except Exception as e:
            print(f"Warning: Could not extract pixel sizes from metadata: {e}")

        # Try to get time interval
        try:
            time_incr = meta.find('.//TimeSeriesT/Interval/IncrementT')
            if time_incr is not None and time_incr.text:
                time_interval = float(time_incr.text)
        except Exception:
            pass

        # Channel names
        channel_names = []
        try:
            channels = meta.findall('.//Channel')
            for ch in channels:
                name = ch.get('Name') or ch.get('Id') or f"Channel_{len(channel_names)}"
                channel_names.append(name)
        except Exception:
            pass

        return {
            'dimensions': dim_dict,
            'voxel_size_xyz': [voxel_x, voxel_y, voxel_z],
            'time_interval_seconds': time_interval,
            'channel_names': channel_names,
            'n_positions': dim_dict.get('S', 1),
            'n_timepoints': dim_dict.get('T', 1),
            'n_z_slices': dim_dict.get('Z', 1),
            'n_channels': dim_dict.get('C', 1),
            'image_size_y': dim_dict.get('Y', 1),
            'image_size_x': dim_dict.get('X', 1),
        }

    elif HAS_CZIFILE:
        # Fallback to czifile library
        with CziFileBackup(czi_path) as czi:
            shape = czi.shape
            axes = czi.axes

            dim_dict = dict(zip(axes, shape))

            return {
                'dimensions': dim_dict,
                'voxel_size_xyz': [1.0, 1.0, 1.0],  # Default - need to extract from metadata
                'time_interval_seconds': 300.0,
                'channel_names': [],
                'n_positions': dim_dict.get('S', 1),
                'n_timepoints': dim_dict.get('T', 1),
                'n_z_slices': dim_dict.get('Z', 1),
                'n_channels': dim_dict.get('C', 1),
                'image_size_y': dim_dict.get('Y', 1),
                'image_size_x': dim_dict.get('X', 1),
            }
    else:
        raise ImportError(
            "No CZI reader available. Please install:\n"
            "  pip install aicspylibczi\n"
            "or:\n"
            "  pip install czifile"
        )


def read_czi_position(czi_path: str, position: int = 0) -> Tuple[np.ndarray, Dict]:
    """
    Read a single position from a multi-position CZI file.

    Args:
        czi_path: Path to CZI file
        position: Position/scene index (0-based)

    Returns:
        Tuple of (image_array, metadata_dict)
        image_array has shape (T, Z, C, Y, X)
    """
    if HAS_AICSPYLIBCZI:
        czi = CziFile(czi_path)

        # Read the specific scene/position
        # read_image returns (data, shape_list) where shape_list is [(dim, size), ...]
        data, shape_list = czi.read_image(S=position)

        # Convert shape_list to dict: [('B', 1), ('S', 1), ('C', 4), ...] -> {'B': 1, 'S': 1, 'C': 4, ...}
        shape_dict = {dim: size for dim, size in shape_list}

        # Get dimension order from czi.dims (e.g., "BSTCZYX")
        dims_str = czi.dims

        # We need to rearrange data to TZCYX format
        # First, identify current dimension positions
        current_axes = [dim for dim, _ in shape_list]

        # Squeeze out singleton dimensions that are not T, Z, C, Y, X
        # But keep track of which axes remain
        squeeze_axes = []
        for i, (dim, size) in enumerate(shape_list):
            if size == 1 and dim not in ['T', 'Z', 'C', 'Y', 'X']:
                squeeze_axes.append(i)

        if squeeze_axes:
            data = np.squeeze(data, axis=tuple(squeeze_axes))
            current_axes = [dim for i, dim in enumerate(current_axes) if i not in squeeze_axes]

        # Now transpose to TZCYX order
        target_order = ['T', 'Z', 'C', 'Y', 'X']

        # Add missing dimensions and build transpose order
        for target_dim in target_order:
            if target_dim not in current_axes:
                data = np.expand_dims(data, axis=0)
                current_axes.insert(0, target_dim)

        # Calculate transpose indices
        transpose_idx = [current_axes.index(dim) for dim in target_order]
        data = np.transpose(data, transpose_idx)

        meta = get_czi_metadata(czi_path)
        return data, meta

    elif HAS_CZIFILE:
        with CziFileBackup(czi_path) as czi:
            # Read full array
            data = czi.asarray()
            axes = czi.axes

            # Select position if multi-position
            if 'S' in axes:
                s_idx = axes.index('S')
                data = np.take(data, position, axis=s_idx)
                axes = axes.replace('S', '')

            # Squeeze and rearrange to TZCYX
            data = np.squeeze(data)

            while data.ndim < 5:
                data = np.expand_dims(data, axis=0)

            meta = get_czi_metadata(czi_path)
            return data, meta

    else:
        raise ImportError("No CZI reader available")


def convert_czi_to_tif(
    czi_path: str,
    output_dir: str,
    positions: Optional[List[int]] = None,
    output_prefix: str = "embryo",
    channel_mapping: Optional[Dict[str, int]] = None,
    override_voxel_size: Optional[List[float]] = None,
    override_time_interval: Optional[float] = None,
    verbose: bool = True
) -> List[str]:
    """
    Convert CZI file to TIF files for CopenhagenWorkflow.

    Args:
        czi_path: Path to input CZI file
        output_dir: Directory for output files
        positions: List of positions to extract (None = all)
        output_prefix: Prefix for output files (e.g., "embryo" -> "embryo_P01")
        channel_mapping: Dict mapping channel names to channel indices for reordering
                        e.g., {"membrane": 0, "nuclei": 2} to select specific channels
        override_voxel_size: Override voxel size [X, Y, Z] in µm
        override_time_interval: Override time interval in seconds
        verbose: Print progress

    Returns:
        List of created output file paths
    """
    if verbose:
        print(f"Reading CZI file: {czi_path}")

    # Get metadata
    meta = get_czi_metadata(czi_path)

    if verbose:
        print(f"CZI dimensions: {meta['dimensions']}")
        print(f"Positions: {meta['n_positions']}")
        print(f"Timepoints: {meta['n_timepoints']}")
        print(f"Z slices: {meta['n_z_slices']}")
        print(f"Channels: {meta['n_channels']} - {meta['channel_names']}")
        print(f"Image size: {meta['image_size_y']} x {meta['image_size_x']}")
        print(f"Voxel size (µm): {meta['voxel_size_xyz']}")
        print(f"Time interval (s): {meta['time_interval_seconds']}")

    # Override calibration if provided
    if override_voxel_size:
        meta['voxel_size_xyz'] = override_voxel_size
        if verbose:
            print(f"Using override voxel size: {override_voxel_size}")

    if override_time_interval:
        meta['time_interval_seconds'] = override_time_interval
        if verbose:
            print(f"Using override time interval: {override_time_interval}")

    # Determine positions to process
    n_positions = meta['n_positions']
    if positions is None:
        positions = list(range(n_positions))

    if verbose:
        print(f"\nProcessing positions: {positions}")

    # Create output directory
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    created_files = []

    for pos in positions:
        if verbose:
            print(f"\n{'='*60}")
            print(f"Processing position {pos+1}/{n_positions} (P{pos:02d})")
            print(f"{'='*60}")

        # Create position-specific output directory
        pos_dir = output_path / f"{output_prefix}_P{pos:02d}"
        pos_dir.mkdir(exist_ok=True)
        merged_dir = pos_dir / "merged"
        merged_dir.mkdir(exist_ok=True)

        # Read position data
        data, _ = read_czi_position(czi_path, pos)

        if verbose:
            print(f"Raw data shape: {data.shape}")

        # Apply channel mapping if specified
        if channel_mapping:
            n_output_channels = len(channel_mapping)
            # Extract specified channels in order
            channel_indices = list(channel_mapping.values())
            data = data[:, :, channel_indices, :, :]
            if verbose:
                print(f"Selected channels {channel_indices}, new shape: {data.shape}")

        # Ensure data is in correct dtype (16-bit)
        if data.dtype != np.uint16:
            # Normalize and convert
            if data.max() > 0:
                if data.dtype == np.float32 or data.dtype == np.float64:
                    # Floating point - normalize to 0-65535
                    data = ((data - data.min()) / (data.max() - data.min()) * 65535).astype(np.uint16)
                elif data.max() <= 255:
                    # 8-bit - scale up
                    data = (data.astype(np.uint16) * 256)
                else:
                    data = data.astype(np.uint16)
            else:
                data = data.astype(np.uint16)

        # Write merged TIFF
        output_tif = merged_dir / "Merged.tif"
        voxel = meta['voxel_size_xyz']

        if verbose:
            print(f"Writing: {output_tif}")
            print(f"Shape: {data.shape} (TZCYX)")

        imwrite(
            str(output_tif),
            data,
            imagej=True,
            bigtiff=True,
            photometric='minisblack',
            resolution=(1 / voxel[0], 1 / voxel[1]),
            metadata={
                'spacing': voxel[2],
                'unit': 'um',
                'axes': 'TZCYX',
                'fps': 1.0 / meta['time_interval_seconds'] if meta['time_interval_seconds'] > 0 else 1.0
            }
        )

        created_files.append(str(output_tif))

        # Write metadata JSON
        pos_meta = {
            'source_file': os.path.basename(czi_path),
            'position': pos,
            'position_name': f"{output_prefix}_P{pos:02d}",
            'dimensions': {
                'T': data.shape[0],
                'Z': data.shape[1],
                'C': data.shape[2],
                'Y': data.shape[3],
                'X': data.shape[4]
            },
            'voxel_size_xyz_um': voxel,
            'time_interval_seconds': meta['time_interval_seconds'],
            'channel_names': meta['channel_names'] if not channel_mapping else list(channel_mapping.keys()),
            'channel_mapping_used': channel_mapping,
            'output_file': str(output_tif)
        }

        meta_file = pos_dir / "acquisition_metadata.json"
        with open(meta_file, 'w') as f:
            json.dump(pos_meta, f, indent=2)

        if verbose:
            print(f"Metadata saved: {meta_file}")

    if verbose:
        print(f"\n{'='*60}")
        print("CONVERSION COMPLETE")
        print(f"{'='*60}")
        print(f"Created {len(created_files)} TIF files:")
        for f in created_files:
            print(f"  - {f}")

    return created_files


def main():
    parser = argparse.ArgumentParser(
        description="Convert CZI files to TIF for CopenhagenWorkflow pipeline",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Convert all positions from a CZI file
  python czi_to_tif_converter.py --input data.czi --output /scratch/medaka_data

  # Convert specific positions (0, 1, 3)
  python czi_to_tif_converter.py --input data.czi --output /scratch/medaka_data --positions 0 1 3

  # Override voxel size and time interval
  python czi_to_tif_converter.py --input data.czi --output /scratch/medaka_data \\
      --voxel-size 2.0 2.0 100.0 --time-interval 300

  # Specify channel mapping (membrane=channel0, nuclei=channel1)
  python czi_to_tif_converter.py --input data.czi --output /scratch/medaka_data \\
      --membrane-channel 0 --nuclei-channel 1

Output structure:
  output_dir/
  ├── embryo_P00/
  │   ├── merged/
  │   │   └── Merged.tif        # Pipeline input
  │   └── acquisition_metadata.json
  ├── embryo_P01/
  │   ├── merged/
  │   │   └── Merged.tif
  │   └── acquisition_metadata.json
  ...
"""
    )

    parser.add_argument('--input', '-i', required=True,
                        help='Input CZI file path')
    parser.add_argument('--output', '-o', required=True,
                        help='Output directory')
    parser.add_argument('--positions', '-p', type=int, nargs='+', default=None,
                        help='Position indices to extract (0-based). Default: all')
    parser.add_argument('--prefix', default='embryo',
                        help='Output file prefix (default: embryo)')
    parser.add_argument('--membrane-channel', type=int, default=None,
                        help='Channel index for membrane marker (e.g., PBra-Venus=0)')
    parser.add_argument('--nuclei-channel', type=int, default=None,
                        help='Channel index for nuclei marker (e.g., H2A-mCherry=1)')
    parser.add_argument('--dextran-channel', type=int, default=None,
                        help='Channel index for injection marker (dextran-647). Will be excluded.')
    parser.add_argument('--voxel-size', type=float, nargs=3, default=None,
                        metavar=('X', 'Y', 'Z'),
                        help='Voxel size in micrometers [X Y Z]')
    parser.add_argument('--time-interval', type=float, default=None,
                        help='Time interval between frames in seconds')
    parser.add_argument('--info-only', action='store_true',
                        help='Only print CZI metadata, do not convert')
    parser.add_argument('--quiet', '-q', action='store_true',
                        help='Suppress progress output')

    args = parser.parse_args()

    # Verify input file exists
    if not os.path.exists(args.input):
        print(f"Error: Input file not found: {args.input}")
        sys.exit(1)

    # If info-only, just print metadata
    if args.info_only:
        meta = get_czi_metadata(args.input)
        print("\nCZI File Information:")
        print("=" * 60)
        print(f"File: {args.input}")
        print(f"Dimensions: {meta['dimensions']}")
        print(f"Positions (embryos): {meta['n_positions']}")
        print(f"Timepoints: {meta['n_timepoints']}")
        print(f"Z slices: {meta['n_z_slices']}")
        print(f"Channels: {meta['n_channels']}")
        print(f"Channel names: {meta['channel_names']}")
        print(f"Image size: {meta['image_size_y']} x {meta['image_size_x']}")
        print(f"Voxel size (µm): X={meta['voxel_size_xyz'][0]:.3f}, Y={meta['voxel_size_xyz'][1]:.3f}, Z={meta['voxel_size_xyz'][2]:.3f}")
        print(f"Time interval: {meta['time_interval_seconds']:.1f} seconds")
        print("=" * 60)
        sys.exit(0)

    # Build channel mapping if specified
    channel_mapping = None
    if args.membrane_channel is not None and args.nuclei_channel is not None:
        channel_mapping = {
            'membrane': args.membrane_channel,
            'nuclei': args.nuclei_channel
        }
        # Note: We only include membrane and nuclei channels
        # Dextran channel is excluded by not including it

    # Convert
    convert_czi_to_tif(
        czi_path=args.input,
        output_dir=args.output,
        positions=args.positions,
        output_prefix=args.prefix,
        channel_mapping=channel_mapping,
        override_voxel_size=args.voxel_size,
        override_time_interval=args.time_interval,
        verbose=not args.quiet
    )


if __name__ == '__main__':
    main()
