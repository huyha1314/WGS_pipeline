#!/bin/bash
#SBATCH --job-name=bac_checkm
#SBATCH --output=log/checkm_%j.out
#SBATCH --error=log/checkm_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=350G 

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

COLLECTED_DIR="$RESULT_DIR/collected_assemblies"
CHECKM_OUT_DIR="$RESULT_DIR/checkm"

# Create output directories
rm -rf "$CHECKM_OUT_DIR"
mkdir -p "$COLLECTED_DIR" "$CHECKM_OUT_DIR" "$LOG_DIR"

# --- STEP 1: Collect Assembly Files ---
echo "Starting Collection of Assemblies from samples sheet..."
echo "--------------------------------"

# Clear directory first to prevent mixing old and new runs
rm -f "$COLLECTED_DIR"/*.fasta

while IFS=$'\t' read -r SAMPLE R1_PATH R2_PATH; do
    if [[ "$SAMPLE" == "name" || -z "$SAMPLE" ]]; then
        continue
    fi
    
    # 1. Copy original polished assembly
    INPUT_FILE="$RESULT_DIR/final_polished/${SAMPLE}/${SAMPLE}_final_polished.fasta"
    if [[ -f "$INPUT_FILE" ]]; then
        echo "Copying original polished assembly for $SAMPLE..."
        cp "$INPUT_FILE" "${COLLECTED_DIR}/${SAMPLE}.fasta"
    else
        echo "WARNING: Original polished assembly not found for $SAMPLE"
    fi

    # 2. Copy all MetaBAT2 bins
    BIN_DIR="$RESULT_DIR/binning/${SAMPLE}/bins"
    if [[ -d "$BIN_DIR" && -n "$(ls -A "$BIN_DIR"/*.fa 2>/dev/null)" ]]; then
        echo "Copying all MetaBAT2 bins for $SAMPLE to collection..."
        for bin_file in "$BIN_DIR"/*.fa; do
            if [[ -f "$bin_file" ]]; then
                bin_basename=$(basename "$bin_file" .fa)
                cp "$bin_file" "${COLLECTED_DIR}/${bin_basename}.fasta"
            fi
        done
    else
        echo "WARNING: No MetaBAT2 bins found for $SAMPLE"
    fi
done < "$INPUT_SHEET"

total_genomes=$(ls -1 "$COLLECTED_DIR"/*.fasta 2>/dev/null | wc -l)
echo "Collection complete. Total genomes: $total_genomes"
echo "--------------------------------"

if [[ $total_genomes -eq 0 ]]; then
    echo "ERROR: No assemblies collected. Exiting."
    exit 1
fi

# --- STEP 2: Run CheckM (Quality & Completeness) ---
echo "Starting CheckM Lineage Workflow..."

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
    echo "ERROR: CheckM lineage_wf failed!"
    exit 1
fi

# Generate checkm summary report
pixi run -e taxonomy checkm qa \
    "${CHECKM_OUT_DIR}/lineage.ms" \
    "${CHECKM_OUT_DIR}" \
    -o 2 > "${CHECKM_OUT_DIR}/checkm_summary.txt"

if [ $? -ne 0 ]; then
    echo "ERROR: CheckM qa failed!"
    exit 1
fi

echo "CheckM Finished. Summary at: ${CHECKM_OUT_DIR}/checkm_summary.txt"
touch "$CHECKM_OUT_DIR/checkm_success.flag"
