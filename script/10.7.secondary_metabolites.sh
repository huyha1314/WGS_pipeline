#!/bin/bash
#SBATCH --job-name=secondary_metabolites
#SBATCH --output=log/secondary_metabolites_%j.out
#SBATCH --error=log/secondary_metabolites_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --mem=64G

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

# Check if secondary analysis is enabled
if [[ "$RUN_ANTISMASH" != "true" && "$RUN_BAGEL4" != "true" ]]; then
    echo "Secondary analysis (antiSMASH & BAGEL4) is disabled in config.sh. Skipping."
    exit 0
fi

# Input is the final refined/cleaned assemblies
IN_DIR="$RESULT_DIR/collected_assemblies"
OUT_DIR="$RESULT_DIR/secondary_metabolites"

mkdir -p "$OUT_DIR/antismash" "$OUT_DIR/bagel4" "$LOG_DIR"

echo "====================================================================="
echo "   RUNNING SECONDARY METABOLITE ANALYSIS (ANTISMASH & BAGEL4)"
echo "   Input assemblies: $IN_DIR"
echo "   Output directory:  $OUT_DIR"
echo "   antiSMASH DB:     $ANTISMASH_DB_DIR"
echo "   BAGEL4 Path:      $BAGEL4_DIR"
echo "====================================================================="

for assembly in "$IN_DIR"/*.fasta; do
    [ -e "$assembly" ] || continue
    
    # Skip backup files
    if [[ "$(basename "$assembly")" == *"_original.fasta"* ]]; then
        continue
    fi

    SAMPLE=$(basename "$assembly" .fasta)

    echo "--> Analyzing Sample: $SAMPLE"

    # --- 1. Run antiSMASH ---
    if [[ "$RUN_ANTISMASH" == "true" ]]; then
        # Check if databases exist
        if [ ! -d "$ANTISMASH_DB_DIR" ] || [ -z "$(ls -A "$ANTISMASH_DB_DIR" 2>/dev/null)" ]; then
            echo "ERROR: antiSMASH database not found at $ANTISMASH_DB_DIR. Please run database downloader."
            exit 1
        fi

        # Prefer GenBank (.gbff) output from Bakta if available
        GBK_FILE="$RESULT_DIR/annotation/${SAMPLE}/${SAMPLE}.gbff"
        if [ ! -f "$GBK_FILE" ]; then
            echo "    WARNING: GenBank file not found for $SAMPLE. Falling back to FASTA."
            GBK_FILE="$assembly"
        fi

        if [[ ! -f "$OUT_DIR/antismash/${SAMPLE}/index.html" ]]; then
            echo "    Running antiSMASH on $GBK_FILE..."
            if ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e secondary-metabolites antismash \
                --databases "$ANTISMASH_DB_DIR" \
                --genefinding-tool none \
                --cb-general \
                --cb-knownclusters \
                --cb-subclusters \
                --asf \
                --pfam2go \
                --cpus "$CPUS_MIN" \
                --output-dir "$OUT_DIR/antismash/${SAMPLE}" \
                "$GBK_FILE"; then
                echo "WARNING: antiSMASH failed for sample: $SAMPLE"
            fi
        else
            echo "    antiSMASH results exist for $SAMPLE. Skipping."
        fi
    fi

    # --- 2. Run BAGEL4 ---
    if [[ "$RUN_BAGEL4" == "true" ]]; then
        # Check if BAGEL4 standalone directory exists
        if [ ! -f "$BAGEL4_DIR/bagel4_wrapper.pl" ]; then
            echo "ERROR: BAGEL4 not found at $BAGEL4_DIR. Please run database downloader."
            exit 1
        fi

        if [[ ! -f "$OUT_DIR/bagel4/${SAMPLE}/index.html" && ! -d "$OUT_DIR/bagel4/${SAMPLE}/HTML" ]]; then
            echo "    Running BAGEL4..."
            export PERL5LIB="$BAGEL4_DIR/lib:$PERL5LIB"
            
            # BAGEL4 wrapper requires running from its folder or setting config correctly
            # We run it using perl wrapper
            if ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e secondary-metabolites perl "$BAGEL4_DIR/bagel4_wrapper.pl" \
                -query "$assembly" \
                -s "$OUT_DIR/bagel4/${SAMPLE}" \
                -cpu "$CPUS_MIN"; then
                echo "WARNING: BAGEL4 failed for sample: $SAMPLE"
            fi
        else
            echo "    BAGEL4 results exist for $SAMPLE. Skipping."
        fi
    fi

    echo "--> Completed Sample: $SAMPLE"
done

touch "$OUT_DIR/secondary_metabolites_success.flag"
echo "====================================================================="
echo "   SECONDARY METABOLITE ANALYSIS RUN COMPLETE"
echo "====================================================================="
