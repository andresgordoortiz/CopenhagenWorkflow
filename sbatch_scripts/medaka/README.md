# Medaka Pipeline Configuration

This folder contains SBATCH scripts and configurations for processing **Medaka embryo** fluorescence microscopy data through the CopenhagenWorkflow pipeline.

---

## 📋 Dataset Overview: M34 Session

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Date** | 2025-12-17 | |
| **Species** | Medaka (*Oryzias latipes*) | |
| **Cross** | PBra-Venus (hom, 6680) × CAB WT (6696) | |
| **Markers** | PBra-Venus (mesoderm), H2A-mCherry (nuclei) | |
| **Injection** | 20pg H2A-mCherry + 100ng dextran-647 | Control |
| **Treatment** | 15pg H2A-mCherry + 10pg Lefty + 100ng dextran-647 | Real Lefty = 20pg (2 puffs) |
| **Positions** | 10 total (3 control, 5 Lefty planned) | Check mCherry positivity! |
| **Temperature** | 25°C | |

### Acquisition Parameters

| Parameter | Value | Impact on Analysis |
|-----------|-------|-------------------|
| **Objective** | 5× with 1× tubelens | Low magnification |
| **Pixel size** | ~2.0 µm/px | **⚠️ Verify from microscope!** |
| **Z-stack** | 600 µm, 7 slices | 100 µm Z-step |
| **Time interval** | 5 minutes | 300 seconds |
| **Duration** | 48 hours | 576 timepoints |
| **Channels** | BF, AF488, mCherry, (dextran-647) | 3-4 channels |

### Position Assignment

| Position | Group | mCherry Status | Use for Quantification? |
|----------|-------|----------------|------------------------|
| P0 | Control | Check | Verify |
| **P1** | **Control** | **NEGATIVE** | **❌ EXCLUDE** |
| P2 | Control | Positive | ✅ Yes |
| P3-P5 | Lefty | Check | Verify |
| **P6** | **Lefty** | **NEGATIVE** | **❌ EXCLUDE** |
| P7-P9 | Lefty | Check | Verify |

> **Note**: Some embryos showed defects at imaging start or died during acquisition.

---

## ⚠️ Important Limitations

### 1. Low XY Resolution

At 5× magnification (~2 µm/pixel), single cells are at the **detection limit**:

| Structure | Physical Size | Pixels at 2µm/px | Status |
|-----------|--------------|------------------|--------|
| Nucleus | 8-12 µm | 4-6 px | ⚠️ Barely resolved |
| Cell body | 15-25 µm | 8-12 px | ⚠️ Marginal for Cellpose |
| Mitotic figure | 10-15 µm | 5-8 px | ❌ Very difficult |

**Consequence**:
- Segmentation accuracy will be lower than high-resolution data
- Small cells may be missed
- Cellpose diameter must be very small (6-12 px)

### 2. Extremely Sparse Z-Sampling

With 100 µm Z-steps and 7 slices:

| Parameter | Value | Issue |
|-----------|-------|-------|
| Z-step | 100 µm | 10× cell diameter! |
| Total depth | 600 µm | Whole embryo visible |
| Cells per slice | ~10% of cells | Most cells missed per Z |

**Consequence**:
- **NO real 3D context** - treat as 2D + sparse depth sampling
- StarDist 3D will not work reliably
- Objects cannot be tracked in Z
- Anisotropy = 50:1 (extreme!)

### 3. Pre-trained Model Mismatch

The pipeline's pre-trained models were optimized for:
- **Xenopus** cells at ~1 µm/pixel (2× better resolution)
- Dense Z-stacks (~2 µm Z-step, 50× denser)
- Different cell morphology

**Consequence**:
- Oneat mitosis detection may be **unreliable**
- Consider manual annotation or alternative detection methods
- Validate ALL automated detections

---

## 🔧 Parameter Choices Explained

### Segmentation Parameters (`medaka/medaka.yaml`)

```yaml
# Cell diameter at low magnification
diameter_cellpose: 6.0      # Nuclei: 4-6 px at 2µm/px
diameter_cellpose_membrane: 12.0  # Cells: 8-12 px

# Sparse Z handling
do_3D: False               # MUST use 2D - Z too sparse
anisotropy: 50.0           # 100µm / 2µm = 50

# Small object detection
min_size: 10               # ~40 µm³ minimum
cellprob_threshold: -2.0   # Very permissive
```

**Rationale**:
- `diameter_cellpose=6`: Medaka nuclei are 8-12µm → 4-6 pixels at 2µm/px
- `do_3D=False`: With 100µm Z-steps, there's no 3D context to use
- `anisotropy=50`: Tells Cellpose about the extreme Z/XY ratio
- `min_size=10`: Very small to catch marginal detections

### Oneat Parameters (`medaka/oneat_medaka.yaml`)

```yaml
# Smaller patches for smaller cells
imagex: 32
imagey: 32
imagez: 3                  # Only 3 Z-slices (essentially 2D)

# HIGH thresholds due to domain shift
event_threshold: [1, 0.999]
event_confidence: [1, 0.95]

# Smaller NMS window for smaller cells
nms_space: 5               # ~10µm at 2µm/px
```

**Rationale**:
- Smaller patches because features are smaller at low resolution
- Very high thresholds because model wasn't trained on this data
- NMS space reduced proportionally to resolution

### Voxel Calibration

```yaml
voxel_size_xyz: [2.0, 2.0, 100.0]  # µm
time_interval_seconds: 300          # 5 minutes
```

**Rationale**:
- 5× objective with standard sCMOS: typically 1.3-2.6 µm/px
- **VERIFY actual pixel size from microscope metadata!**
- Z-step = 600µm ÷ 6 intervals = 100µm

---

## 📁 File Structure

After running the pipeline:

```
/scratch-cbe/users/USERNAME/medaka/M34_session/
├── raw_data/
│   └── M34_PBra_Venus_H2A_mCherry.czi    # Original acquisition
│
├── converted/                             # From CZI conversion
│   ├── M34_embryo_P00/
│   │   ├── merged/
│   │   │   └── Merged.tif                # Pipeline input
│   │   ├── acquisition_metadata.json
│   │   ├── nuclei_timelapses/            # Split channels
│   │   ├── membrane_timelapses/
│   │   ├── seg_nuclei_timelapses/        # Segmentation masks
│   │   ├── oneat_detections/             # Mitosis CSVs
│   │   └── tracking/                     # TrackMate output
│   ├── M34_embryo_P01/                   # EXCLUDE (mCherry-)
│   ├── M34_embryo_P02/
│   ...
│   └── M34_embryo_P09/
```

---

## 🚀 Usage

### Step 0: Convert CZI to TIF

```bash
# First, edit 00_convert_czi.sh with your file paths
nano sbatch_scripts/medaka/00_convert_czi.sh

# Submit conversion job
sbatch sbatch_scripts/medaka/00_convert_czi.sh
```

### Step 1: Create Config for Each Embryo

```bash
# Copy template
cp conf/experiment_data_paths/medaka/M34_template.yaml \
   conf/experiment_data_paths/medaka/M34_P02_control.yaml

# Edit paths and position name
nano conf/experiment_data_paths/medaka/M34_P02_control.yaml
```

### Step 2: Run Pipeline

**Option A: Step by step**
```bash
# Channel splitting
sbatch sbatch_scripts/medaka/01_split_channels.sh medaka/M34_P02_control

# After completion, segmentation
sbatch sbatch_scripts/medaka/02_segment_nuclei.sh medaka/M34_P02_control

# Continue with remaining steps...
```

**Option B: Full pipeline with dependencies**
```bash
chmod +x sbatch_scripts/medaka/run_full_pipeline.sh
./sbatch_scripts/medaka/run_full_pipeline.sh medaka/M34_P02_control
```

### Monitoring Jobs

```bash
# Check job status
squeue -u $USER

# View logs
tail -f logs/medaka_*.out

# Check errors
cat logs/medaka_*.err
```

---

## 📊 Expected Results & Caveats

### What This Pipeline CAN Do

1. **Tissue-level analysis**: Track mesoderm domain boundaries (PBra-Venus)
2. **Bulk cell dynamics**: Count total nuclei over time
3. **Long-term tracking**: 48 hours of development at 5-min resolution
4. **Comparative analysis**: Control vs Lefty treatment effects

### What This Pipeline CANNOT Do Reliably

1. **Single-cell segmentation**: Resolution too low for accurate cell boundaries
2. **Mitosis detection**: Oneat not trained on this data type
3. **3D morphometry**: Z too sparse for meaningful 3D analysis
4. **Cell shape analysis**: Cells too small in pixels

### Recommended Validation

Before trusting any results:

1. **Check segmentation visually** in napari:
   ```bash
   singularity exec copenhagen_workflow.sif napari \
       nuclei_timelapses/*.tif seg_nuclei_timelapses/*.tif
   ```

2. **Review Oneat detections** manually - expect many false positives

3. **Validate tracking** on a few frames before processing all 576

4. **Compare across conditions** (Control vs Lefty) rather than trusting absolute numbers

---

## 🔬 Recommendations for Future Acquisitions

To improve single-cell analysis capability:

| Parameter | Current | Recommended | Why |
|-----------|---------|-------------|-----|
| Objective | 5× | 10× or 20× | Better cell resolution |
| Pixel size | ~2 µm | ~0.5-1 µm | Cells need >10 px diameter |
| Z-step | 100 µm | 2-5 µm | Capture all cells in 3D |
| Z-slices | 7 | 50-100 | Cover depth with dense sampling |

With 10× and 2µm Z-step:
- Nuclei: 8-16 pixels (good for Cellpose)
- Full 3D context preserved
- Oneat can detect mitotic figures

---

## 📚 References

### Medaka Development

- Medaka gastrulation: ~7-10 hpf at 25°C
- Cell cycle during gastrulation: 45-60 minutes
- Shield stage equivalent: ~7 hpf

### Pipeline Documentation

- Main README: [/README.md](/README.md)
- Segmentation details: [/docs/SEGMENTATION.md](/docs/SEGMENTATION.md)
- Oneat documentation: [/docs/ONEAT.md](/docs/ONEAT.md)

---

## 🆘 Troubleshooting

### "CZI reader not found"
```bash
# Install in container or environment
pip install aicspylibczi
# or
pip install czifile
```

### "Out of memory during segmentation"
Increase tiling in parameters:
```yaml
n_tiles: [1, 4, 4]  # Increase Y, X values
```

### "No cells detected"
- Check if nuclei channel is correct (should be mCherry, channel 1 after mapping)
- Lower `cellprob_threshold` further (try -3.0)
- Verify embryo is mCherry positive (not P1 or P6!)

### "Too many false positive mitoses"
- Increase `event_confidence` threshold (try 0.99)
- Consider manual annotation instead
- Use track lineages to infer divisions

---

## 📝 Changelog

- **v1.0** (2025-01): Initial Medaka configuration for M34 session
