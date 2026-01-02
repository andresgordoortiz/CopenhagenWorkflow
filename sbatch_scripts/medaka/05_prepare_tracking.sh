#!/bin/bash
#SBATCH --job-name=medaka_prep_track
#SBATCH --partition=m                    # High memory partition
#SBATCH --cpus-per-task=8                # 8 CPUs
#SBATCH --mem=128G                       # 128GB RAM for large arrays
#SBATCH --time=02:00:00                  # 2 hours
#SBATCH --output=logs/medaka_prep_track_%j.out
#SBATCH --error=logs/medaka_prep_track_%j.err

# =============================================================================
# Step 05: Prepare Data for TrackMate Tracking
# =============================================================================
# Creates hyperstack format required by TrackMate (TZCYX).
#
# Input:  nuclei_timelapses/*.tif + seg_nuclei_timelapses/*.tif
# Output: tracking/*.tif (hyperstack for TrackMate)
# =============================================================================

echo "=========================================="
echo "Medaka Data: Prepare for Tracking"
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
# RUN PREPARATION
# =============================================================================
echo "=========================================="
echo "Preparing tracking data..."
echo "=========================================="

singularity exec \
    ${CONTAINER} \
    python 04_prepare_tracking.py \
    experiment_data_paths=${EMBRYO_CONFIG}

EXIT_CODE=$?

echo ""
echo "=========================================="
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "SUCCESS: Tracking preparation completed"
    echo ""
    echo "Next step: Run TrackMate"
    echo "  sbatch sbatch_scripts/medaka/06_trackmate.sh ${EMBRYO_CONFIG}"
else
    echo "ERROR: Tracking preparation failed with exit code ${EXIT_CODE}"
fi
echo "Job ended: $(date)"
echo "=========================================="

exit ${EXIT_CODE}
