#!/bin/bash
#SBATCH --job-name=post_sspace_pilon
#SBATCH --output=log/pilon_round2_%j.out
#SBATCH --error=log/pilon_round2_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=250G

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

mkdir -p "$LOG_DIR" "$RESULT_DIR/final_polished"

while IFS=$'\t' read -r SAMPLE R1_PATH R2_PATH; do
    if [[ "$SAMPLE" == "name" || -z "$SAMPLE" ]]; then
        continue
    fi

    echo "=== Running Pilon (Round 2) for Sample: $SAMPLE ==="

    scaffold_in="$RESULT_DIR/sspaces/${SAMPLE}_scaffold/${SAMPLE}_sspace.final.scaffolds.fasta"
    workdir="$RESULT_DIR/final_polished/${SAMPLE}"
    mkdir -p "$workdir"
    
    # Check if this sample is already finished
    final_polished_out="${workdir}/${SAMPLE}_final_polished.fasta"
    if [[ "$RUN_POLISHING" != "true" ]]; then
        echo "Polishing (Round 2) is disabled (RUN_POLISHING=false). Forwarding scaffolds directly..."
        cp "$scaffold_in" "$final_polished_out"
        continue
    fi

    if [[ -s "$final_polished_out" ]]; then
        echo "--- Polished file exists for $SAMPLE. Skipping. ---"
        continue
    fi

    # Read inputs (Clean reads from Step 2)
    fq1="$RESULT_DIR/k2/clean.${SAMPLE}_1.fq.gz"
    fq2="$RESULT_DIR/k2/clean.${SAMPLE}_2.fq.gz"

    # Verify inputs exist
    if [[ ! -f "$fq1" || ! -f "$fq2" ]]; then
        echo "Error: Clean reads for $SAMPLE not found in $RESULT_DIR/k2/. Skipping."
        continue
    fi
    if [[ ! -f "$scaffold_in" ]]; then
        echo "Error: SSPACE scaffold for $SAMPLE not found at $scaffold_in. Skipping."
        continue
    fi

    # Index the scaffolds (if missing)
    if [[ ! -f "${scaffold_in}.bwt" ]]; then
        echo "--- Indexing Scaffolds for $SAMPLE ---"
        pixi run -e assembly bwa index "$scaffold_in"
        pixi run -e assembly samtools faidx "$scaffold_in"
    fi

    # Align reads to scaffolds
    echo "--- Aligning reads to scaffolds for $SAMPLE ---"
    # Using 30 threads for BWA mem + 10 threads for samtools sort = 40 CPUs total
    pixi run -e assembly bwa mem -t 30 "$scaffold_in" "$fq1" "$fq2" | \
        pixi run -e assembly samtools sort -@ 10 -m 4G -o "${workdir}/${SAMPLE}_scaffold.sorted.bam" -
    
    pixi run -e assembly samtools index "${workdir}/${SAMPLE}_scaffold.sorted.bam"

    # Run Pilon (Round 2)
    echo "--- Running Pilon Round 2 for $SAMPLE ---"
    # Set heap memory to 200G (configured for 250G RAM node)
    pixi run -e assembly pilon \
        --genome "$scaffold_in" \
        --frags "${workdir}/${SAMPLE}_scaffold.sorted.bam" \
        --output "${SAMPLE}_final_polished" \
        --outdir "$workdir" \
        --fix all \
        --changes \
        --threads "$CPUS_MED" \
        -Xmx200G

    # Cleanup temporary BAM files to save space
    rm -f "${workdir}/${SAMPLE}_scaffold.sorted.bam" "${workdir}/${SAMPLE}_scaffold.sorted.bam.bai"

    echo "=== Finished Round 2 for Sample $SAMPLE ==="
done < "$INPUT_SHEET"