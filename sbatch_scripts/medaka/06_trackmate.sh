#!/bin/bash
#SBATCH --job-name=medaka_trackmate
#SBATCH --partition=c                    # CPU partition (Fiji doesn't use GPU well)
#SBATCH --cpus-per-task=16               # Multiple CPUs for Fiji
#SBATCH --mem=128G                       # High memory for large timelapses
#SBATCH --time=12:00:00                  # 12 hours for long timelapse
#SBATCH --output=logs/medaka_trackmate_%j.out
#SBATCH --error=logs/medaka_trackmate_%j.err

# =============================================================================
# Step 06: TrackMate Tracking (Fiji)
# =============================================================================
# Runs automated tracking using TrackMate in Fiji (headless mode).
#
# NOTE: For 576 timepoints, this will take significant time!
# Consider processing a subset first to validate parameters.
#
# Input:  tracking/*.tif (hyperstack)
# Output: tracking/*.xml (TrackMate tracks)
# =============================================================================

echo "=========================================="
echo "Medaka Data: TrackMate Tracking"
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
# RUN TRACKMATE
# =============================================================================
echo "=========================================="
echo "Starting TrackMate tracking..."
echo "=========================================="
echo "NOTE: This may take many hours for 576 timepoints"
echo ""

singularity exec \
    ${CONTAINER} \
    /opt/Fiji.app/fiji-linux-x64 --headless \
    --run 05_automate_trackmate.py

EXIT_CODE=$?

echo ""
echo "=========================================="
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "SUCCESS: TrackMate tracking completed"
    echo ""
    echo "Next step: Master tracking assembly"
    echo "  sbatch sbatch_scripts/medaka/07_master_tracking.sh ${EMBRYO_CONFIG}"
else
    echo "ERROR: TrackMate tracking failed with exit code ${EXIT_CODE}"
fi
echo "Job ended: $(date)"
echo "=========================================="

exit ${EXIT_CODE}
