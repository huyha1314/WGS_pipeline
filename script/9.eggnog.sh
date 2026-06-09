#!/bin/bash
#SBATCH --job-name=eggnog_func
#SBATCH --output=log/eggnog_%j.out
#SBATCH --error=log/eggnog_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=120G

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

ANNOTATION_DIR="$RESULT_DIR/annotation" 
OUT_DIR="$RESULT_DIR/eggnog"

mkdir -p "$OUT_DIR" "$LOG_DIR"

# Explicitly override the eggnog data directory environment variable
export EGGNOG_DATA_DIR="$EGGNOG_DB_PATH"

for faa_file in "$ANNOTATION_DIR"/*/*.faa; do
    [ -e "$faa_file" ] || continue
    SAMPLE=$(basename "$faa_file" .faa)
    
    echo "=== Running eggNOG-mapper on $SAMPLE ==="
    
    # Check if already done
    if [[ -f "${OUT_DIR}/${SAMPLE}.emapper.annotations" ]]; then
        echo "Skipping $SAMPLE (Already done)"
        continue
    fi

    # Run eggNOG-mapper in the functional environment
    pixi run -e functional emapper.py \
        -i "$faa_file" \
        --output "$SAMPLE" \
        --output_dir "$OUT_DIR" \
        --data_dir "$EGGNOG_DB_PATH" \
        -m diamond \
        --cpu "$CPUS_MED" \
        --sensmode more-sensitive

    echo "=== Finished $SAMPLE ==="
done

touch "$OUT_DIR/eggnog_success.flag"