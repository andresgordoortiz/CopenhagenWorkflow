#!/bin/bash
#SBATCH --job-name=medaka_master
#SBATCH --partition=c                    # CPU partition
#SBATCH --cpus-per-task=8                # 8 CPUs
#SBATCH --mem=64G                        # 64GB RAM
#SBATCH --time=04:00:00                  # 4 hours
#SBATCH --output=logs/medaka_master_%j.out
#SBATCH --error=logs/medaka_master_%j.err

# =============================================================================
# Step 07: Master Tracking Assembly
# =============================================================================
# Assembles tracks from TrackMate into a master track structure.
#
# Input:  tracking/*.xml (TrackMate output)
# Output: Master track XML with cell shape features
# =============================================================================

echo "=========================================="
echo "Medaka Data: Master Tracking"
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
# RUN MASTER TRACKING
# =============================================================================
echo "=========================================="
echo "Assembling master tracks..."
echo "=========================================="

singularity exec \
    ${CONTAINER} \
    python 06_master_tracking.py \
    experiment_data_paths=${EMBRYO_CONFIG}

EXIT_CODE=$?

echo ""
echo "=========================================="
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "SUCCESS: Master tracking completed"
    echo ""
    echo "Next step: Extract features to dataframe"
    echo "  sbatch sbatch_scripts/medaka/08_dataframe.sh ${EMBRYO_CONFIG}"
else
    echo "ERROR: Master tracking failed with exit code ${EXIT_CODE}"
fi
echo "Job ended: $(date)"
echo "=========================================="

exit ${EXIT_CODE}
