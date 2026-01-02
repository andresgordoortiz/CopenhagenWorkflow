#!/bin/bash
#SBATCH --job-name=medaka_oneat
#SBATCH --partition=g                    # GPU partition
#SBATCH --gres=gpu:A100:1                # Request 1 A100 GPU
#SBATCH --cpus-per-task=8                # 8 CPUs
#SBATCH --mem=64G                        # 64GB RAM
#SBATCH --time=04:00:00                  # 4 hours
#SBATCH --output=logs/medaka_oneat_%j.out
#SBATCH --error=logs/medaka_oneat_%j.err

# =============================================================================
# Step 03: Mitosis Detection with Oneat
# =============================================================================
# This step detects mitotic events using the Oneat neural network.
#
# ⚠️  IMPORTANT WARNING FOR MEDAKA DATA:
# The Oneat model was trained on high-resolution Xenopus data (~1µm/px).
# Your Medaka data at 5x (~2µm/px with 100µm Z-steps) is VERY different!
#
# EXPECTED ISSUES:
# - Many false positives (small bright objects misclassified)
# - Many false negatives (real divisions too small to detect)
# - Model may not generalize well to different cell appearances
#
# RECOMMENDATIONS:
# 1. Run with VERY HIGH thresholds (event_confidence > 0.95)
# 2. MANUALLY REVIEW all detections
# 3. Consider this step EXPLORATORY rather than reliable
# 4. Alternative: Track lineages and infer divisions from splits
#
# Input:  nuclei_timelapses/*.tif + seg_nuclei_timelapses/*.tif
# Output: oneat_detections/*.csv (mitosis locations)
# =============================================================================

echo "=========================================="
echo "Medaka Data: Mitosis Detection (Oneat)"
echo "Job started: $(date)"
echo "Running on node: $(hostname)"
echo "Job ID: $SLURM_JOB_ID"
echo "=========================================="

echo ""
echo "⚠️  WARNING: Oneat was not trained on this type of data!"
echo "   - Low resolution (5x) and sparse Z may cause issues"
echo "   - Review all detections manually"
echo ""

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
echo "  Parameters: medaka/oneat_medaka"
echo ""

# =============================================================================
# RUN ONEAT
# =============================================================================
echo "=========================================="
echo "Starting mitosis detection..."
echo "=========================================="

singularity exec --nv \
    ${CONTAINER} \
    python 02_oneat_nuclei.py \
    experiment_data_paths=${EMBRYO_CONFIG} \
    parameters=medaka/oneat_medaka

EXIT_CODE=$?

echo ""
echo "=========================================="
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "SUCCESS: Mitosis detection completed"
    echo ""
    echo "⚠️  IMPORTANT: Review detections before proceeding!"
    echo "   Output CSV contains putative mitosis locations"
    echo "   Many may be false positives at this resolution"
    echo ""
    echo "Next step: Non-maximum suppression"
    echo "  sbatch sbatch_scripts/medaka/04_nms.sh ${EMBRYO_CONFIG}"
else
    echo "ERROR: Mitosis detection failed with exit code ${EXIT_CODE}"
fi
echo "Job ended: $(date)"
echo "=========================================="

exit ${EXIT_CODE}
