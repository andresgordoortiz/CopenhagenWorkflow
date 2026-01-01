# CopenhagenWorkflow - Complete Documentation

> **A complete pipeline for 4D cell tracking and fate analysis**
> 
> Originally developed for Xenopus mucociliary epithelium, adapted for zebrafish embryo imaging

---

## Table of Contents

1. [Overview](#1-overview)
2. [Quick Start](#2-quick-start)
3. [Container Setup (Docker/Singularity)](#3-container-setup)
4. [Test Datasets](#4-test-datasets)
5. [Pipeline Architecture](#5-pipeline-architecture)
6. [Core Pipeline Scripts](#6-core-pipeline-scripts)
7. [Configuration System (Hydra)](#7-configuration-system-hydra)
8. [Running on HPC (SLURM)](#8-running-on-hpc-slurm)
9. [Zebrafish-Specific Adaptations](#9-zebrafish-specific-adaptations)
10. [Cell Fate Detection](#10-cell-fate-detection)
11. [Integrating Molecular Markers](#11-integrating-molecular-markers)
12. [Training Your Own Models](#12-training-your-own-models)
13. [Tool Fundamentals](#13-tool-fundamentals)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Overview

### What This Pipeline Does

This workflow implements a complete single-cell tracking and morphodynamic analysis pipeline for 4D microscopy data (3D + time):

1. **Segments nuclei** using StarDist3D (wrapped in VollSeg)
2. **Segments membranes** using Cellpose 2D + 3D stitching
3. **Denoises membrane** using CARE (Content-Aware Image Restoration)
4. **Detects mitotic events** using Oneat (DenseNet-based classifier)
5. **Tracks cells** via TrackMate + Oneat integration
6. **Extracts morphodynamic features** (shape, velocity, neighbors)
7. **Classifies cell fates** based on these features

### Pipeline vs Supporting Scripts

| **Core Pipeline (Sequential)** | **Supporting/Training Scripts** |
|-------------------------------|--------------------------------|
| `00_create_nuclei_membrane_splits.py` | `minus_01_create_train_patches.py` |
| `01_nuclei_segmentation.py` | `minus_02_train_vollseg.py` |
| `01_enhance_membrane.py` | `minus_03_train_cellpose.py` |
| `01_vollcellpose_membrane_segmentation.py` | `minus_06_train_oneat.py` |
| `02_oneat_nuclei.py` | `train_edge_enhancement_*.py` |
| `03_nms_nuclei_automated.py` | Jupyter notebooks (`*.ipynb`) |
| `04_prepare_tracking.py` | |
| `05_automate_trackmate.py` (Fiji) | |
| `06_master_tracking.py` | |
| `07_masterxml_dataframe.py` | |
| `10_cell_type_dataframe_generator.py` | |

---

## 2. Quick Start

### Prerequisites
- Docker or Singularity
- NVIDIA GPU with CUDA support (recommended)
- 64GB+ RAM for large datasets

### 5-Minute Setup

```bash
# 1. Pull the container (after it's built via GitHub Actions)
singularity pull copenhagen_workflow.sif docker://ghcr.io/YOUR_USER/copenhagenworkflow:latest

# Or build locally with Docker
docker build -t copenhagenworkflow:latest .

# 2. Download test data (first 50 timepoints of S-BIAD499)
./utils/download_test_data.sh /path/to/data 50

# 3. Merge the data
singularity exec copenhagen_workflow.sif python utils/merge_sbiad499.py \
    -i /path/to/data/wildtype-1 -o /path/to/data/merged

# 4. Edit config with your paths
cp conf/experiment_data_paths/zebrafish_gastrulation.yaml conf/experiment_data_paths/my_data.yaml
# Edit my_data.yaml with your paths

# 5. Run first step
singularity exec --nv copenhagen_workflow.sif python 00_create_nuclei_membrane_splits.py \
    experiment_data_paths=my_data
```

---

## 3. Container Setup

### Option A: Pull Pre-built Container (Recommended)

After pushing to GitHub, containers are automatically built via GitHub Actions:

```bash
# Pull from GitHub Container Registry
singularity pull copenhagen_workflow.sif docker://ghcr.io/YOUR_USER/copenhagenworkflow:latest

# Or with Docker
docker pull ghcr.io/YOUR_USER/copenhagenworkflow:latest
```

### Option B: Build Locally with Docker

```bash
# Build the Docker image
docker build -t copenhagenworkflow:latest .

# Test it
docker run --gpus all copenhagenworkflow:latest

# Convert to Singularity (for HPC)
singularity build copenhagen_workflow.sif docker-daemon://copenhagenworkflow:latest
```

### Option C: Build Singularity Directly

```bash
# From Docker image
singularity build copenhagen_workflow.sif docker://ghcr.io/YOUR_USER/copenhagenworkflow:latest

# Or from definition file (requires root/fakeroot)
singularity build --fakeroot copenhagen_workflow.sif containers/copenhagen_workflow.def
```

### Verify Installation

```bash
# Test Python packages
singularity exec --nv copenhagen_workflow.sif python utils/verify_installation.py

# Test GPU access
singularity exec --nv copenhagen_workflow.sif python -c "
import tensorflow as tf
print(f'TensorFlow GPUs: {tf.config.list_physical_devices(\"GPU\")}')
import torch
print(f'PyTorch CUDA: {torch.cuda.is_available()}')
"

# Test Fiji
singularity exec copenhagen_workflow.sif fiji --headless --help
```

### Container Contents

| Component | Version | Purpose |
|-----------|---------|---------|
| Python | 3.10 | Core runtime |
| TensorFlow | 2.13.1 | StarDist, CARE, Oneat |
| PyTorch | 2.1.1 | Cellpose |
| CUDA | 11.8 | GPU acceleration |
| Cellpose | 3.0.1 | Cell segmentation |
| StarDist | 0.8.5 | Nuclei segmentation |
| VollSeg | 2.4.3 | Segmentation pipeline |
| Oneat | 1.0.4 | Mitosis detection |
| NapaTrackMater | 1.4.5 | Track analysis |
| Fiji | Latest | TrackMate tracking |
| Napari | 0.4.19 | Visualization |

---

## 4. Test Datasets

### ⭐ Recommended: S-BIAD499 (Zebrafish Gastrulation)

**BioStudies S-BIAD499** - Perfect for zebrafish gastrulation studies:

- **Stage**: Shield to bud stage (~6-14 hpf)
- **Duration**: 8 hours per embryo
- **Channels**: 
  - C0: drl:GFP (mesoderm marker)
  - C1: H2B-RFP (nuclei)
- **Format**: 150 z-slices × 600-800 timepoints
- **Resolution**: 1.774 µm z-spacing, 42 sec intervals

```bash
# Download first 50 timepoints for testing
./utils/download_test_data.sh /scratch/$USER/zebrafish_data 50

# Merge into pipeline format
singularity exec copenhagen_workflow.sif python utils/merge_sbiad499.py \
    -i /scratch/$USER/zebrafish_data/wildtype-1 \
    -o /scratch/$USER/zebrafish_data/merged \
    -t 50
```

### Alternative: Zenodo 7671626 (StarDist Training)

4 zebrafish embryos with manual segmentation ground truth:

```bash
wget https://zenodo.org/records/7671626/files/Embryo1.zip
# Excellent for training StarDist models
```

---

## 5. Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         INPUT: Merged.tif (TZCYX)                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 00: Split Channels                                                     │
│   00_create_nuclei_membrane_splits.py                                       │
│   Output: nuclei_timelapses/, membrane_timelapses/                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
┌───────────────────────────────────┐  ┌───────────────────────────────────────┐
│ STEP 01a: Nuclei Segmentation     │  │ STEP 01b: Membrane Processing         │
│   01_nuclei_segmentation.py       │  │   01_enhance_membrane.py (CARE)       │
│   (StarDist3D + VollSeg)          │  │   01_vollcellpose_membrane_seg.py     │
│   Output: seg_nuclei_timelapses/  │  │   Output: seg_membrane_timelapses/    │
└───────────────────────────────────┘  └───────────────────────────────────────┘
                    │                                   │
                    └─────────────────┬─────────────────┘
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 02: Mitosis Detection (Oneat)                                          │
│   02_oneat_nuclei.py                                                        │
│   Output: oneat_detections/*.csv                                            │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 03: Non-Maximum Suppression                                            │
│   03_nms_nuclei_automated.py                                                │
│   Output: non_maximal_oneat_*.csv                                           │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 04: Prepare Tracking                                                   │
│   04_prepare_tracking.py                                                    │
│   Creates hyperstacks for TrackMate                                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 05: TrackMate Tracking (Fiji/Jython)                                   │
│   05_automate_trackmate.py                                                  │
│   Output: nuclei_*.xml, membrane_*.xml                                      │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 06-07: Feature Extraction                                              │
│   06_master_tracking.py → 07_masterxml_dataframe.py                         │
│   Output: dataframes/results_dataframe_*.csv                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 10: Cell Type Classification                                           │
│   10_cell_type_dataframe_generator.py                                       │
│   Output: goblet_basal_dataframe_normalized_*.csv                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Input Data Requirements

**Primary Input:** `Merged.tif`
- **Format:** 5D TIFF (TZCYX order)
- **Channels:** 
  - Channel 0: Membrane/mesoderm marker
  - Channel 1: Nuclear marker (H2B)
- **Bit depth:** 16-bit unsigned integer

---

## 6. Core Pipeline Scripts

### Step 00: Channel Splitting

```bash
python 00_create_nuclei_membrane_splits.py experiment_data_paths=my_data
```

**Purpose:** Splits merged timelapse into separate nuclei and membrane stacks.

**Output:**
- `nuclei_timelapses/{name}.tif`
- `membrane_timelapses/{name}.tif`
- `split_nuclei_membrane_raw/Merged-{t}.tif`

---

### Step 01a: Nuclei Segmentation

```bash
python 01_nuclei_segmentation.py experiment_data_paths=my_data parameters=zebrafish
```

**Method:**
1. ROI detection (MASKUNET on Z-MIP)
2. Intensity normalization
3. StarDist3D instance segmentation
4. Size filtering

**Key Parameters:**
```yaml
min_size: 30            # Minimum nucleus volume (voxels)
max_size: 3000          # Maximum volume
n_tiles: [2, 4, 4]      # GPU memory management
```

---

### Step 01b: Membrane Enhancement & Segmentation

```bash
python 01_enhance_membrane.py experiment_data_paths=my_data
python 01_membrane_segmentation_normal_cellpose.py experiment_data_paths=my_data
python 01_vollcellpose_membrane_segmentation.py experiment_data_paths=my_data
```

**Method:**
1. CARE denoising
2. Cellpose 2D per-slice segmentation
3. 3D stitching via IoU matching

**Key Parameters:**
```yaml
diameter_cellpose: 16.0    # Cell diameter in pixels (CRITICAL!)
stitch_threshold: 0.5      # IoU threshold for stitching
```

---

### Step 02: Mitosis Detection

```bash
python 02_oneat_nuclei.py experiment_data_paths=my_data parameters=oneat_zebrafish
```

**Method:** Oneat (DenseVollNet) scans 4D data with sliding window, predicting mitosis probability.

**Output:** `oneat_detections/oneat_mitosis_locations_*.csv`

---

### Step 03: Non-Maximum Suppression

```bash
python 03_nms_nuclei_automated.py experiment_data_paths=my_data
```

**Purpose:** Deduplicates mitosis detections across consecutive frames.

**Parameters:**
```yaml
nms_space: 8    # Spatial radius (µm)
nms_time: 2     # Temporal window (frames)
```

---

### Step 04-05: Tracking

```bash
python 04_prepare_tracking.py experiment_data_paths=my_data

# Run TrackMate in Fiji
singularity exec copenhagen_workflow.sif fiji --headless --run 05_automate_trackmate.py
```

**TrackMate Configuration:**
- Label Image Detector (uses segmentation)
- LAP Tracker (max distance ~16 µm)
- Oneat Corrector (inserts division events)

---

### Step 06-07: Feature Extraction

```bash
python 06_master_tracking.py experiment_data_paths=my_data
python 07_masterxml_dataframe.py experiment_data_paths=my_data
```

**Features Extracted:**

| Shape Features | Dynamic Features |
|---------------|-----------------|
| Surface Area | Velocity |
| Volume | Acceleration |
| Sphericity | Displacement |
| Eccentricity | Angular velocity |

---

## 7. Configuration System (Hydra)

### Directory Structure

```
conf/
├── experiment_data_paths/      # Dataset paths
│   ├── zebrafish_gastrulation.yaml
│   └── your_dataset.yaml
├── parameters/                 # Algorithm parameters
│   ├── zebrafish.yaml
│   ├── oneat_zebrafish.yaml
│   └── tracking_zebrafish.yaml
└── model_paths/                # Model locations
    └── your_hpc.yaml
```

### Creating Your Dataset Config

```yaml
# conf/experiment_data_paths/my_embryo.yaml
timelapse_nuclei_to_track: 'my_embryo'
timelapse_membrane_to_track: 'my_embryo'
base_directory: '/data/my_project/'

timelapse_nuclei_directory: '/data/my_project/nuclei_timelapses/'
timelapse_seg_nuclei_directory: '/data/my_project/seg_nuclei_timelapses/'
timelapse_membrane_directory: '/data/my_project/membrane_timelapses/'
timelapse_seg_membrane_directory: '/data/my_project/seg_membrane_timelapses/'
timelapse_oneat_directory: '/data/my_project/oneat_detections/'
tracking_directory: '/data/my_project/tracking/'

# CRITICAL: Match your microscope!
voxel_size_xyz: [0.5, 0.5, 1.774]  # X, Y, Z in micrometers
```

### Override Parameters

```bash
# Single parameter
python script.py parameters.diameter_cellpose=18.0

# Multiple
python script.py parameters.min_size=50 parameters.n_tiles=[4,8,8]

# Different config files
python script.py experiment_data_paths=my_embryo parameters=zebrafish model_paths=my_hpc
```

---

## 8. Running on HPC (SLURM)

### Your HPC Partitions

| Partition | Use For | Command |
|-----------|---------|---------|
| `gpu` | Segmentation, Oneat | `--partition=gpu --gres=gpu:1` |
| `genoa64` | CPU tasks, Fiji | `--partition=genoa64 --cpus-per-task=16` |
| `gpu_diasfrazer` | Alternative GPU | `--partition=gpu_diasfrazer --gres=gpu:1` |

### Interactive Session

```bash
# GPU session
srun --partition=gpu --gres=gpu:1 --cpus-per-task=8 --mem=64G --time=4:00:00 --pty bash

# Run inside container
singularity exec --nv \
    --bind /scratch/$USER/data:/data \
    copenhagen_workflow.sif python 01_nuclei_segmentation.py \
    experiment_data_paths=my_data
```

### Batch Job Example

```bash
#!/bin/bash
#SBATCH --job-name=nuclei_seg
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=4:00:00
#SBATCH --output=logs/%j.out

singularity exec --nv \
    --bind /scratch/$USER/data:/data \
    copenhagen_workflow.sif python 01_nuclei_segmentation.py \
    experiment_data_paths=zebrafish_gastrulation \
    parameters=zebrafish
```

### Full Pipeline Script

See `slurm/run_pipeline.sh` for a complete pipeline runner.

---

## 9. Zebrafish-Specific Adaptations

### Zebrafish vs Xenopus

| Aspect | Xenopus | Zebrafish |
|--------|---------|-----------|
| Cell size | ~30-40 µm | **~5-15 µm** |
| Cellpose diameter | ~34 px | **~12-18 px** |
| Division time | ~hours | **~15-20 min** |
| Voxel size | 0.69×0.69×2 µm | **~0.5×0.5×1.7 µm** |

### Developmental Stages

| Stage | hpf | Cells | Notes |
|-------|-----|-------|-------|
| 1-cell | 0 | 1 | Too early |
| Sphere | 4 | 1000+ | Cells ~15 µm |
| **Shield** | **6** | **~4000** | **Gastrulation starts** |
| 75% epiboly | 8 | 8000+ | Mid-gastrulation |
| **Bud** | **10** | **~16000** | **Late gastrulation** |

### Key Parameter Adjustments

```yaml
# conf/parameters/zebrafish.yaml
diameter_cellpose: 16.0    # SMALLER than Xenopus!
min_size: 30               # Smaller nuclei
max_size: 3000
n_tiles: [2, 4, 4]         # Increase if memory issues
```

### Gastrulation Challenges

1. **Epiboly/involution**: Rapid cell movements
2. **Yolk cell**: NOT a cell - exclude from segmentation
3. **Depth**: Cells move in/out of imaging volume
4. **Mesoderm marker**: Use drl:GFP as pseudo-membrane or for validation

---

## 10. Cell Fate Detection

### ⚠️ IMPORTANT: Cell fate is predicted from MORPHOLOGY, not markers!

The pipeline classifies cells using **morphodynamic features only**:

**Shape Features:**
- Volume, surface area, sphericity
- Eccentricity, principal axes
- Centroid position

**Dynamic Features:**
- Velocity, acceleration
- Displacement, MSD
- Track duration

**Neighbor Features:**
- Number of neighbors
- Distance to nearest neighbor
- Cell density

### Classification Approach

1. Extract features via `napatrackmater.TrackVector`
2. Normalize all features
3. Classify using:
   - Pre-trained GradientBoosting models
   - Clustering (hierarchical, k-means)
   - Your own ground truth labels

---

## 11. Integrating Molecular Markers

If you have a marker like Brachyury:

### Option 1: Measure Intensity Per Cell

```python
import pandas as pd
import numpy as np
from tifffile import imread

# Load data
tracks = pd.read_csv('tracking_features.csv')
marker = imread('brachyury_channel.tif')  # TZYX
seg = imread('seg_nuclei.tif')

# Measure marker per cell
def get_marker_intensity(row, marker_vol, seg_vol):
    t, z, y, x = int(row['t']), int(row['z']), int(row['y']), int(row['x'])
    label = seg_vol[t, z, y, x]
    if label == 0:
        return np.nan
    mask = seg_vol[t] == label
    return np.mean(marker_vol[t][mask])

tracks['brachyury'] = tracks.apply(
    lambda r: get_marker_intensity(r, marker, seg), axis=1
)
```

### Option 2: Use Marker as Ground Truth

```python
# Define cell types from marker expression
threshold = np.percentile(tracks['brachyury'].dropna(), 75)
tracks['cell_type'] = 'Other'
tracks.loc[tracks['brachyury'] > threshold, 'cell_type'] = 'Mesendoderm'

# Train classifier on morphology (NOT marker!)
from sklearn.ensemble import GradientBoostingClassifier
feature_cols = ['volume', 'sphericity', 'velocity', 'msd']
clf = GradientBoostingClassifier()
clf.fit(tracks[feature_cols], tracks['cell_type'])

# Now predict cell type from morphology alone!
```

---

## 12. Training Your Own Models

### StarDist (Nuclei)

```bash
python minus_01_create_train_patches.py  # Create patches
python minus_02_train_vollseg.py         # Train model
```

Use Zenodo 7671626 for zebrafish training data.

### Cellpose (Membrane)

```bash
python minus_03_train_cellpose.py
```

Or use Cellpose GUI for interactive training.

### Oneat (Mitosis)

```bash
python minus_06_train_oneat.py
```

Requires manually annotated mitosis events (use Napari).

---

## 13. Tool Fundamentals

### StarDist3D
- **Method**: Star-convex polyhedra with 96 radial rays
- **Best for**: Convex shapes like nuclei
- **Key params**: `n_rays=96`, `prob_thresh=0.5`

### Cellpose
- **Method**: Gradient flow fields to cell centers
- **Best for**: Variable cell shapes
- **Key params**: `diameter`, `flow_threshold`

### CARE
- **Method**: U-Net denoising
- **Best for**: Low SNR membrane images

### Oneat
- **Method**: DenseNet on 4D patches (time as channels)
- **Best for**: Event detection (mitosis)
- **Key params**: `event_threshold`, `nms_space`

### TrackMate
- **Method**: LAP (Linear Assignment Problem) tracking
- **Key params**: `linking_max_distance`, `gap_closing`

---

## 14. Troubleshooting

### GPU Not Found

```bash
# Must use --nv flag with Singularity
singularity exec --nv ...

# Check CUDA
singularity exec --nv container.sif nvidia-smi
```

### Out of Memory

```yaml
# Increase tiling
n_tiles: [4, 8, 8]  # Process smaller chunks
```

### Wrong Cell Size (Cellpose)

```bash
# Run GUI to test diameter
singularity exec --nv container.sif python -m cellpose --gui
```

### TrackMate Errors

```bash
# Test Fiji
singularity exec container.sif fiji --headless --help

# Update plugins
singularity exec container.sif fiji --headless --update update
```

### Module Not Found

```bash
# Test imports
singularity exec container.sif python -c "import cellpose"

# Rebuild container if needed
docker build --no-cache -t copenhagenworkflow:latest .
```

---

## Files Reference

```
CopenhagenWorkflow/
├── Dockerfile                          # Container definition
├── .github/workflows/docker-build.yml  # Auto-build on push
├── conf/
│   ├── experiment_data_paths/
│   │   └── zebrafish_gastrulation.yaml
│   ├── parameters/
│   │   ├── zebrafish.yaml
│   │   ├── oneat_zebrafish.yaml
│   │   └── tracking_zebrafish.yaml
│   └── model_paths/
│       └── your_hpc.yaml
├── slurm/
│   ├── run_pipeline.sh
│   └── step01_nuclei_segmentation.sbatch
└── utils/
    ├── download_test_data.sh
    ├── merge_sbiad499.py
    └── verify_installation.py
```

---

## Citation

If you use this workflow, please cite:

> Tolonen, M., Xu, Z., Beker, O., Kapoor, V., Dumitrascu, B., & Sedzinski, J. (2024). 
> Single-cell morphodynamics predicts cell fate decisions during Xenopus mucociliary differentiation.

---

## License

MIT License - See LICENSE file for details.

---

*Documentation last updated: January 2026*
