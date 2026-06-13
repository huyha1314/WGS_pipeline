#!/bin/bash
#SBATCH --job-name=bwa_pilon
#SBATCH --output=./log/bwa_pilon_%j.out
#SBATCH --error=./log/bwa_pilon_%j.err
#SBATCH --ntasks=1
#SBATCH --mem=180G
#SBATCH --cpus-per-task=48

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

mkdir -p "$LOG_DIR" "$RESULT_DIR/bwa_pilon"

while IFS=$'\t' read -r SAMPLE R1_PATH R2_PATH; do
    if [[ "$SAMPLE" == "name" || -z "$SAMPLE" ]]; then
        continue
    fi

    echo "=== Running Pilon (Round 1) for sample: $SAMPLE ==="

    fq1="$RESULT_DIR/k2/clean.${SAMPLE}_1.fq.gz"
    fq2="$RESULT_DIR/k2/clean.${SAMPLE}_2.fq.gz"
    asm="$RESULT_DIR/assembly/${SAMPLE}_assembly/final.contigs.fa"
    workdir="$RESULT_DIR/bwa_pilon/${SAMPLE}"
    
    mkdir -p "$workdir"

    # --- Check for Final Output ---
    final_fasta="${workdir}/${SAMPLE}_pilon.fasta"
    if [[ "$RUN_POLISHING" != "true" ]]; then
        echo "Polishing is disabled (RUN_POLISHING=false). Forwarding raw assembly directly..."
        cp "$asm" "$final_fasta"
        continue
    fi

    if [[ -s "$final_fasta" ]]; then
        echo "--- Final Pilon file already exists, skipping $SAMPLE ---"
        continue
    fi

    # --- Check Inputs ---
    if [[ ! -f "$fq1" || ! -f "$fq2" ]]; then
        echo "Error: Reads for $SAMPLE not found in $RESULT_DIR/k2/. Skipping."
        continue
    fi
    if [[ ! -f "$asm" ]]; then
        echo "Error: Assembly for $SAMPLE not found at $asm. Skipping."
        continue
    fi

    # --- Step 1 & 2: Index and Align ---
    if [[ ! -s "${workdir}/${SAMPLE}.sorted.bam" ]]; then
        # 1. Indexing (BWA + Samtools FAI)
        if [[ ! -f "${asm}.bwt" || ! -f "${asm}.fai" ]]; then
            echo "--- Indexing Assembly for $SAMPLE ---"
            pixi run -e assembly bwa index "$asm"
            pixi run -e assembly samtools faidx "$asm"
        fi

        # 2. Alignment (BWA mem + Samtools sort)
        echo "--- Aligning reads for $SAMPLE ---"
        # Using 36 threads for bwa mem + 10 threads for samtools sort = 46 threads total
        pixi run -e assembly bwa mem -t 36 "$asm" "$fq1" "$fq2" | \
            pixi run -e assembly samtools sort -@ 10 -m 4G -o "${workdir}/${SAMPLE}.sorted.bam" -

        # 3. Index BAM
        echo "--- Indexing BAM for $SAMPLE ---"
        pixi run -e assembly samtools index "${workdir}/${SAMPLE}.sorted.bam"
    else
        echo "--- Found existing BAM for $SAMPLE ---"
    fi

    # --- Step 3: Pilon Polishing ---
    echo "--- Running Pilon for $SAMPLE ---"
    # Using 48 threads and setting heap memory to 160G (configured for 180G RAM node)
    pixi run -e assembly pilon \
        --genome "$asm" \
        --frags "${workdir}/${SAMPLE}.sorted.bam" \
        --output "${SAMPLE}_pilon" \
        --outdir "$workdir" \
        --vcf \
        --changes \
        --fix all \
        --threads "$CPUS_MAX" \
        -Xmx160G

    echo "=== Finished Pilon for sample: $SAMPLE ==="
done < "$INPUT_SHEET"

echo "=== All samples processed ==="