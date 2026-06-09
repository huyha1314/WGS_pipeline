#!/bin/bash
# ==============================================================================
#                 PRECISIONGENE WGS PIPELINE - POST-CLEANING QUALITY VERIFICATION (CheckM)
# ==============================================================================
# This script runs CheckM on the cleaned assemblies to verify that
# contamination has successfully dropped below 5%.

#SBATCH --job-name=bac_checkm_clean
#SBATCH --output=log/checkm_clean_%j.out
#SBATCH --error=log/checkm_clean_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=350G

# --- Load Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

COLLECTED_DIR="$RESULT_DIR/collected_assemblies"
CHECKM_OUT_DIR="$RESULT_DIR/checkm_cleaned"

# Create output directories
rm -rf "$CHECKM_OUT_DIR"
mkdir -p "$CHECKM_OUT_DIR" "$LOG_DIR"

total_genomes=$(ls -1 "$COLLECTED_DIR"/*.fasta 2>/dev/null | grep -v "_original" | wc -l)
echo "--------------------------------"
echo "Verifying $total_genomes cleaned assemblies in $COLLECTED_DIR with CheckM"
echo "--------------------------------"

if [[ $total_genomes -eq 0 ]]; then
    echo "ERROR: No assemblies found in $COLLECTED_DIR. Exiting."
    exit 1
fi

# --- STEP 1: Run CheckM (Quality & Completeness) ---
echo "Starting CheckM Lineage Workflow on cleaned assemblies..."

# Configure CheckM data directory first (just in case)
if [[ -d "$CHECKM_DB_PATH" ]]; then
    pixi run -e taxonomy checkm data setRoot "$CHECKM_DB_PATH"
fi

pixi run -e taxonomy checkm lineage_wf \
    -t "$CPUS_MED" \
    -x fasta \
    --pplacer_threads "$CPUS_MAX" \
    "$COLLECTED_DIR" \
    "$CHECKM_OUT_DIR"

if [ $? -ne 0 ]; then
    echo "ERROR: CheckM lineage_wf failed on cleaned assemblies!"
    exit 1
fi

# Generate checkm summary report
pixi run -e taxonomy checkm qa \
    "${CHECKM_OUT_DIR}/lineage.ms" \
    "${CHECKM_OUT_DIR}" \
    -o 2 > "${CHECKM_OUT_DIR}/checkm_summary.txt"

if [ $? -ne 0 ]; then
    echo "ERROR: CheckM qa failed on cleaned assemblies!"
    exit 1
fi

echo "CheckM Finished. Cleaned genomes summary at: ${CHECKM_OUT_DIR}/checkm_summary.txt"
cat "${CHECKM_OUT_DIR}/checkm_summary.txt"
touch "$CHECKM_OUT_DIR/checkm_success.flag"
