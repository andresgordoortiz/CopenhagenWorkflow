# Medaka M34 Data Processing - Quick Start

## Your Data Configuration

**Input CZI file:**
```
/groups/pinheiro/user/andres.gordo/projects/medaka_m34/data/raw/2025-11-27/2025-11-27/medaka_25C_lefty_10pg_injected-30pg-H2A-mCherry_mzoep_injected-40pg-H2A-mCherry-01.czi
```

**Output directory:**
```
/groups/pinheiro/user/andres.gordo/projects/medaka_m34/data/merged/2025-11-27/
```

**Repository:**
```
/users/andres.ortiz/projects/CopenhagenWorkflow
```

**Container:**
```
/users/andres.ortiz/projects/CopenhagenWorkflow/copenhagen_workflow.sif
```

---

## Step-by-Step Instructions

### Step 1: Convert CZI to TIF

```bash
# Make sure you're in the repo directory
cd /users/andres.ortiz/projects/CopenhagenWorkflow

# Submit the CZI conversion job
sbatch sbatch_scripts/medaka/00_convert_czi.sh
```

This will:
- Read your CZI file
- Extract all positions (embryos)
- Create individual `Merged.tif` files in:
  ```
  /groups/pinheiro/user/andres.gordo/projects/medaka_m34/data/merged/2025-11-27/medaka_embryo_P00/merged/Merged.tif
  /groups/pinheiro/user/andres.gordo/projects/medaka_m34/data/merged/2025-11-27/medaka_embryo_P01/merged/Merged.tif
  ...
  ```

Monitor the job:
```bash
squeue -u $USER
tail -f logs/czi_convert_*.out
```

---

### Step 2: Create Config for Each Embryo

After CZI conversion completes, create a config file for each embryo you want to analyze:

```bash
# Example: For embryo at position 0
cp conf/experiment_data_paths/medaka/M34_template.yaml \
   conf/experiment_data_paths/medaka/embryo_P00.yaml
```

The template is already configured with the correct paths. You just need to:
1. Copy it with a unique name for each embryo
2. Change `P00` to the correct position number (`P01`, `P02`, etc.) throughout the file

**Quick way to create config for position 2:**
```bash
cd /users/andres.ortiz/projects/CopenhagenWorkflow

# Copy and edit in one go
sed 's/P00/P02/g' conf/experiment_data_paths/medaka/M34_template.yaml > \
    conf/experiment_data_paths/medaka/embryo_P02.yaml
```

---

### Step 3: Run the Pipeline

#### Option A: Full pipeline with dependencies (recommended)
```bash
cd /users/andres.ortiz/projects/CopenhagenWorkflow

# Make script executable
chmod +x sbatch_scripts/medaka/run_full_pipeline.sh

# Run for embryo P02
./sbatch_scripts/medaka/run_full_pipeline.sh medaka/embryo_P02
```

#### Option B: Step by step
```bash
cd /users/andres.ortiz/projects/CopenhagenWorkflow

# Step 1: Split channels
sbatch sbatch_scripts/medaka/01_split_channels.sh medaka/embryo_P02

# After it completes, run Step 2
sbatch sbatch_scripts/medaka/02_segment_nuclei.sh medaka/embryo_P02

# Continue with remaining steps...
```

---

## Monitoring Jobs

```bash
# Check job status
squeue -u $USER

# View logs
ls -lht logs/medaka_*

# Follow a specific log
tail -f logs/medaka_seg_nuclei_12345.out  # Replace 12345 with job ID
```

---

## Processing Multiple Embryos

To process all embryos from your CZI file:

```bash
cd /users/andres.ortiz/projects/CopenhagenWorkflow

# Create configs for all positions (adjust range as needed)
for i in {0..9}; do
    POS=$(printf "P%02d" $i)
    sed "s/P00/${POS}/g" conf/experiment_data_paths/medaka/M34_template.yaml > \
        conf/experiment_data_paths/medaka/embryo_${POS}.yaml
done

# Submit all pipelines (they'll queue up)
for i in {0..9}; do
    POS=$(printf "P%02d" $i)
    ./sbatch_scripts/medaka/run_full_pipeline.sh medaka/embryo_${POS}
done
```

---

## Expected Timeline

| Step | Time | Resource |
|------|------|----------|
| 00. CZI conversion | ~2-4h | High memory (256GB) |
| 01. Split channels | ~1h | High memory (128GB) |
| 02. Nuclei segmentation | ~4-8h | GPU (A100) |
| 03. Mitosis detection | ~2-4h | GPU (A100) |
| 04. NMS | ~30min | CPU |
| 05. Prepare tracking | ~1h | High memory |
| 06. TrackMate | ~2h | CPU |
| 07. Master tracking | ~2h | CPU |
| 08. Feature extraction | ~1h | CPU |

**Total per embryo: ~15-25 hours**

---

## Troubleshooting

### "Container not found"
```bash
# Check container location
ls -lh /users/andres.ortiz/projects/CopenhagenWorkflow/copenhagen_workflow.sif
```

### "Cannot cd to repo"
```bash
# Verify repo path
ls -ld /users/andres.ortiz/projects/CopenhagenWorkflow
```

### "Input CZI not found"
```bash
# Verify CZI file
ls -lh /groups/pinheiro/user/andres.gordo/projects/medaka_m34/data/raw/2025-11-27/2025-11-27/*.czi
```

### Check all paths are accessible
```bash
# Input
ls -lh /groups/pinheiro/user/andres.gordo/projects/medaka_m34/data/raw/2025-11-27/2025-11-27/

# Output
ls -ld /groups/pinheiro/user/andres.gordo/projects/medaka_m34/data/merged/2025-11-27/

# Repo
pwd
ls -lh copenhagen_workflow.sif
```

---

## Next Steps

After processing completes, you'll have CSV files with per-cell features in each embryo's directory:

```
/groups/pinheiro/user/andres.gordo/projects/medaka_m34/data/merged/2025-11-27/medaka_embryo_P*/
```

These can be loaded into Python/R for comparative analysis between control and Lefty conditions.
