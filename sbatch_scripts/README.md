# SBATCH Scripts for CLIP Cluster

This directory contains SLURM batch scripts for running the CopenhagenWorkflow pipeline on the CLIP cluster.

---

## Quick Start

```bash
# Create logs directory
mkdir -p logs

# Submit Step 00
sbatch sbatch_scripts/00_split_channels.sh

# Check job status
squeue -u $USER

# View output
tail -f logs/split_*.out
```

---

## Adapting for Your Own Data

### For Step 00: Channel Splitting

You need to create/modify **TWO config files**:

#### 1. Data Paths Config: `conf/experiment_data_paths/YOUR_DATA.yaml`

Copy `sbiad499_clip.yaml` as a template:

```bash
cp conf/experiment_data_paths/sbiad499_clip.yaml \
   conf/experiment_data_paths/my_embryo.yaml
```

**What to modify:**

```yaml
# Dataset name - used for output filenames
timelapse_nuclei_to_track: 'my_embryo_name'      # ← Change this
timelapse_membrane_to_track: 'my_embryo_name'   # ← Change this

# Input filename - what your merged TIFF is called
input_merged_filename: 'Merged.tif'              # ← Or 'my_data.tif'

# Base directory - where your data lives
base_directory: '/scratch-cbe/users/YOUR_USER/my_project/merged/'  # ← Your path

# All output directories - adjust paths
timelapse_nuclei_directory: '/scratch-cbe/users/YOUR_USER/my_project/merged/nuclei_timelapses/'
timelapse_membrane_directory: '/scratch-cbe/users/YOUR_USER/my_project/merged/membrane_timelapses/'
# ... (see template for all paths)

# CRITICAL: Match your microscope calibration!
voxel_size_xyz: [0.65, 0.65, 1.774]             # ← [X, Y, Z] in micrometers
time_interval_seconds: 42                        # ← Time between frames
```

**Key fields:**
- `input_merged_filename`: Your TIFF filename (default: `Merged.tif`)
- `base_directory`: Parent directory containing your input file
- `voxel_size_xyz`: Physical pixel size [X, Y, Z] in µm
- `time_interval_seconds`: Frame interval

#### 2. Parameters Config: `conf/parameters/YOUR_PARAMS.yaml`

Copy `sbiad499.yaml` as a template:

```bash
cp conf/parameters/sbiad499.yaml \
   conf/parameters/my_params.yaml
```

**What to modify for Step 00:**

```yaml
# Channel assignments - which channel is which?
channel_membrane: 0    # ← Membrane marker (or mesoderm like drl:GFP)
channel_nuclei: 1      # ← Nuclear marker (like H2B-RFP)
```

**Other parameters** (used in later steps):
```yaml
# Cell size for segmentation
diameter_cellpose: 15.0              # Nucleus diameter in pixels
diameter_cellpose_membrane: 30.0     # Cell diameter in pixels

# GPU memory management
n_tiles: [2, 4, 4]                   # [Z, Y, X] - increase if OOM

# Size filters (in voxels)
min_size: 50                         # Minimum nucleus volume
max_size: 2000                       # Maximum nucleus volume
```

---

## Modifying SBATCH Scripts

Edit `00_split_channels.sh` to use your configs:

```bash
# Line 32-33: Change these
CONFIG_DATA="experiment_data_paths=my_embryo"      # Your data config name
CONFIG_PARAMS="parameters=my_params"                # Your params config name

# Line 41: Change input file path if needed
INPUT_FILE="/scratch-cbe/users/YOUR_USER/my_project/merged/Merged.tif"
```

---

## Memory Requirements by Dataset Size

| Input Size | T frames | Recommended RAM | Partition |
|------------|----------|-----------------|-----------|
| 20 GB | ~50 | 128G | `m` |
| 43 GB | ~100 | 256G | `m` |
| 90 GB | ~200 | 384G | `m` |
| 150 GB | ~350 | 512G | `m` |

Formula: `RAM ≈ Input_Size × 4.5`

If you get OOM errors, increase `--mem=` in the sbatch script.

---

## Directory Structure Expected

Your data should be organized like this:

```
/scratch-cbe/users/YOUR_USER/
└── my_project/
    └── merged/
        ├── Merged.tif                    ← Your input (TZCYX format)
        ├── nuclei_timelapses/           ← Created by Step 00
        ├── membrane_timelapses/         ← Created by Step 00
        └── split_nuclei_membrane_raw/   ← Created by Step 00
```

**Important**: The script looks for `input_merged_filename` in the **parent directory** of `timelapse_nuclei_directory`. This is why both are under `merged/` in the example above.

---

## Common Issues

### "File not found: Merged.tif"
- Check that `input_merged_filename` in your YAML matches the actual filename
- Verify the file is in the correct location (parent of `timelapse_nuclei_directory`)

### Out of Memory (OOM)
- Increase `--mem=` in the sbatch script
- Rule of thumb: RAM = Input file size × 4.5

### Wrong channel order
- Check your TIFF with: `singularity exec copenhagen_workflow.sif python -c "from tifffile import imread; print(imread('Merged.tif').shape)"`
- Expected: `(T, Z, C, Y, X)` where C=2
- Adjust `channel_membrane` and `channel_nuclei` in parameters YAML

---

## Next Steps

After Step 00 completes successfully, you can run:

```bash
# Step 01: Nuclei segmentation (requires GPU)
sbatch sbatch_scripts/01_segment_nuclei.sh

# Step 02: Membrane segmentation (requires GPU)
sbatch sbatch_scripts/01_segment_membrane.sh
```

*(Additional sbatch scripts coming soon)*
