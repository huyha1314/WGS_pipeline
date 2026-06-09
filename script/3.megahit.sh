#!/bin/bash
#SBATCH --job-name=megahit
#SBATCH --output=./log/megahit_%j.out
#SBATCH --error=./log/megahit_%j.err
#SBATCH --ntasks=1
#SBATCH --mem=164G
#SBATCH --cpus-per-task=48

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

mkdir -p "$LOG_DIR" "$RESULT_DIR/megahit"

while IFS=$'\t' read -r SAMPLE R1_PATH R2_PATH; do
    if [[ "$SAMPLE" == "name" || -z "$SAMPLE" ]]; then
        continue
    fi

    # Inputs from Step 2 (Kraken/Bowtie clean reads)
    in1="$RESULT_DIR/k2/clean.${SAMPLE}_1.fq.gz"
    in2="$RESULT_DIR/k2/clean.${SAMPLE}_2.fq.gz"
    outdir="$RESULT_DIR/megahit/${SAMPLE}_assembly"

    # --- SAFETY CHECK 1: Ensure Input Files Exist ---
    if [[ ! -f "$in1" || ! -f "$in2" ]]; then
        echo "Warning: Input files for $SAMPLE not found in $RESULT_DIR/k2/. Skipping."
        continue
    fi

    # --- SAFETY CHECK 2: Skip if Assembly Already Finished ---
    if [[ -f "$outdir/final.contigs.fa" ]]; then
        echo "Skipping $SAMPLE (Assembly already exists)"
        continue
    fi

    # --- SAFETY CHECK 3: Clean Partial Runs ---
    if [[ -d "$outdir" ]]; then
        echo "Removing partial run for $SAMPLE"
        rm -rf "$outdir"
    fi

    echo "Running MEGAHIT for sample: $SAMPLE"

    # Temporary uncompressed FASTQ files to bypass Megahit's background named pipe decompression bugs
    temp_fq1="$RESULT_DIR/megahit/temp.${SAMPLE}_1.fq"
    temp_fq2="$RESULT_DIR/megahit/temp.${SAMPLE}_2.fq"

    echo "[$SAMPLE] Decompressing reads for MEGAHIT..."
    rm -f "$temp_fq1" "$temp_fq2"
    if pixi run -e default pigz -d -c "$in1" > "$temp_fq1" && \
       pixi run -e default pigz -d -c "$in2" > "$temp_fq2"; then
        
        echo "[$SAMPLE] Decompression complete. Launching MEGAHIT..."
        if pixi run -e assembly megahit \
            -1 "$temp_fq1" \
            -2 "$temp_fq2" \
            -o "$outdir" \
            --num-cpu-threads "$CPUS_MED" \
            --memory "$MEGAHIT_MEM_FRACTION" \
            --min-contig-len "$MEGAHIT_MIN_CONTIG_LEN" \
            --k-list "$MEGAHIT_K_LIST" &> "$RESULT_DIR/megahit/${SAMPLE}.megahit.log"; then
            echo "Finished sample: $SAMPLE"
        else
            echo "ERROR: MEGAHIT failed for sample: $SAMPLE"
            rm -f "$temp_fq1" "$temp_fq2"
            exit 1
        fi
        rm -f "$temp_fq1" "$temp_fq2"
    else
        echo "ERROR: Decompressing reads failed for sample: $SAMPLE"
        rm -f "$temp_fq1" "$temp_fq2"
        exit 1
    fi
done < "$INPUT_SHEET"