#!/bin/bash
#SBATCH --job-name=sspace_bac
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=60
#SBATCH --mem=240G
#SBATCH --output=log/sspace_bac_%j.out
#SBATCH --error=log/sspace_bac_%j.err

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

mkdir -p "$LOG_DIR" "$RESULT_DIR/sspaces"

while IFS=$'\t' read -r SAMPLE R1_PATH R2_PATH; do
    if [[ "$SAMPLE" == "name" || -z "$SAMPLE" ]]; then
        continue
    fi

    echo "=== Running SSPACE Scaffolding for sample: $SAMPLE ==="

    # Assembly input (Output from Pilon Round 1)
    contigs_in="$RESULT_DIR/bwa_pilon/${SAMPLE}/${SAMPLE}_pilon.fasta"

    # Verify assembly exists
    if [[ ! -f "$contigs_in" ]]; then
        echo "❌ Error: Pilon assembly not found at $contigs_in. Skipping."
        continue
    fi

    # Read inputs (Clean reads from Step 2)
    r1_in="$RESULT_DIR/k2/clean.${SAMPLE}_1.fq.gz"
    r2_in="$RESULT_DIR/k2/clean.${SAMPLE}_2.fq.gz"

    # Verify reads exist
    if [[ ! -f "$r1_in" || ! -f "$r2_in" ]]; then
        echo "❌ Error: Clean reads not found. Skipping."
        continue
    fi

    # Define Work Directory
    WORK_DIR="$RESULT_DIR/sspaces/${SAMPLE}_scaffold"
    mkdir -p "$WORK_DIR"
    
    # Check if finished
    final_output="${WORK_DIR}/${SAMPLE}_sspace.final.scaffolds.fasta"
    if [[ -s "$final_output" ]]; then
        echo "Skipping $SAMPLE (SSPACE already completed)"
        continue
    fi

    # Save original working directory
    ORIG_DIR="$PWD"
    cd "$WORK_DIR" || exit

    # Decompress reads locally (SSPACE needs uncompressed fastq)
    echo "📦 Decompressing reads..."
    if [[ ! -f "reads_R1.fq" ]]; then
        gunzip -c "$r1_in" > "reads_R1.fq"
    fi
    if [[ ! -f "reads_R2.fq" ]]; then
        gunzip -c "$r2_in" > "reads_R2.fq"
    fi

    # Prepare Contigs (Clean headers - SSPACE requires simple header names)
    echo "🧹 Cleaning headers..."
    cp "$contigs_in" "contigs.fa"
    sed -i 's/ .*//' "contigs.fa"

    # Create Library File
    printf "Lib${SAMPLE}\t${WORK_DIR}/reads_R1.fq\t${WORK_DIR}/reads_R2.fq\t${SSPACE_INSERT_SIZE}\t${SSPACE_INSERT_ERR}\tFR\n" > "library.txt"

    # Run SSPACE via Pixi
    echo "🧬 Running SSPACE..."
    pixi run -e sspace SSPACE_Basic.pl \
        -l "library.txt" \
        -s "contigs.fa" \
        -x 0 -m 32 -k 5 -a 0.7 \
        -b "${SAMPLE}_sspace" \
        -T "$CPUS_MAX"

    # Finalize
    sspace_result="${SAMPLE}_sspace.final.scaffolds.fasta"

    if [[ -f "$sspace_result" ]]; then
        echo "✅ SSPACE finished successfully."
        cp "$sspace_result" "$final_output"
        # Clean up large decompressed reads to save space
        rm -f "reads_R1.fq" "reads_R2.fq"
    else
        echo "❌ Error: SSPACE failed for $SAMPLE."
        cd "$ORIG_DIR"
        exit 1
    fi

    cd "$ORIG_DIR"
    echo "=== Finished $SAMPLE ==="
done < "$INPUT_SHEET"