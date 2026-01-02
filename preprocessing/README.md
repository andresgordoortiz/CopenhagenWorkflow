# Medaka Preprocessing Scripts

This folder contains preprocessing utilities for converting raw microscopy data to the format required by the CopenhagenWorkflow pipeline.

## CZI to TIF Converter

The main script `czi_to_tif_converter.py` converts multi-position CZI files (Zeiss format) to individual TIF files.

### Features

- Extracts individual positions (embryos) from multi-position CZI files
- Converts to TZCYX format required by pipeline
- Supports channel selection and reordering
- Preserves/overrides voxel calibration
- Generates metadata JSON for each position

### Requirements

Install one of the CZI reading libraries:

```bash
# Preferred (newer, better maintained)
pip install aicspylibczi

# Alternative
pip install czifile
```

### Usage

#### Check CZI file contents

```bash
python preprocessing/czi_to_tif_converter.py \
    --input /path/to/data.czi \
    --output /tmp \
    --info-only
```

Output example:
```
CZI File Information:
============================================================
File: M34_PBra_Venus_H2A_mCherry.czi
Positions (embryos): 10
Timepoints: 576
Z slices: 7
Channels: 4
Channel names: ['BF', 'AF488', 'mCherry', 'dextran-647']
Image size: 2048 x 2048
Voxel size (µm): X=2.000, Y=2.000, Z=100.000
Time interval: 300.0 seconds
============================================================
```

#### Convert all positions

```bash
python preprocessing/czi_to_tif_converter.py \
    --input /path/to/data.czi \
    --output /scratch/medaka/converted \
    --prefix M34_embryo \
    --membrane-channel 1 \
    --nuclei-channel 2 \
    --voxel-size 2.0 2.0 100.0 \
    --time-interval 300
```

#### Convert specific positions only

```bash
# Only control embryos (P0, P2, P3), excluding mCherry-negative P1
python preprocessing/czi_to_tif_converter.py \
    --input /path/to/data.czi \
    --output /scratch/medaka/converted \
    --positions 0 2 3 \
    --membrane-channel 1 \
    --nuclei-channel 2
```

### Output Structure

```
output_dir/
├── M34_embryo_P00/
│   ├── merged/
│   │   └── Merged.tif        # Pipeline-ready TZCYX file
│   └── acquisition_metadata.json
├── M34_embryo_P01/
│   ├── merged/
│   │   └── Merged.tif
│   └── acquisition_metadata.json
...
```

### Channel Mapping

For the M34 Medaka data:

| CZI Channel | Index | Marker | Pipeline Role |
|-------------|-------|--------|---------------|
| BF | 0 | Brightfield | **Exclude** |
| AF488 | 1 | PBra-Venus | Membrane (mesoderm) |
| mCherry | 2 | H2A-mCherry | Nuclei |
| dextran-647 | 3 | Injection marker | **Exclude** |

Use `--membrane-channel 1 --nuclei-channel 2` to select only the relevant channels.

### SLURM Integration

See `sbatch_scripts/medaka/00_convert_czi.sh` for the SLURM batch script.

---

## Future Extensions

Potential additions:
- ND2 converter (Nikon format)
- LIF converter (Leica format)
- OIB/OIF converter (Olympus format)
- Batch conversion scripts for multiple CZI files
