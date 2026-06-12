#!/bin/bash
#SBATCH --job-name=plasmid_pred
#SBATCH --output=log/plasmid_%j.out
#SBATCH --error=log/plasmid_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=56
#SBATCH --mem=120G

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

IN_DIR="$RESULT_DIR/collected_assemblies"
GENOMAD_OUT_DIR="$RESULT_DIR/genomad"
CHECKV_OUT_DIR="$RESULT_DIR/checkv"

mkdir -p "$GENOMAD_OUT_DIR" "$CHECKV_OUT_DIR" "$LOG_DIR"

echo "====================================================="
# In case checkv db path has not been set up, checkv needs it
export CHECKVDB="$CHECKV_DB_PATH"

for assembly in "$IN_DIR"/*.fasta; do
    [ -e "$assembly" ] || continue
    
    # Skip backup files
    if [[ "$(basename "$assembly")" == *"_original.fasta"* ]]; then
        continue
    fi

    SAMPLE=$(basename "$assembly" .fasta)

    echo "=== Running Plasmid & Virus Prediction for: $SAMPLE ==="

    sample_genomad_out="${GENOMAD_OUT_DIR}/${SAMPLE}"
    
    # 1. Run geNomad end-to-end
    if [[ -d "$sample_genomad_out" && -f "${sample_genomad_out}/${SAMPLE}_summary/${SAMPLE}_plasmid.fna" ]]; then
        echo " -> geNomad already completed for $SAMPLE. Skipping."
    else
        echo " -> Executing geNomad end-to-end..."
        # Clean up partial output folder if exists
        rm -rf "$sample_genomad_out"
        
        pixi run -e plasmid genomad end-to-end \
            --cleanup \
            --splits 4 \
            --threads "$CPUS_MED" \
            "$assembly" \
            "$sample_genomad_out" \
            "$GENOMAD_DB_PATH"
            
        echo " -> geNomad completed for $SAMPLE."
    fi

    # 2. Run CheckV on predicted virus contigs (if any are found)
    virus_fna="${sample_genomad_out}/${SAMPLE}_summary/${SAMPLE}_virus.fna"
    sample_checkv_out="${CHECKV_OUT_DIR}/${SAMPLE}"

    if [[ -s "$virus_fna" ]]; then
        if [[ -d "$sample_checkv_out" && -f "${sample_checkv_out}/quality_summary.tsv" ]]; then
            echo " -> CheckV already completed for $SAMPLE. Skipping."
        else
            echo " -> Virus sequences found! Running CheckV quality assessment..."
            rm -rf "$sample_checkv_out"
            
            pixi run -e plasmid checkv end_to_end \
                "$virus_fna" \
                "$sample_checkv_out" \
                -d "$CHECKV_DB_PATH" \
                -t "$CPUS_MED"
                
            echo " -> CheckV completed for $SAMPLE."
        fi
    else
        echo " -> No virus contigs detected by geNomad for $SAMPLE. Skipping CheckV."
    fi

    echo "=== Finished Plasmid/Virus Prediction for $SAMPLE ==="
done

touch "$GENOMAD_OUT_DIR/genomad_success.flag"
