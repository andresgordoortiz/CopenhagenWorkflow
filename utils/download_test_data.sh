#!/bin/bash
#===============================================================================
# download_test_data.sh - Download S-BIAD499 zebrafish gastrulation dataset
#===============================================================================
#
# This script downloads the S-BIAD499 dataset from EBI BioStudies.
# The dataset contains zebrafish embryos imaged during gastrulation with:
#   - Channel 0: drl:GFP (mesoderm marker)
#   - Channel 1: H2B-RFP (nuclei)
#
# Dataset info: https://www.ebi.ac.uk/biostudies/bioimages/studies/S-BIAD499
#
# Usage:
#   ./download_test_data.sh [output_dir] [num_timepoints]
#
# Examples:
#   ./download_test_data.sh                    # Download 50 timepoints to current dir
#   ./download_test_data.sh /scratch/data 100  # Download 100 timepoints
#   ./download_test_data.sh /scratch/data all  # Download ALL timepoints (~800)
#
#===============================================================================

set -e

# Configuration
OUTPUT_DIR="${1:-.}"
NUM_TIMEPOINTS="${2:-50}"
EMBRYO="wildtype-1"
BASE_URL="https://ftp.ebi.ac.uk/biostudies/fire/S-BIAD/499/S-BIAD499/Files/${EMBRYO}"

echo "=============================================="
echo "S-BIAD499 Zebrafish Gastrulation Dataset"
echo "=============================================="
echo "Output directory: $OUTPUT_DIR"
echo "Embryo: $EMBRYO"
echo "Timepoints: $NUM_TIMEPOINTS"
echo "=============================================="

# Create output directory
mkdir -p "${OUTPUT_DIR}/${EMBRYO}"
cd "${OUTPUT_DIR}/${EMBRYO}"

# Determine range
if [ "$NUM_TIMEPOINTS" = "all" ]; then
    # Full dataset has ~600-800 timepoints depending on embryo
    MAX_T=800
else
    MAX_T=$((NUM_TIMEPOINTS - 1))
fi

# Download files
echo "Starting download..."
failed_downloads=""

for t in $(seq 0 $MAX_T); do
    # Zero-pad to 4 digits
    T_PAD=$(printf "%04d" $t)
    
    # File names
    FILE_C0="${EMBRYO}_T${T_PAD}-C0.tiff"
    FILE_C1="${EMBRYO}_T${T_PAD}-C1.tiff"
    
    # Check if already downloaded
    if [ -f "$FILE_C0" ] && [ -f "$FILE_C1" ]; then
        echo "Timepoint $T_PAD: already exists, skipping"
        continue
    fi
    
    # Download channel 0 (mesoderm)
    if [ ! -f "$FILE_C0" ]; then
        echo -n "Downloading T${T_PAD}-C0..."
        if wget -q "${BASE_URL}/${FILE_C0}" -O "$FILE_C0" 2>/dev/null; then
            echo " OK"
        else
            echo " FAILED (may not exist)"
            rm -f "$FILE_C0"
            # If first file fails at timepoint > MAX_T, we've reached the end
            if [ $t -gt 10 ]; then
                echo "Reached end of dataset at timepoint $t"
                break
            fi
            failed_downloads="${failed_downloads} ${FILE_C0}"
        fi
    fi
    
    # Download channel 1 (nuclei)
    if [ ! -f "$FILE_C1" ]; then
        echo -n "Downloading T${T_PAD}-C1..."
        if wget -q "${BASE_URL}/${FILE_C1}" -O "$FILE_C1" 2>/dev/null; then
            echo " OK"
        else
            echo " FAILED"
            rm -f "$FILE_C1"
            failed_downloads="${failed_downloads} ${FILE_C1}"
        fi
    fi
done

# Summary
echo ""
echo "=============================================="
echo "Download Complete!"
echo "=============================================="
echo "Location: ${OUTPUT_DIR}/${EMBRYO}"
echo "Files:"
ls -1 | head -10
echo "..."
echo "Total files: $(ls -1 *.tiff 2>/dev/null | wc -l)"
echo "Total size: $(du -sh . | cut -f1)"

if [ -n "$failed_downloads" ]; then
    echo ""
    echo "WARNING: Some files failed to download:"
    echo "$failed_downloads"
fi

echo ""
echo "Next steps:"
echo "1. Merge files: python utils/merge_sbiad499.py -i ${OUTPUT_DIR}/${EMBRYO} -o ${OUTPUT_DIR}/merged"
echo "2. Update config: conf/experiment_data_paths/zebrafish_gastrulation.yaml"
echo "3. Run pipeline: python 00_create_nuclei_membrane_splits.py"
