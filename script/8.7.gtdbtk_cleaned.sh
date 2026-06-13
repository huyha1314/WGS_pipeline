#!/bin/bash
# ==============================================================================
#                 PRECISIONGENE WGS PIPELINE - POST-CLEANING TAXONOMY (GTDB-Tk)
# ==============================================================================
# This script runs GTDB-Tk on the cleaned assemblies to generate the final taxonomy.

#SBATCH --job-name=bac_gtdbtk_clean
#SBATCH --output=log/gtdbtk_clean_%j.out
#SBATCH --error=log/gtdbtk_clean_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=350G

# --- Load Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

COLLECTED_DIR="$RESULT_DIR/collected_assemblies"
GTDB_OUT_DIR="$RESULT_DIR/gtdbtk_cleaned"

# Create output directories
rm -rf "$GTDB_OUT_DIR"
mkdir -p "$GTDB_OUT_DIR" "$LOG_DIR"

total_genomes=$(ls -1 "$COLLECTED_DIR"/*.fasta 2>/dev/null | grep -v "_original" | wc -l)
echo "--------------------------------"
echo "Running GTDB-Tk on $total_genomes cleaned assemblies in $COLLECTED_DIR"
echo "--------------------------------"

if [[ $total_genomes -eq 0 ]]; then
    echo "ERROR: No assemblies found in $COLLECTED_DIR. Exiting."
    exit 1
fi

# --- STEP 2: Run GTDB-Tk (Taxonomy Classification) ---
echo "Starting GTDB-Tk Classify Workflow on cleaned assemblies..."

pixi run -e taxonomy gtdbtk classify_wf \
    --genome_dir "$COLLECTED_DIR" \
    --out_dir "$GTDB_OUT_DIR" \
    --extension fasta \
    --cpus "$CPUS_MED" \
    --pplacer_cpus "$CPUS_MIN" \
    --min_perc_aa "$GTDBTK_MIN_PERC_AA" \
    --force

if [ $? -ne 0 ]; then
    echo "ERROR: GTDB-Tk classify_wf failed on cleaned assemblies!"
    exit 1
fi

echo "GTDB-Tk Finished on cleaned assemblies. Outputs located at $GTDB_OUT_DIR"
touch "$GTDB_OUT_DIR/gtdbtk_success.flag"
