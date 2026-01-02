#!/bin/bash
#SBATCH --job-name=medaka_nms
#SBATCH --partition=c                    # CPU partition (no GPU needed)
#SBATCH --cpus-per-task=8                # 8 CPUs
#SBATCH --mem=32G                        # 32GB RAM
#SBATCH --time=01:00:00                  # 1 hour
#SBATCH --output=logs/medaka_nms_%j.out
#SBATCH --error=logs/medaka_nms_%j.err

# =============================================================================
# Step 04: Non-Maximum Suppression for Oneat Detections
# =============================================================================
# Removes duplicate/overlapping mitosis detections.
#
# Input:  oneat_detections/*.csv (raw detections)
# Output: oneat_detections/non_maximal_*.csv (filtered detections)
# =============================================================================

echo "=========================================="
echo "Medaka Data: Non-Maximum Suppression"
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
# RUN NMS
# =============================================================================
echo "=========================================="
echo "Starting non-maximum suppression..."
echo "=========================================="

singularity exec \
    ${CONTAINER} \
    python 03_nms_nuclei_automated.py \
    experiment_data_paths=${EMBRYO_CONFIG}

EXIT_CODE=$?

echo ""
echo "=========================================="
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "SUCCESS: NMS completed"
    echo ""
    echo "Next step: Prepare tracking"
    echo "  sbatch sbatch_scripts/medaka/05_prepare_tracking.sh ${EMBRYO_CONFIG}"
else
    echo "ERROR: NMS failed with exit code ${EXIT_CODE}"
fi
echo "Job ended: $(date)"
echo "=========================================="

exit ${EXIT_CODE}
