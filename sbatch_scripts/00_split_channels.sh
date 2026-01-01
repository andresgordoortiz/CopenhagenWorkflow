#!/bin/bash
#SBATCH --job-name=zf_split_channels
#SBATCH --partition=m                    # High-memory partition (no GPU needed)
#SBATCH --mem=384G                       # 384GB RAM for 90GB input file
#SBATCH --cpus-per-task=8                # 8 CPUs for parallel processing
#SBATCH --time=02:00:00                  # 2 hours max
#SBATCH --output=logs/split_%j.out
#SBATCH --error=logs/split_%j.err

# =============================================================================
# Step 00: Split dual-channel TIFF into separate nuclei/membrane timelapses
# =============================================================================
# This step:
#   - Reads your Merged.tif (TZCYX format)
#   - Extracts channel 0 (membrane/mesoderm) and channel 1 (nuclei)
#   - Writes two separate TIFF files for downstream processing
#   - Creates per-timepoint splits for tracking
#
# Input:  Merged.tif (~90 GB for S-BIAD499 full dataset)
# Output: ~180 GB (two channel TIFFs + per-timepoint splits)
# =============================================================================

echo "=========================================="
echo "Job started: $(date)"
echo "Running on node: $(hostname)"
echo "Job ID: $SLURM_JOB_ID"
echo "=========================================="

# Load Singularity if needed
module load singularity 2>/dev/null || true

# Set paths
CONTAINER="${HOME}/copenhagen_workflow.sif"
WORKDIR="/scratch-cbe/users/andres.ortiz/zebrafish_test"

# Configuration files to use
# MODIFY THESE for different datasets:
CONFIG_DATA="experiment_data_paths=sbiad499_clip"    # Data paths config
CONFIG_PARAMS="parameters=sbiad499"                  # Segmentation parameters

echo "Container: ${CONTAINER}"
echo "Working directory: ${WORKDIR}"
echo "Config: ${CONFIG_DATA} ${CONFIG_PARAMS}"
echo ""

# Check that input file exists
INPUT_FILE="/scratch-cbe/users/andres.ortiz/zebrafish_test/merged/Merged.tif"
if [ ! -f "${INPUT_FILE}" ]; then
    echo "ERROR: Input file not found: ${INPUT_FILE}"
    exit 1
fi

echo "Input file: ${INPUT_FILE}"
echo "Input file size: $(du -h ${INPUT_FILE} | cut -f1)"
echo ""

# Run channel splitting
echo "=========================================="
echo "Starting channel split..."
echo "=========================================="

singularity exec \
    ${CONTAINER} \
    python 00_create_nuclei_membrane_splits.py \
    ${CONFIG_DATA} \
    ${CONFIG_PARAMS}

EXIT_CODE=$?

echo ""
echo "=========================================="
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "SUCCESS: Channel splitting completed"
    echo "Check outputs in:"
    echo "  - ${WORKDIR}/merged/nuclei_timelapses/"
    echo "  - ${WORKDIR}/merged/membrane_timelapses/"
    echo "  - ${WORKDIR}/merged/split_nuclei_membrane_raw/"
else
    echo "ERROR: Channel splitting failed with exit code ${EXIT_CODE}"
fi
echo "Job ended: $(date)"
echo "=========================================="

exit ${EXIT_CODE}
