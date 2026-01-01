# CLIP Cluster Quick Start - S-BIAD499 Zebrafish Gastrulation

## 📁 Expected Directory Structure

On CLIP, your data should be organized as:
```
/users/andres.ortiz/data/zebrafish_test/
├── merged/
│   └── Merged.tif              ← Your merged TZCYX file (or rename to this)
├── nuclei_timelapses/          ← Created by step 00
├── membrane_timelapses/        ← Created by step 00
├── seg_nuclei_timelapses/      ← Created by step 01
├── seg_membrane_timelapses/    ← Created by step 01
├── oneat_detections/           ← Created by step 02
└── tracking/                   ← Created by step 05+
```

## 🔧 Before Running: Verify Your Setup

### 1. Check your input file name
The config expects `Merged.tif` in the `merged/` folder:
```bash
ls -la /users/andres.ortiz/data/zebrafish_test/merged/
```

If your file is named differently (e.g., `zebrafish_gastrulation_Merged.tif`), either:
- **Rename it:** `mv zebrafish_gastrulation_Merged.tif Merged.tif`
- **Or edit the config:** `conf/experiment_data_paths/sbiad499_clip.yaml`

### 2. Verify image dimensions
```bash
# Using Python in the container
singularity exec copenhagen_workflow.sif python -c "
from tifffile import imread
import sys
f = '/users/andres.ortiz/data/zebrafish_test/merged/Merged.tif'
data = imread(f)
print(f'Shape: {data.shape}')
print(f'Expected: (T, Z, C, Y, X) = (100, 149, 2, 1200, 1200)')
print(f'Dtype: {data.dtype}')
print(f'Size: {data.nbytes / 1e9:.1f} GB')
"
```

## 🚀 Running the Pipeline

### Submit SLURM jobs on CLIP

**Step 0: Split channels** (CPU is fine, but memory intensive)
```bash
#!/bin/bash
#SBATCH --job-name=zf_split
#SBATCH --partition=m           # memory partition for large files
#SBATCH --mem=64G               # Need RAM for 100x149x2x1200x1200 file
#SBATCH --time=01:00:00
#SBATCH --output=logs/split_%j.out

module load singularity

singularity exec copenhagen_workflow.sif python 00_create_nuclei_membrane_splits.py \
    experiment_data_paths=sbiad499_clip \
    parameters=sbiad499
```

**Step 1: Segment nuclei** (requires GPU)
```bash
#!/bin/bash
#SBATCH --job-name=zf_segment
#SBATCH --partition=g           # GPU partition
#SBATCH --gres=gpu:1            # Request 1 GPU (any type)
#SBATCH --mem=48G
#SBATCH --time=04:00:00
#SBATCH --output=logs/segment_%j.out

module load singularity

singularity exec --nv copenhagen_workflow.sif python 01_nuclei_segmentation_cellpose.py \
    experiment_data_paths=sbiad499_clip \
    parameters=sbiad499
```

### Interactive testing
```bash
# Request interactive GPU session
salloc --partition=g --gres=gpu:1 --mem=48G --time=02:00:00

# Inside the allocation
module load singularity

# Test that config loads correctly (dry run)
singularity exec --nv copenhagen_workflow.sif python -c "
import hydra
from omegaconf import DictConfig
from hydra import initialize, compose

with initialize(config_path='conf'):
    cfg = compose(config_name='scenario_segment_star_cellpose', 
                  overrides=['experiment_data_paths=sbiad499_clip', 'parameters=sbiad499'])
    print('Config loaded successfully!')
    print(f'Input file: {cfg.experiment_data_paths.input_merged_filename}')
    print(f'Nuclei dir: {cfg.experiment_data_paths.timelapse_nuclei_directory}')
    print(f'Voxel size: {cfg.experiment_data_paths.voxel_size_xyz}')
"
```

## ⚠️ Important Notes

1. **Hydra syntax**: Use `experiment_data_paths=sbiad499_clip` (config name), NOT a file path

2. **Parameters to use**: `parameters=sbiad499` is optimized for zebrafish at 0.65 µm/px

3. **Channel order**:
   - C0 = drl:GFP (mesoderm) → treated as "membrane"
   - C1 = H2B-RFP (nuclei)

4. **GPU types on CLIP partition `g`**:
   - P100 (16GB) - good for inference
   - V100 (32GB) - recommended for training
   - RTX 2080 Ti (11GB) - may need smaller batch size
   - A100 (40/80GB) - best for large batches

5. **Memory requirements**:
   - 100×149×1200×1200 = ~21 GB per channel at 16-bit
   - Request at least 48GB RAM for segmentation

## 🔍 Troubleshooting

**"Could not load experiment_data_paths/..."**
- Check that `sbiad499_clip.yaml` exists in `conf/experiment_data_paths/`
- Config names are case-sensitive!

**Out of memory**
- Increase `n_tiles` in `conf/parameters/sbiad499.yaml`: `n_tiles: [4, 8, 8]`
- Or reduce batch_size

**"File not found: Merged.tif"**
- Check `input_merged_filename` in `conf/experiment_data_paths/sbiad499_clip.yaml`
- Verify file exists at the expected location
