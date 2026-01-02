#!/bin/bash
#SBATCH --job-name=czi_convert
#SBATCH --partition=m                    # High-memory partition (no GPU needed)
#SBATCH --mem=256G                       # 256GB RAM - CZI files can be large
#SBATCH --cpus-per-task=8                # Multiple CPUs for parallel I/O
#SBATCH --time=01:30:00                  # 1 hour 30 minutes - adjust based on file size
#SBATCH --output=logs/czi_convert_%j.out
#SBATCH --error=logs/czi_convert_%j.err

# =============================================================================
# MEDAKA DATA PREPROCESSING: CZI to TIF Conversion
# =============================================================================
# This script converts multi-position CZI files from the fluorescence microscope
# to individual TIF files suitable for the CopenhagenWorkflow pipeline.
#
# For the M34 session Medaka data:
#   - Input: Multi-position CZI file with 10 positions (embryos)
#   - Channels: BF, AF488 (PBra-Venus), mCherry (H2A-mCherry), [possibly dextran-647]
#   - Z-stack: 600µm total, 7 slices, 100µm interval
#   - Time: Every 5 minutes for 48 hours
#
# Output structure:
#   output_dir/
#   ├── embryo_P00/merged/Merged.tif   (Control - but mCherry negative, exclude!)
#   ├── embryo_P01/merged/Merged.tif   (Control - positive)
#   ├── ...
#   └── embryo_P09/merged/Merged.tif   (Lefty - but check mCherry!)
#
# IMPORTANT: Check which positions are mCherry positive!
#   - P1 is control but mCherry NEGATIVE → exclude from quantifications
#   - P6 is Lefty but mCherry NEGATIVE → exclude from quantifications
# =============================================================================

echo "=========================================="
echo "CZI to TIF Conversion for Medaka Data"
echo "Job started: $(date)"
echo "Running on node: $(hostname)"
echo "Job ID: $SLURM_JOB_ID"
echo "=========================================="

# =============================================================================
# CONFIGURATION - MODIFY THESE FOR YOUR DATA
# =============================================================================

# Input CZI file
INPUT_CZI="/groups/pinheiro/user/andres.gordo/projects/medaka_m34/data/raw/2025-11-27/2025-11-27/medaka_25C_lefty_10pg_injected-30pg-H2A-mCherry_mzoep_injected-40pg-H2A-mCherry-01.czi"

# Output directory - where processed TIFs will go
OUTPUT_DIR="/groups/pinheiro/user/andres.gordo/projects/medaka_m34/data/merged/2025-11-27"

# Prefix for output folders
PREFIX="medaka_embryo"

# Specific positions to convert (leave empty for all)
# According to your notes, you have 10 positions total
# Positive for mCherry (usable): P0?, P2?, P3?, P4?, P5?, P7?, P8?, P9?
# NEGATIVE for mCherry (exclude): P1 (control), P6 (Lefty)
# Set specific positions to convert, or leave empty for all:
POSITIONS=""  # e.g., "0 2 3 4 5 7 8 9" to exclude P1 and P6

# Channel mapping based on your acquisition (0-based indexing):
# From CZI metadata, channels appear to be:
# Channel 0: Bright (brightfield) - EXCLUDE
# Channel 1: AF488 (PBra-Venus) - membrane/mesoderm marker
# Channel 2: mCherry (H2A-mCherry) - nuclei marker
# Channel 3: AF647 (dextran injection marker) - EXCLUDE
#
# If brightfield appears in output, try incrementing both by 1:
MEMBRANE_CHANNEL=2   # AF488 / PBra-Venus (was 1)
NUCLEI_CHANNEL=3     # mCherry / H2A-mCherry (was 2)

# Voxel size calibration from your acquisition:
# 5x objective, 1x tubelens
# At 5x magnification, typical pixel size is ~1.3-2.0 µm/px depending on camera
# You may need to check your microscope calibration
# Z-step: 100 µm (very coarse! 600µm stack / 7 slices ≈ 100µm)
VOXEL_X=2.0     # µm - VERIFY THIS from your microscope settings
VOXEL_Y=2.0     # µm - typically same as X
VOXEL_Z=100.0   # µm - from your acquisition notes (600µm / 6 intervals = 100µm)

# Time interval: 5 minutes = 300 seconds
TIME_INTERVAL=300

# =============================================================================
# SETUP
# =============================================================================

# Load modules
module load singularity 2>/dev/null || true

# Set paths
REPO_ROOT="/users/andres.ortiz/projects/CopenhagenWorkflow"
CONTAINER="${REPO_ROOT}/copenhagen_workflow.sif"

# Change to repo directory
cd "${REPO_ROOT}" || { echo "ERROR: Cannot cd to ${REPO_ROOT}"; exit 1; }

# Create output and logs directories
mkdir -p "${OUTPUT_DIR}"
mkdir -p logs

# Verify input file exists
if [ ! -f "${INPUT_CZI}" ]; then
    echo "ERROR: Input CZI file not found: ${INPUT_CZI}"
    echo ""
    echo "Please update INPUT_CZI variable in this script."
    exit 1
fi

echo ""
echo "Configuration:"
echo "  Input CZI: ${INPUT_CZI}"
echo "  Output dir: ${OUTPUT_DIR}"
echo "  Prefix: ${PREFIX}"
echo "  Membrane channel: ${MEMBRANE_CHANNEL}"
echo "  Nuclei channel: ${NUCLEI_CHANNEL}"
echo "  Voxel size (µm): X=${VOXEL_X}, Y=${VOXEL_Y}, Z=${VOXEL_Z}"
echo "  Time interval: ${TIME_INTERVAL} seconds"
echo ""

# =============================================================================
# STEP 1: Print CZI info first
# =============================================================================
echo "=========================================="
echo "Checking CZI file structure..."
echo "=========================================="

singularity exec \
    --bind /groups:/groups \
    --bind /users:/users \
    ${CONTAINER} \
    python preprocessing/czi_to_tif_converter.py \
    --input "${INPUT_CZI}" \
    --output "${OUTPUT_DIR}" \
    --info-only

INFO_EXIT=$?
if [ ${INFO_EXIT} -ne 0 ]; then
    echo ""
    echo "WARNING: Could not read CZI info. The file may use a different format."
    echo "Proceeding with conversion anyway..."
fi

# =============================================================================
# STEP 2: Convert CZI to TIF
# =============================================================================
echo ""
echo "=========================================="
echo "Converting CZI to TIF..."
echo "=========================================="

# Build command arguments
CMD_ARGS=("--input" "${INPUT_CZI}")
CMD_ARGS+=("--output" "${OUTPUT_DIR}")
CMD_ARGS+=("--prefix" "${PREFIX}")
CMD_ARGS+=("--membrane-channel" "${MEMBRANE_CHANNEL}")
CMD_ARGS+=("--nuclei-channel" "${NUCLEI_CHANNEL}")
CMD_ARGS+=("--voxel-size" "${VOXEL_X}" "${VOXEL_Y}" "${VOXEL_Z}")
CMD_ARGS+=("--time-interval" "${TIME_INTERVAL}")

# Add specific positions if specified
if [ -n "${POSITIONS}" ]; then
    CMD_ARGS+=("--positions" ${POSITIONS})
fi

echo "Running: python preprocessing/czi_to_tif_converter.py ${CMD_ARGS[@]}"
echo ""

singularity exec \
    --bind /groups:/groups \
    --bind /users:/users \
    ${CONTAINER} \
    python preprocessing/czi_to_tif_converter.py "${CMD_ARGS[@]}"

EXIT_CODE=$?

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "=========================================="
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "SUCCESS: CZI conversion completed"
    echo ""
    echo "Output structure:"
    ls -la "${OUTPUT_DIR}"
    echo ""
    echo "Next steps:"
    echo "  1. Verify which positions have good mCherry signal"
    echo "  2. Create YAML config for each embryo you want to process"
    echo "  3. Run the pipeline starting from 00_split_channels.sh"
    echo ""
    echo "Remember to EXCLUDE from quantifications:"
    echo "  - P1 (control, mCherry negative)"
    echo "  - P6 (Lefty, mCherry negative)"
else
    echo "ERROR: CZI conversion failed with exit code ${EXIT_CODE}"
fi
echo "Job ended: $(date)"
echo "=========================================="

exit ${EXIT_CODE}
