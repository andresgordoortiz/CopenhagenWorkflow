#!/bin/bash
#SBATCH --job-name=medaka_seg_nuclei
#SBATCH --partition=g                    # GPU partition
#SBATCH --gres=gpu:A100:1                # Request 1 A100 GPU
#SBATCH --cpus-per-task=8                # 8 CPUs
#SBATCH --mem=64G                        # 64GB RAM
#SBATCH --time=08:00:00                  # 8 hours (long timelapse!)
#SBATCH --output=logs/medaka_seg_nuclei_%j.out
#SBATCH --error=logs/medaka_seg_nuclei_%j.err

# =============================================================================
# Step 02: Nuclei Segmentation with StarDist/VollSeg
# =============================================================================
# This step segments nuclei in the H2A-mCherry channel.
#
# IMPORTANT NOTES FOR MEDAKA DATA:
# - Low resolution (5x, ~2µm/px) means nuclei are ~4-6 pixels diameter
# - Very sparse Z (100µm step) - essentially 2D with sparse depth
# - StarDist 3D may struggle - consider 2D approach per slice
# - 576 timepoints will take significant time
#
# Input:  nuclei_timelapses/*.tif
# Output: seg_nuclei_timelapses/*.tif (label masks)
# =============================================================================

echo "=========================================="
echo "Medaka Data: Nuclei Segmentation"
echo "Job started: $(date)"
echo "Running on node: $(hostname)"
echo "Job ID: $SLURM_JOB_ID"
echo "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader)"
echo "=========================================="

# =============================================================================
# CONFIGURATION
# =============================================================================

# Which embryo position to process
EMBRYO_CONFIG="medaka/M34_P02_control"

# Use command line argument if provided
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

echo ""
echo "Configuration:"
echo "  Embryo config: ${EMBRYO_CONFIG}"
echo "  Parameters: medaka/medaka"
echo ""

# =============================================================================
# RUN SEGMENTATION
# =============================================================================
echo "=========================================="
echo "Starting nuclei segmentation..."
echo "=========================================="
echo "NOTE: This may take several hours for 576 timepoints"
echo ""

singularity exec --nv \
    ${CONTAINER} \
    python 01_nuclei_segmentation.py \
    experiment_data_paths=${EMBRYO_CONFIG} \
    parameters=medaka/medaka

EXIT_CODE=$?

echo ""
echo "=========================================="
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "SUCCESS: Nuclei segmentation completed"
    echo ""
    echo "IMPORTANT: Review segmentation quality before proceeding!"
    echo "  - Check if nuclei are properly detected at low resolution"
    echo "  - Verify no over/under-segmentation"
    echo ""
    echo "Next step: Run membrane enhancement (optional) or mitosis detection"
    echo "  sbatch sbatch_scripts/medaka/03_mitosis_detection.sh ${EMBRYO_CONFIG}"
else
    echo "ERROR: Nuclei segmentation failed with exit code ${EXIT_CODE}"
    echo ""
    echo "Common issues:"
    echo "  - GPU memory: Try increasing n_tiles in parameters"
    echo "  - Small nuclei: Adjust diameter_cellpose and min_size"
fi
echo "Job ended: $(date)"
echo "=========================================="

exit ${EXIT_CODE}
