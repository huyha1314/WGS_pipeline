#!/bin/bash
#SBATCH --job-name=busco_targeted
#SBATCH --output=log/busco_targeted_%j.out
#SBATCH --error=log/busco_targeted_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=120G

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

BASE_DIR="$RESULT_DIR/collected_assemblies"
OUT_DIR="$RESULT_DIR/busco"

mkdir -p "$OUT_DIR" "$LOG_DIR"

echo "Starting Targeted BUSCO analysis for sample 85 bins..."
echo "------------------------------------------------------"

# Define an array of the specific bins and their corresponding BUSCO lineages
declare -A BIN_LINEAGES=(
    ["85_maxbin.001"]="bacillales_odb12"
    ["85_maxbin.002"]="lactobacillales_odb12"
)

# Iterate through the associative array
for SAMPLE in "${!BIN_LINEAGES[@]}"; do
    INPUT_FILE="$BASE_DIR/${SAMPLE}.fasta"
    LINEAGE="${BIN_LINEAGES[$SAMPLE]}"
    
    if [ ! -f "$INPUT_FILE" ]; then
        echo "WARNING: Cannot find $INPUT_FILE. Skipping."
        continue
    fi

    SAMPLE_OUT_DIR="${OUT_DIR}/${SAMPLE}_busco"
    EXPECTED_SUMMARY_PATTERN="${SAMPLE_OUT_DIR}/short_summary.*.${SAMPLE}_busco.txt"

    # --- RESUME MECHANISM ---
    if ls ${EXPECTED_SUMMARY_PATTERN} 1> /dev/null 2>&1; then
        echo "SKIPPING: $SAMPLE (BUSCO analysis already completed)"
    else
        echo "Processing $SAMPLE using specific lineage: $LINEAGE"

        # Run BUSCO with explicit lineage
        pixi run -e statistics busco -i "$INPUT_FILE" \
              -o "${SAMPLE}_busco" \
              --out_path "$OUT_DIR" \
              -l "$LINEAGE" \
              -m genome \
              -c "$CPUS_MED" \
              --force

        echo "$SAMPLE analysis complete."
    fi
    echo "------------------------------------------------------"
done

# Final summary collection
echo "Targeted Summary of BUSCO Scores:"
for SAMPLE in "${!BIN_LINEAGES[@]}"; do
    if ls ${OUT_DIR}/${SAMPLE}_busco/short_summary.*.txt 1> /dev/null 2>&1; then
        echo "Results for $SAMPLE:"
        cat ${OUT_DIR}/${SAMPLE}_busco/short_summary.*.txt | grep -E "C:|S:|D:|F:|M:|n:"
    fi
done

echo "Script finished."