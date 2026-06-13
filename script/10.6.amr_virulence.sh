#!/bin/bash
#SBATCH --job-name=amr_virulence
#SBATCH --output=log/amr_virulence_%j.out
#SBATCH --error=log/amr_virulence_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --mem=32G

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

# Check if AMR & Virulence analysis is enabled
if [[ "$RUN_AMR_VIRULENCE" != "true" ]]; then
    echo "AMR and Virulence analysis is disabled in config.sh. Skipping."
    exit 0
fi

# Input is the final refined/cleaned assemblies
IN_DIR="$RESULT_DIR/collected_assemblies"
OUT_DIR="$RESULT_DIR/amr_virulence"

mkdir -p "$OUT_DIR" "$LOG_DIR"

echo "====================================================================="
echo "   RUNNING AMR & VIRULENCE ANALYSIS (CARD, RESFINDER, VFDB)"
echo "   Input assemblies: $IN_DIR"
echo "   Output directory:  $OUT_DIR"
echo "   ABRicate Database: $ABRICATE_DB_DIR"
echo "====================================================================="

# Check database existence
if [ ! -d "$ABRICATE_DB_DIR" ] || [ -z "$(ls -A "$ABRICATE_DB_DIR" 2>/dev/null)" ]; then
    echo "ERROR: ABRicate database not found at $ABRICATE_DB_DIR. Please run database downloader first."
    exit 1
fi

for assembly in "$IN_DIR"/*.fasta; do
    [ -e "$assembly" ] || continue
    
    # Skip backup files
    if [[ "$(basename "$assembly")" == *"_original.fasta"* ]]; then
        continue
    fi

    SAMPLE=$(basename "$assembly" .fasta)

    echo "--> Analyzing Sample: $SAMPLE"
    
    # Run CARD
    if [[ ! -f "$OUT_DIR/${SAMPLE}_card.tsv" ]]; then
        echo "    Running CARD..."
        if ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e amr-virulence abricate --datadir "$ABRICATE_DB_DIR" --db card --threads "$CPUS_MIN" "$assembly" > "$OUT_DIR/${SAMPLE}_card.tsv"; then
            echo "WARNING: ABRicate CARD failed for sample: $SAMPLE"
        fi
    else
        echo "    CARD results exist. Skipping."
    fi

    # Run ResFinder
    if [[ ! -f "$OUT_DIR/${SAMPLE}_resfinder.tsv" ]]; then
        echo "    Running ResFinder..."
        if ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e amr-virulence abricate --datadir "$ABRICATE_DB_DIR" --db resfinder --threads "$CPUS_MIN" "$assembly" > "$OUT_DIR/${SAMPLE}_resfinder.tsv"; then
            echo "WARNING: ABRicate ResFinder failed for sample: $SAMPLE"
        fi
    else
        echo "    ResFinder results exist. Skipping."
    fi

    # Run VFDB
    if [[ ! -f "$OUT_DIR/${SAMPLE}_vfdb.tsv" ]]; then
        echo "    Running VFDB..."
        if ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e amr-virulence abricate --datadir "$ABRICATE_DB_DIR" --db vfdb --threads "$CPUS_MIN" "$assembly" > "$OUT_DIR/${SAMPLE}_vfdb.tsv"; then
            echo "WARNING: ABRicate VFDB failed for sample: $SAMPLE"
        fi
    else
        echo "    VFDB results exist. Skipping."
    fi

    # Run RGI (Resistance Gene Identifier)
    if [[ ! -f "$OUT_DIR/${SAMPLE}_rgi.txt" ]]; then
        echo "    Running RGI..."
        if ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e rgi rgi main --input_sequence "$assembly" --output_file "$OUT_DIR/${SAMPLE}_rgi" --input_type contig --num_threads "$CPUS_MIN" --clean; then
            echo "WARNING: RGI failed for sample: $SAMPLE"
        fi
    else
        echo "    RGI results exist. Skipping."
    fi

    echo "--> Completed Sample: $SAMPLE"
done

touch "$OUT_DIR/amr_virulence_success.flag"
echo "====================================================================="
echo "   AMR & VIRULENCE ANALYSIS RUN COMPLETE"
echo "====================================================================="
