#!/bin/bash
#SBATCH --job-name=busco
#SBATCH --output=log/busco_%j.out
#SBATCH --error=log/busco_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=120G

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

BASE_DIR="$RESULT_DIR/collected_assemblies"
OUT_DIR="$RESULT_DIR/busco"
CHECKM_FILE="$RESULT_DIR/checkm_cleaned/checkm_summary.txt"

mkdir -p "$OUT_DIR" "$LOG_DIR"

echo "Starting Automated BUSCO analysis..."
echo "--------------------------------"

for INPUT_FILE in "$BASE_DIR"/*.fasta; do
    [ -e "$INPUT_FILE" ] || continue
    
    # Skip backup files
    if [[ "$(basename "$INPUT_FILE")" == *"_original.fasta"* ]]; then
        continue
    fi
    
    SAMPLE=$(basename "$INPUT_FILE" .fasta)

    SAMPLE_OUT_DIR="${OUT_DIR}/${SAMPLE}_busco"
    EXPECTED_SUMMARY_PATTERN="${SAMPLE_OUT_DIR}/short_summary.*.${SAMPLE}_busco.txt"

    # --- RESUME MECHANISM ---
    if ls ${EXPECTED_SUMMARY_PATTERN} 1> /dev/null 2>&1; then
        echo "SKIPPING: $SAMPLE (BUSCO analysis already completed)"
    else
        echo "Processing $SAMPLE with BUSCO auto-lineage..."

        # Run BUSCO in statistics environment
        pixi run -e statistics busco -i "$INPUT_FILE" \
              -o "${SAMPLE}_busco" \
              --out_path "$OUT_DIR" \
              --auto-lineage-prok \
              -m genome \
              -c "$CPUS_MED" \
              --force

        echo "$SAMPLE analysis complete."
    fi
    echo "--------------------------------"
done

# Final summary collection
echo "Final Summary of BUSCO Scores:"
if ls ${OUT_DIR}/*/short_summary.*.txt 1> /dev/null 2>&1; then
    cat ${OUT_DIR}/*/short_summary.*.txt | grep -E "C:|S:|D:|F:|M:|n:"
else
    echo "No summary files found yet."
fi

touch "$OUT_DIR/busco_success.flag"