#!/bin/bash
#SBATCH --job-name=bac_gtdbtk
#SBATCH --output=log/gtdbtk_%j.out
#SBATCH --error=log/gtdbtk_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=56
#SBATCH --mem=350G 

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

COLLECTED_DIR="$RESULT_DIR/collected_assemblies"
GTDB_OUT_DIR="$RESULT_DIR/gtdbtk"

# Create output directories
rm -rf "$GTDB_OUT_DIR"
mkdir -p "$GTDB_OUT_DIR" "$LOG_DIR"

total_genomes=$(ls -1 "$COLLECTED_DIR"/*.fasta 2>/dev/null | grep -v "_original" | wc -l)
echo "--------------------------------"
echo "Running GTDB-Tk on $total_genomes assemblies in $COLLECTED_DIR"
echo "--------------------------------"

if [[ $total_genomes -eq 0 ]]; then
    echo "ERROR: No assemblies found in $COLLECTED_DIR. Exiting."
    exit 1
fi

# --- STEP 3: Run GTDB-Tk (Taxonomy Classification) ---
echo "Starting GTDB-Tk Classify Workflow..."

pixi run -e taxonomy gtdbtk classify_wf \
    --genome_dir "$COLLECTED_DIR" \
    --out_dir "$GTDB_OUT_DIR" \
    --extension fasta \
    --cpus "$CPUS_MED" \
    --pplacer_cpus "$CPUS_MIN" \
    --min_perc_aa "$GTDBTK_MIN_PERC_AA" \
    --force

if [ $? -ne 0 ]; then
    echo "ERROR: GTDB-Tk classify_wf failed!"
    exit 1
fi

echo "GTDB-Tk Finished. Outputs located at $GTDB_OUT_DIR"
touch "$GTDB_OUT_DIR/gtdbtk_success.flag"
