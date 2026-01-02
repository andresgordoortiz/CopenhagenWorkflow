#!/bin/bash
#SBATCH --job-name=medaka_df
#SBATCH --partition=c                    # CPU partition
#SBATCH --cpus-per-task=8                # 8 CPUs
#SBATCH --mem=64G                        # 64GB RAM
#SBATCH --time=02:00:00                  # 2 hours
#SBATCH --output=logs/medaka_df_%j.out
#SBATCH --error=logs/medaka_df_%j.err

# =============================================================================
# Step 08: Extract Features to DataFrame
# =============================================================================
# Converts master track XML to pandas DataFrame with per-cell features:
#   - Shape: volume, surface area, sphericity, eccentricity
#   - Dynamics: velocity, acceleration, displacement, MSD
#   - Neighbors: count, distances, local density
#
# Input:  Master track XML
# Output: CSV dataframe with features
# =============================================================================

echo "=========================================="
echo "Medaka Data: Feature Extraction"
echo "Job started: $(date)"
echo "Running on node: $(hostname)"
echo "Job ID: $SLURM_JOB_ID"
echo "=========================================="

# =============================================================================
# CONFIGURATION
# =============================================================================

EMBRYO_CONFIG="medaka/M34_P02_control"

if [ -n "$1" ]; then
    EMBRYO_CONFIG="$1"
fi

# =============================================================================
# SETUP
# =============================================================================

module load singularity 2>/dev/null || true

REPO_ROOT="/users/andres.ortiz/projects/CopenhagenWorkflow"
CONTAINER="${REPO_ROOT}/copenhagen_workflow.sif"

cd "${REPO_ROOT}" || { echo "ERROR: Cannot cd to ${REPO_ROOT}"; exit 1; }

mkdir -p logs

echo "Configuration:"
echo "  Embryo config: ${EMBRYO_CONFIG}"
echo ""

# =============================================================================
# RUN FEATURE EXTRACTION
# =============================================================================
echo "=========================================="
echo "Extracting features to dataframe..."
echo "=========================================="

singularity exec \
    ${CONTAINER} \
    python 07_masterxml_dataframe.py \
    experiment_data_paths=${EMBRYO_CONFIG}

EXIT_CODE=$?

echo ""
echo "=========================================="
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "SUCCESS: Feature extraction completed"
    echo ""
    echo "Output: CSV file with per-cell features"
    echo ""
    echo "Optional next step: Cell fate classification"
    echo "  sbatch sbatch_scripts/medaka/09_cell_fate.sh ${EMBRYO_CONFIG}"
else
    echo "ERROR: Feature extraction failed with exit code ${EXIT_CODE}"
fi
echo "Job ended: $(date)"
echo "=========================================="

exit ${EXIT_CODE}
