#!/bin/bash
#SBATCH --job-name=medaka_split
#SBATCH --partition=m                    # High-memory partition (no GPU needed)
#SBATCH --mem=128G                       # 128GB RAM should be sufficient
#SBATCH --cpus-per-task=8                # 8 CPUs for parallel processing
#SBATCH --time=02:00:00                  # 2 hours max
#SBATCH --output=logs/medaka_split_%j.out
#SBATCH --error=logs/medaka_split_%j.err

# =============================================================================
# Step 01: Split dual-channel TIF into separate nuclei/membrane timelapses
# =============================================================================
# This step:
#   - Reads your Merged.tif (TZCYX format) from CZI conversion
#   - Extracts channel 0 (PBra-Venus/membrane) and channel 1 (H2A-mCherry/nuclei)
#   - Writes two separate TIFF files for downstream processing
#   - Creates per-timepoint splits for tracking
#
# Input:  Merged.tif (from CZI conversion)
# Output: Nuclei and membrane timelapse TIFFs + per-timepoint splits
# =============================================================================

echo "=========================================="
echo "Medaka Data: Channel Splitting"
echo "Job started: $(date)"
echo "Running on node: $(hostname)"
echo "Job ID: $SLURM_JOB_ID"
echo "=========================================="

# =============================================================================
# CONFIGURATION - MODIFY THESE FOR YOUR EMBRYO
# =============================================================================

# Which embryo position to process
# MODIFY THIS for each embryo you want to process
EMBRYO_CONFIG="medaka/M34_P02_control"    # ← Your config file name (without .yaml)

# Alternative: Use command line argument
# Usage: sbatch 01_split_channels.sh medaka/M34_P02_control
if [ -n "$1" ]; then
    EMBRYO_CONFIG="$1"
fi

# =============================================================================
# SETUP
# =============================================================================

# Load Singularity
module load singularity 2>/dev/null || true

# Set paths
REPO_ROOT="/users/andres.ortiz/projects/CopenhagenWorkflow"
CONTAINER="${REPO_ROOT}/copenhagen_workflow.sif"

# Change to repo directory
cd "${REPO_ROOT}" || { echo "ERROR: Cannot cd to ${REPO_ROOT}"; exit 1; }

# Create logs directory
mkdir -p logs

echo ""
echo "Configuration:"
echo "  Embryo config: ${EMBRYO_CONFIG}"
echo "  Container: ${CONTAINER}"
echo ""

# Check container exists
if [ ! -f "${CONTAINER}" ]; then
    echo "ERROR: Container not found: ${CONTAINER}"
    exit 1
fi

# =============================================================================
# RUN CHANNEL SPLITTING
# =============================================================================
echo "=========================================="
echo "Starting channel split..."
echo "=========================================="

singularity exec \
    ${CONTAINER} \
    python 00_create_nuclei_membrane_splits.py \
    experiment_data_paths=${EMBRYO_CONFIG} \
    parameters=medaka/medaka

EXIT_CODE=$?

echo ""
echo "=========================================="
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "SUCCESS: Channel splitting completed"
    echo ""
    echo "Next step: Run nuclei segmentation"
    echo "  sbatch sbatch_scripts/medaka/02_segment_nuclei.sh ${EMBRYO_CONFIG}"
else
    echo "ERROR: Channel splitting failed with exit code ${EXIT_CODE}"
fi
echo "Job ended: $(date)"
echo "=========================================="

exit ${EXIT_CODE}
