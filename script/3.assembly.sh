#!/bin/bash
#SBATCH --job-name=assembly
#SBATCH --output=./log/assembly_%j.out
#SBATCH --error=./log/assembly_%j.err
#SBATCH --ntasks=1
#SBATCH --mem=164G
#SBATCH --cpus-per-task=48

# --- Load Central Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

# Default assembler if not set
ASSEMBLER="${ASSEMBLER:-spades}"

echo "====================================================="
echo "        GENOME ASSEMBLY - ASSEMBLER: $ASSEMBLER      "
echo "====================================================="

mkdir -p "$LOG_DIR" "$RESULT_DIR/assembly"

while IFS=$'\t' read -r SAMPLE R1_PATH R2_PATH; do
    if [[ "$SAMPLE" == "name" || -z "$SAMPLE" ]]; then
        continue
    fi

    # Inputs from Step 2 (Kraken/Bowtie clean reads)
    in1="$RESULT_DIR/k2/clean.${SAMPLE}_1.fq.gz"
    in2="$RESULT_DIR/k2/clean.${SAMPLE}_2.fq.gz"
    outdir="$RESULT_DIR/assembly/${SAMPLE}_assembly"

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
        echo "Removing partial run directory for $SAMPLE"
        rm -rf "$outdir"
    fi
    mkdir -p "$outdir"

    echo "Running $ASSEMBLER for sample: $SAMPLE"

    if [[ "$ASSEMBLER" == "megahit" ]]; then
        # Temporary uncompressed FASTQ files to bypass Megahit's background named pipe decompression bugs
        temp_fq1="$RESULT_DIR/assembly/temp.${SAMPLE}_1.fq"
        temp_fq2="$RESULT_DIR/assembly/temp.${SAMPLE}_2.fq"

        echo "[$SAMPLE] Decompressing reads for MEGAHIT..."
        rm -f "$temp_fq1" "$temp_fq2"
        if pixi run --manifest-path "$WORKDIR/pixi.toml" -e default pigz -d -c "$in1" > "$temp_fq1" && \
           pixi run --manifest-path "$WORKDIR/pixi.toml" -e default pigz -d -c "$in2" > "$temp_fq2"; then
            
            echo "[$SAMPLE] Decompression complete. Launching MEGAHIT..."
            if pixi run --manifest-path "$WORKDIR/pixi.toml" -e assembly megahit \
                -1 "$temp_fq1" \
                -2 "$temp_fq2" \
                -o "$outdir/megahit_out" \
                --num-cpu-threads "$CPUS_MED" \
                --memory "$MEGAHIT_MEM_FRACTION" \
                --min-contig-len "$MEGAHIT_MIN_CONTIG_LEN" \
                --k-list "$MEGAHIT_K_LIST" &> "$RESULT_DIR/assembly/${SAMPLE}.megahit.log"; then
                
                # Copy Megahit final contigs to standard output path
                cp "$outdir/megahit_out/final.contigs.fa" "$outdir/final.contigs.fa"
                echo "Finished Megahit assembly for sample: $SAMPLE"
            else
                echo "ERROR: MEGAHIT failed for sample: $SAMPLE"
                rm -f "$temp_fq1" "$temp_fq2"
                exit 1
            fi
            rm -f "$temp_fq1" "$temp_fq2"
            rm -rf "$outdir/megahit_out"
        else
            echo "ERROR: Decompressing reads failed for sample: $SAMPLE"
            rm -f "$temp_fq1" "$temp_fq2"
            exit 1
        fi

    elif [[ "$ASSEMBLER" == "spades" ]]; then
        echo "[$SAMPLE] Launching SPAdes..."
        if pixi run --manifest-path "$WORKDIR/pixi.toml" -e assembly spades.py \
            -1 "$in1" \
            -2 "$in2" \
            -o "$outdir/spades_out" \
            --threads "$CPUS_MED" \
            --memory 250 &> "$RESULT_DIR/assembly/${SAMPLE}.spades.log"; then
            
            # Use scaffolds.fasta as the standard contigs file for downstream
            cp "$outdir/spades_out/scaffolds.fasta" "$outdir/final.contigs.fa"
            echo "Finished SPAdes assembly for sample: $SAMPLE"
        else
            echo "ERROR: SPAdes failed for sample: $SAMPLE"
            exit 1
        fi
        rm -rf "$outdir/spades_out"

    elif [[ "$ASSEMBLER" == "flye" ]]; then
        echo "[$SAMPLE] Launching Flye..."
        # Flye is a long-read assembler. As a fallback, we assume clean.fq.gz contains reads.
        if pixi run --manifest-path "$WORKDIR/pixi.toml" -e assembly flye \
            --nano-hq "$in1" \
            -o "$outdir/flye_out" \
            -t "$CPUS_MED" &> "$RESULT_DIR/assembly/${SAMPLE}.flye.log"; then
            
            cp "$outdir/flye_out/assembly.fasta" "$outdir/final.contigs.fa"
            echo "Finished Flye assembly for sample: $SAMPLE"
        else
            echo "ERROR: Flye failed for sample: $SAMPLE"
            exit 1
        fi
        rm -rf "$outdir/flye_out"

    else
        echo "ERROR: Unknown assembler '$ASSEMBLER'. Supported: megahit, spades, flye."
        exit 1
    fi
done < "$INPUT_SHEET"
