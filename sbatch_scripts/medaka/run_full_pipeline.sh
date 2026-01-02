#!/bin/bash
# =============================================================================
# MEDAKA PIPELINE: Run All Steps
# =============================================================================
# Convenience script to run the full pipeline for a single embryo.
#
# Usage:
#   ./run_full_pipeline.sh <config_name>
#
# Example:
#   ./run_full_pipeline.sh medaka/M34_P02_control
#
# This will submit all jobs with dependencies so they run in sequence.
# =============================================================================

if [ -z "$1" ]; then
    echo "Usage: $0 <config_name>"
    echo "Example: $0 medaka/M34_P02_control"
    exit 1
fi

CONFIG="$1"
REPO_ROOT="/users/andres.ortiz/projects/CopenhagenWorkflow"

cd "${REPO_ROOT}" || { echo "ERROR: Cannot cd to ${REPO_ROOT}"; exit 1; }

echo "=========================================="
echo "MEDAKA PIPELINE: Full Run"
echo "Config: ${CONFIG}"
echo "=========================================="
echo ""

# Create logs directory
mkdir -p logs

# Submit jobs with dependencies
echo "Submitting Step 01: Channel splitting..."
JOB1=$(sbatch --parsable ${SCRIPT_DIR}/01_split_channels.sh ${CONFIG})
echo "  Job ID: ${JOB1}"

echo "Submitting Step 02: Nuclei segmentation (depends on ${JOB1})..."
JOB2=$(sbatch --parsable --dependency=afterok:${JOB1} ${SCRIPT_DIR}/02_segment_nuclei.sh ${CONFIG})
echo "  Job ID: ${JOB2}"

echo "Submitting Step 03: Mitosis detection (depends on ${JOB2})..."
JOB3=$(sbatch --parsable --dependency=afterok:${JOB2} ${SCRIPT_DIR}/03_mitosis_detection.sh ${CONFIG})
echo "  Job ID: ${JOB3}"

echo "Submitting Step 04: NMS (depends on ${JOB3})..."
JOB4=$(sbatch --parsable --dependency=afterok:${JOB3} ${SCRIPT_DIR}/04_nms.sh ${CONFIG})
echo "  Job ID: ${JOB4}"

echo "Submitting Step 05: Prepare tracking (depends on ${JOB4})..."
JOB5=$(sbatch --parsable --dependency=afterok:${JOB4} ${SCRIPT_DIR}/05_prepare_tracking.sh ${CONFIG})
echo "  Job ID: ${JOB5}"

echo "Submitting Step 06: TrackMate (depends on ${JOB5})..."
JOB6=$(sbatch --parsable --dependency=afterok:${JOB5} ${SCRIPT_DIR}/06_trackmate.sh ${CONFIG})
echo "  Job ID: ${JOB6}"

echo "Submitting Step 07: Master tracking (depends on ${JOB6})..."
JOB7=$(sbatch --parsable --dependency=afterok:${JOB6} ${SCRIPT_DIR}/07_master_tracking.sh ${CONFIG})
echo "  Job ID: ${JOB7}"

echo "Submitting Step 08: Feature extraction (depends on ${JOB7})..."
JOB8=$(sbatch --parsable --dependency=afterok:${JOB7} ${SCRIPT_DIR}/08_dataframe.sh ${CONFIG})
echo "  Job ID: ${JOB8}"

echo ""
echo "=========================================="
echo "All jobs submitted!"
echo "=========================================="
echo ""
echo "Job chain: ${JOB1} -> ${JOB2} -> ${JOB3} -> ${JOB4} -> ${JOB5} -> ${JOB6} -> ${JOB7} -> ${JOB8}"
echo ""
echo "Monitor with:"
echo "  squeue -u \$USER"
echo ""
echo "View logs:"
echo "  tail -f logs/medaka_*_${JOB1}.out"
echo ""
echo "Cancel all:"
echo "  scancel ${JOB1} ${JOB2} ${JOB3} ${JOB4} ${JOB5} ${JOB6} ${JOB7} ${JOB8}"
