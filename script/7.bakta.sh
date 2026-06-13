#!/bin/bash
#SBATCH --job-name=bakta_annotation
#SBATCH --output=log/bakta_%j.out
#SBATCH --error=log/bakta_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

# Input is the final refined/cleaned assemblies
IN_DIR="$RESULT_DIR/collected_assemblies"
OUT_DIR="$RESULT_DIR/annotation"

mkdir -p "$OUT_DIR" "$LOG_DIR"

for assembly in "$IN_DIR"/*.fasta; do
    [ -e "$assembly" ] || continue
    
    # Skip backup files
    if [[ "$(basename "$assembly")" == *"_original.fasta"* ]]; then
        continue
    fi

    SAMPLE=$(basename "$assembly" .fasta)

    echo "=== Annotating Sample: $SAMPLE ==="

    sample_out="${OUT_DIR}/${SAMPLE}"
    
    # Check if already done (Bakta produces a .gbff file)
    if [[ -f "${sample_out}/${SAMPLE}.gbff" ]]; then
        echo "Annotation exists for $SAMPLE. Skipping."
        continue
    fi

    # Extract base sample name (e.g., 85_bin.5 -> 85)
    base_sample=$(echo "$SAMPLE" | cut -d'_' -f1)
    
    # Lookup custom genus/species in samples.tsv
    g_s_line=$(grep -w "^$base_sample" "$INPUT_SHEET" 2>/dev/null)
    if [[ -n "$g_s_line" ]]; then
        GENUS=$(echo "$g_s_line" | cut -d$'\t' -f4)
        SPECIES=$(echo "$g_s_line" | cut -d$'\t' -f5)
    else
        GENUS=""
        SPECIES=""
    fi

    # Determine genus and species, fallback to config.sh defaults if empty
    run_genus="${GENUS:-$BAKTA_GENUS}"
    run_species="${SPECIES:-$BAKTA_SPECIES}"

    # Prevent Diamond segmentation faults (error code -11/SIGSEGV)
    ulimit -s unlimited
    export OMP_STACKSIZE=256M

    # Run Bakta in the Pixi annotation environment
    if ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e annotation bakta \
        --db "$BAKTA_DB" \
        --output "$sample_out" \
        --prefix "$SAMPLE" \
        --locus-tag "$SAMPLE" \
        --threads "$CPUS_MIN" \
        --genus "$run_genus" \
        --species "$run_species" \
        --force \
        "$assembly"; then
        echo "ERROR: Bakta failed for sample: $SAMPLE"
        exit 1
    fi

    echo "=== Finished $SAMPLE ==="
done

touch "$OUT_DIR/bakta_success.flag"