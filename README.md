# CopenhagenWorkflow

**4D Cell Tracking and Fate Analysis Pipeline**

A complete pipeline for single-cell tracking and morphodynamic analysis of 4D microscopy data (3D + time). Originally developed for Xenopus mucociliary epithelium, adapted for zebrafish embryo imaging from 0 hpf through gastrulation.

---

## Quick Start

```bash
# 1. Pull container
singularity pull copenhagen_workflow.sif docker://ghcr.io/andresgordoortiz/copenhagenworkflow:latest

# 2. Run on HPC (CLIP cluster)
srun --partition=g --gres=gpu:A100:1 --mem=64G --time=4:00:00 --pty bash
singularity exec --nv copenhagen_workflow.sif python 01_nuclei_segmentation.py experiment_data_paths=my_data
```

---

## Table of Contents

1. [What This Pipeline Does](#what-this-pipeline-does)
2. [Installation](#installation)
3. [Running the Pipeline](#running-the-pipeline)
4. [HPC Setup (CLIP Cluster)](#hpc-setup-clip-cluster)
5. [Configuration](#configuration)
6. [Zebrafish Adaptations](#zebrafish-adaptations)
7. [Troubleshooting](#troubleshooting)

---

## What This Pipeline Does

### Overview

This workflow processes 4D microscopy timelapse data through these stages:

```
Input: Merged.tif (5D: TZCYX)
         │
         ▼
┌─────────────────────────────────────┐
│  SEGMENTATION                       │
│  • Nuclei: StarDist3D               │
│  • Membrane: Cellpose + 3D stitch   │
│  • Denoising: CARE                  │
└─────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  EVENT DETECTION                    │
│  • Mitosis: Oneat (DenseNet)        │
│  • Non-maximum suppression          │
└─────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  TRACKING                           │
│  • TrackMate (Fiji)                 │
│  • Division-aware linking           │
└─────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  ANALYSIS                           │
│  • Shape features extraction        │
│  • Morphodynamic analysis           │
│  • Cell fate classification         │
└─────────────────────────────────────┘
         │
         ▼
Output: Per-cell tracks with features
```

### Pipeline Steps

| Step | Script | Description | Compute |
|------|--------|-------------|---------|
| 00 | `00_create_nuclei_membrane_splits.py` | Split channels from merged timelapse | CPU |
| 01a | `01_nuclei_segmentation.py` | StarDist3D nuclei segmentation | **GPU** |
| 01b | `01_enhance_membrane.py` | CARE denoising for membrane | **GPU** |
| 01c | `01_vollcellpose_membrane_segmentation.py` | Cellpose membrane segmentation | **GPU** |
| 02 | `02_oneat_nuclei.py` | Mitosis detection with Oneat | **GPU** |
| 03 | `03_nms_nuclei_automated.py` | Deduplicate detections | CPU |
| 04 | `04_prepare_tracking.py` | Prepare data for TrackMate | CPU |
| 05 | `05_automate_trackmate.py` | TrackMate tracking (Fiji) | CPU |
| 06 | `06_master_tracking.py` | Master track assembly | CPU |
| 07 | `07_masterxml_dataframe.py` | Extract features to dataframe | CPU |
| 10 | `10_cell_type_dataframe_generator.py` | Cell fate classification | CPU |

### What You Get

- **Segmentation masks**: Per-timepoint 3D label images for nuclei and membranes
- **Mitosis events**: CSV with detected division locations (T, Z, Y, X, confidence)
- **Cell tracks**: XML files with linked cell identities across time
- **Feature dataframes**: CSV with per-cell morphodynamic features:
  - Shape: volume, surface area, sphericity, eccentricity
  - Dynamics: velocity, acceleration, displacement, MSD
  - Neighbors: count, distances, local density

---

## Installation

### Container (Recommended)

The container includes all dependencies: TensorFlow, PyTorch, Cellpose, StarDist, Oneat, Fiji, etc.

```bash
# Pull pre-built container from GitHub Container Registry
singularity pull copenhagen_workflow.sif docker://ghcr.io/andresgordoortiz/copenhagenworkflow:latest
```

### Build Locally (Optional)

```bash
# Clone repository
git clone https://github.com/andresgordoortiz/CopenhagenWorkflow.git
cd CopenhagenWorkflow

# Build with Docker
docker build -t copenhagenworkflow:latest .

# Convert to Singularity
singularity build copenhagen_workflow.sif docker-daemon://copenhagenworkflow:latest
```

### Verify Installation

```bash
singularity exec --nv copenhagen_workflow.sif python -c "
import tensorflow as tf
import torch
from cellpose import version as cp_version
import stardist
print(f'TensorFlow: {tf.__version__}')
print(f'PyTorch: {torch.__version__}')
print(f'Cellpose: {cp_version}')
print(f'StarDist: {stardist.__version__}')
print(f'GPU (TF): {len(tf.config.list_physical_devices(\"GPU\"))}')
print(f'GPU (PyTorch): {torch.cuda.is_available()}')
"
```

---

## Running the Pipeline

### Input Data Format

**Required**: `Merged.tif` - 5D TIFF stack
- Dimension order: TZCYX (Time, Z, Channel, Y, X)
- Channel 0: Membrane marker (or mesoderm marker like drl:GFP)
- Channel 1: Nuclear marker (H2B-RFP or similar)
- Bit depth: 16-bit

### Step-by-Step Execution

```bash
# Set up your data config first (see Configuration section)

# Step 00: Split channels
singularity exec copenhagen_workflow.sif python 00_create_nuclei_membrane_splits.py \
    experiment_data_paths=my_data

# Step 01: Segmentation (GPU required)
singularity exec --nv copenhagen_workflow.sif python 01_nuclei_segmentation.py \
    experiment_data_paths=my_data parameters=zebrafish

singularity exec --nv copenhagen_workflow.sif python 01_enhance_membrane.py \
    experiment_data_paths=my_data

singularity exec --nv copenhagen_workflow.sif python 01_vollcellpose_membrane_segmentation.py \
    experiment_data_paths=my_data parameters=zebrafish

# Step 02: Mitosis detection (GPU required)
singularity exec --nv copenhagen_workflow.sif python 02_oneat_nuclei.py \
    experiment_data_paths=my_data parameters=oneat_zebrafish

# Step 03: Non-maximum suppression
singularity exec copenhagen_workflow.sif python 03_nms_nuclei_automated.py \
    experiment_data_paths=my_data

# Step 04-05: Tracking
singularity exec copenhagen_workflow.sif python 04_prepare_tracking.py \
    experiment_data_paths=my_data

singularity exec copenhagen_workflow.sif /opt/Fiji.app/fiji-linux-x64 --headless \
    --run 05_automate_trackmate.py

# Step 06-07: Feature extraction
singularity exec copenhagen_workflow.sif python 06_master_tracking.py \
    experiment_data_paths=my_data

singularity exec copenhagen_workflow.sif python 07_masterxml_dataframe.py \
    experiment_data_paths=my_data

# Step 10: Cell fate classification
singularity exec copenhagen_workflow.sif python 10_cell_type_dataframe_generator.py \
    experiment_data_paths=my_data
```

---

## HPC Setup (CLIP Cluster)

### Available Partitions

| Partition | Nodes | GPUs | Best For |
|-----------|-------|------|----------|
| `g` | clip-g1-[0-6] | P100 ×8 | Basic GPU work |
| `g` | clip-g2-[0-3] | V100 ×4 | Segmentation |
| `g` | clip-g3-[0-9] | RTX ×4 | Fast inference |
| `g` | clip-g4-[0-11] | **A100 ×4** | **Recommended** |
| `c` | clip-c1/c2-* | CPU only | Fiji, feature extraction |
| `m` | clip-m1/m2-* | High memory | Large datasets |

### Interactive Session

```bash
# GPU session on A100 (recommended)
srun --partition=g --nodelist=clip-g4-0 --gres=gpu:A100:1 \
     --cpus-per-task=8 --mem=64G --time=4:00:00 --pty bash

# Alternative: V100
srun --partition=g --nodelist=clip-g2-0 --gres=gpu:V100:1 \
     --cpus-per-task=8 --mem=64G --time=4:00:00 --pty bash

# CPU-only session (Fiji, feature extraction)
srun --partition=c --cpus-per-task=16 --mem=64G --time=4:00:00 --pty bash

# Inside session:
module load singularity  # if needed
singularity exec --nv --bind /scratch/$USER:/data copenhagen_workflow.sif \
    python 01_nuclei_segmentation.py experiment_data_paths=my_data
```

### Batch Job Template

```bash
#!/bin/bash
#SBATCH --job-name=cell_tracking
#SBATCH --partition=g
#SBATCH --nodelist=clip-g4-0
#SBATCH --gres=gpu:A100:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=8:00:00
#SBATCH --output=logs/%j_%x.out
#SBATCH --error=logs/%j_%x.err

# Load modules
module load singularity 2>/dev/null || true

# Set paths
CONTAINER="/home/$USER/copenhagen_workflow.sif"
WORKDIR="/scratch/$USER/zebrafish_project"

# Bind paths and run
singularity exec --nv \
    --bind $WORKDIR:/data \
    --bind /scratch/$USER/models:/models \
    $CONTAINER python 01_nuclei_segmentation.py \
    experiment_data_paths=my_data \
    parameters=zebrafish

echo "Job completed: $(date)"
```

### Full Pipeline Script

Save as `run_pipeline.sh`:

```bash
#!/bin/bash
#SBATCH --job-name=full_pipeline
#SBATCH --partition=g
#SBATCH --gres=gpu:A100:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=logs/%j_pipeline.out

CONTAINER="copenhagen_workflow.sif"
CONFIG="experiment_data_paths=my_data parameters=zebrafish"

echo "=== Step 00: Channel splitting ==="
singularity exec $CONTAINER python 00_create_nuclei_membrane_splits.py $CONFIG

echo "=== Step 01: Segmentation ==="
singularity exec --nv $CONTAINER python 01_nuclei_segmentation.py $CONFIG
singularity exec --nv $CONTAINER python 01_enhance_membrane.py $CONFIG
singularity exec --nv $CONTAINER python 01_vollcellpose_membrane_segmentation.py $CONFIG

echo "=== Step 02: Mitosis detection ==="
singularity exec --nv $CONTAINER python 02_oneat_nuclei.py $CONFIG

echo "=== Step 03: NMS ==="
singularity exec $CONTAINER python 03_nms_nuclei_automated.py $CONFIG

echo "=== Step 04-05: Tracking ==="
singularity exec $CONTAINER python 04_prepare_tracking.py $CONFIG
singularity exec $CONTAINER /opt/Fiji.app/fiji-linux-x64 --headless --run 05_automate_trackmate.py

echo "=== Step 06-07: Features ==="
singularity exec $CONTAINER python 06_master_tracking.py $CONFIG
singularity exec $CONTAINER python 07_masterxml_dataframe.py $CONFIG

echo "=== Done! ==="
```

Submit with: `sbatch run_pipeline.sh`

---

## Configuration

### Create Your Dataset Config

Create `conf/experiment_data_paths/my_data.yaml`:

```yaml
# Dataset name
timelapse_nuclei_to_track: 'embryo1'
timelapse_membrane_to_track: 'embryo1'

# Base directory
base_directory: '/scratch/andres.ortiz/zebrafish/'

# Input/output directories
timelapse_nuclei_directory: '/scratch/andres.ortiz/zebrafish/nuclei_timelapses/'
timelapse_seg_nuclei_directory: '/scratch/andres.ortiz/zebrafish/seg_nuclei_timelapses/'
timelapse_membrane_directory: '/scratch/andres.ortiz/zebrafish/membrane_timelapses/'
timelapse_seg_membrane_directory: '/scratch/andres.ortiz/zebrafish/seg_membrane_timelapses/'
timelapse_oneat_directory: '/scratch/andres.ortiz/zebrafish/oneat_detections/'
tracking_directory: '/scratch/andres.ortiz/zebrafish/tracking/'

# CRITICAL: Match your microscope settings!
voxel_size_xyz: [0.5, 0.5, 1.774]    # X, Y, Z in micrometers
time_interval_seconds: 42             # Time between frames
```

### Parameter Override

```bash
# Override single parameter
python script.py parameters.diameter_cellpose=18.0

# Override multiple
python script.py parameters.min_size=50 parameters.n_tiles=[4,8,8]

# Use different config files
python script.py experiment_data_paths=embryo2 parameters=zebrafish_late
```

---

## Zebrafish Adaptations

### Key Differences from Xenopus

| Parameter | Xenopus | Zebrafish |
|-----------|---------|-----------|
| Cell diameter | ~34 px | **~12-18 px** |
| `diameter_cellpose` | 34 | **16** |
| `min_size` | 100 | **30** |
| Division time | hours | **15-20 min** |
| Z spacing | 2 µm | **~1.77 µm** |

### Recommended Test Dataset

**S-BIAD499** (BioStudies) - Zebrafish gastrulation with drl:GFP (mesoderm) + H2B-RFP (nuclei):

```bash
# Download utility
./utils/download_test_data.sh /scratch/$USER/zebrafish_data 50

# Merge channels into pipeline format
singularity exec copenhagen_workflow.sif python utils/merge_sbiad499.py \
    -i /scratch/$USER/zebrafish_data/wildtype-1 \
    -o /scratch/$USER/zebrafish_data/merged \
    -t 50
```

### Developmental Stages

| Stage | hpf | Notes |
|-------|-----|-------|
| Sphere | 4 | ~1000 cells, ~15 µm diameter |
| **Shield** | **6** | **Gastrulation starts** |
| 75% epiboly | 8 | Mid-gastrulation |
| **Bud** | **10** | **Late gastrulation** |
| Somitogenesis | 10.5+ | Post-gastrulation |

---

## Troubleshooting

### GPU Not Detected

```bash
# Must use --nv flag
singularity exec --nv copenhagen_workflow.sif nvidia-smi

# Check GPU partition
sinfo -p g -o "%N %G"
```

### Out of Memory

```yaml
# In your parameters yaml, increase tiling:
n_tiles: [4, 8, 8]  # Process smaller chunks
```

### Wrong Cell Sizes

Cellpose diameter is critical! Test interactively:

```bash
# Launch Cellpose GUI
singularity exec --nv copenhagen_workflow.sif python -m cellpose --gui

# Measure cells in Napari
singularity exec --nv copenhagen_workflow.sif napari
```

### Fiji/TrackMate Issues

```bash
# Test Fiji
singularity exec copenhagen_workflow.sif /opt/Fiji.app/fiji-linux-x64 --headless --help

# Update Fiji plugins
singularity exec copenhagen_workflow.sif /opt/Fiji.app/fiji-linux-x64 --headless --update update
```

### Import Errors

```bash
# Verify all packages
singularity exec copenhagen_workflow.sif python -c "
import cellpose, stardist, tensorflow, torch
print('All imports OK')
"
```

---

## Citation

If you use this workflow:

> Tolonen, M., Xu, Z., Beker, O., Kapoor, V., Dumitrascu, B., & Sedzinski, J. (2024).
> Single-cell morphodynamics predicts cell fate decisions during Xenopus mucociliary differentiation.

---

## License

MIT License - See LICENSE file.

---

*Last updated: January 2026*
