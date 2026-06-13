#!/bin/bash
#SBATCH --job-name=bbduk_pipeline
#SBATCH --output=./log/bbduk_%j.out
#SBATCH --error=./log/bbduk_%j.err
#SBATCH --ntasks=1
#SBATCH --mem=256G
#SBATCH --cpus-per-task=64

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

# Ensure log and output directories exist
mkdir -p "$LOG_DIR" "$RESULT_DIR/bbduk" "$RESULT_DIR/bowtie2" "$RESULT_DIR/k2"

process_qc_bt2() {
    local sample="$1"
    local r1_in="$2"
    local r2_in="$3"
    
    # Define outputs
    local trim_out1="$RESULT_DIR/bbduk/${sample}_1.fq.gz"
    local trim_out2="$RESULT_DIR/bbduk/${sample}_2.fq.gz"
    local bt2_out1="$RESULT_DIR/bowtie2/nohuman.${sample}.fq.1.gz"
    local bt2_out2="$RESULT_DIR/bowtie2/nohuman.${sample}.fq.2.gz"

    # --- Step 1: BBDuk quality filtering ---
    if [[ ! -f "$trim_out1" || ! -f "$trim_out2" ]] || ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e default gzip -t "$trim_out1" &>/dev/null || ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e default gzip -t "$trim_out2" &>/dev/null; then
        echo "[$sample] Running BBDuk (output missing or corrupted)..."
        rm -f "$trim_out1" "$trim_out2"
        if pixi run --manifest-path "$WORKDIR/pixi.toml" -e qc bbduk.sh \
            in1="$r1_in" \
            in2="$r2_in" \
            out1="$trim_out1" \
            out2="$trim_out2" \
            entropy="$BBDUK_ENTROPY" \
            entropywindow="$BBDUK_ENTROPY_WINDOW" \
            entropyk="$BBDUK_ENTROPY_K" \
            threads="$THREADS_PER_QC_BT2"; then
            echo "[$sample] BBDuk completed successfully."
        else
            echo "ERROR: BBDuk failed for $sample"
            rm -f "$trim_out1" "$trim_out2"
            return 1
        fi
    fi

    # --- Step 2: Remove human reads with Bowtie2 ---
    if [[ ! -f "$bt2_out1" || ! -f "$bt2_out2" ]] || ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e default gzip -t "$bt2_out1" &>/dev/null || ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e default gzip -t "$bt2_out2" &>/dev/null; then
        echo "[$sample] Running Bowtie2 to filter human reads (output missing or corrupted)..."
        rm -f "$bt2_out1" "$bt2_out2" "$RESULT_DIR/bowtie2/nohuman.${sample}.sam"
        if pixi run --manifest-path "$WORKDIR/pixi.toml" -e assembly bowtie2 \
            --threads "$THREADS_PER_QC_BT2" \
            -x "$BOWTIE2_INDEX" \
            -1 "$trim_out1" \
            -2 "$trim_out2" \
            --un-conc-gz "$RESULT_DIR/bowtie2/nohuman.${sample}.fq.gz" \
            -S "$RESULT_DIR/bowtie2/nohuman.${sample}.sam" &> "$RESULT_DIR/bowtie2/${sample}_bowtie2.log"; then
            rm -f "$RESULT_DIR/bowtie2/nohuman.${sample}.sam" # Clean large SAM file to save disk space
        else
            echo "ERROR: Bowtie2 failed for $sample"
            rm -f "$bt2_out1" "$bt2_out2" "$RESULT_DIR/bowtie2/nohuman.${sample}.sam"
            return 1
        fi
    fi
}

process_kraken() {
    local sample="$1"
    
    local bt2_out1="$RESULT_DIR/bowtie2/nohuman.${sample}.fq.1.gz"
    local bt2_out2="$RESULT_DIR/bowtie2/nohuman.${sample}.fq.2.gz"
    local final_out1="$RESULT_DIR/k2/clean.${sample}_1.fq.gz"
    local final_out2="$RESULT_DIR/k2/clean.${sample}_2.fq.gz"

    # --- Step 3: Extract & Clean Reads (Optimized) ---
    # Since Bowtie2 already filters out host (human) reads, running Kraken2 and extract_kraken_reads.py
    # to exclude human (taxid 9606) is completely redundant.
    # We bypass Kraken2 here to save massive memory (120GB+ RAM), CPU, and processing time.
    if [[ ! -f "$final_out1" || ! -f "$final_out2" ]] || ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e default gzip -t "$final_out1" &>/dev/null || ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e default gzip -t "$final_out2" &>/dev/null; then
        echo "[$sample] Creating clean reads directly from Bowtie2 output (bypassing redundant Kraken2 host-filtering)..."
        rm -f "$final_out1" "$final_out2"
        
        # Copy Bowtie2 output to final clean reads
        if cp "$bt2_out1" "$final_out1" && cp "$bt2_out2" "$final_out2"; then
            echo "[$sample] Clean reads created successfully."
        else
            echo "ERROR: Copying clean reads failed for $sample"
            rm -f "$final_out1" "$final_out2"
            return 1
        fi
    fi

    # NOTE: If you ever need to run full Kraken2 classification on raw reads and filter them,
    # you can uncomment the block below and comment out the optimized block above.
    
    local kraken_report="$RESULT_DIR/k2/${sample}.report.txt"
    local kraken_output="$RESULT_DIR/k2/${sample}.kraken.txt"
    local raw_out1="$RESULT_DIR/k2/clean.${sample}_1.fq"
    local raw_out2="$RESULT_DIR/k2/clean.${sample}_2.fq"
    
    if [[ ! -f "$kraken_output" || ! -f "$kraken_report" ]]; then
        echo "[$sample] Running Kraken2..."
        rm -f "$kraken_output" "$kraken_report"
        if pixi run --manifest-path "$WORKDIR/pixi.toml" -e tree kraken2 \
            --db "$KRAKEN2_DB_PATH" \
            --paired "$bt2_out1" "$bt2_out2" \
            --threads "$THREADS_PER_KRAKEN" \
            --report "$kraken_report" \
            --output "$kraken_output" \
            --minimum-base-quality "$KRAKEN2_MIN_QUAL" \
            --gzip-compressed \
            --confidence "$KRAKEN2_CONFIDENCE"; then
            echo "[$sample] Kraken2 completed successfully."
        else
            echo "ERROR: Kraken2 failed for $sample"
            rm -f "$kraken_output" "$kraken_report"
            return 1
        fi
    fi
    
    if [[ ! -f "$final_out1" || ! -f "$final_out2" ]]; then
        echo "[$sample] Extracting reads..."
        rm -f "$raw_out1" "$raw_out2" "$final_out1" "$final_out2"
        if pixi run --manifest-path "$WORKDIR/pixi.toml" -e tree extract_kraken_reads.py \
            -k "$kraken_output" \
            -r "$kraken_report" \
            -s "$bt2_out1" \
            -s2 "$bt2_out2" \
            -o "$raw_out1" \
            -o2 "$raw_out2" \
            -t 9606 --include-parents --exclude --fastq-output; then
            
            echo "[$sample] Compressing final reads..."
            if pixi run --manifest-path "$WORKDIR/pixi.toml" -e default pigz -p 8 -f "$raw_out1" && \
               pixi run --manifest-path "$WORKDIR/pixi.toml" -e default pigz -p 8 -f "$raw_out2"; then
                echo "[$sample] Read extraction and compression complete."
            else
                echo "ERROR: pigz compression failed for $sample"
                rm -f "$raw_out1" "$raw_out2" "$final_out1" "$final_out2"
                return 1
            fi
        else
            echo "ERROR: extract_kraken_reads.py failed for $sample"
            rm -f "$raw_out1" "$raw_out2" "$final_out1" "$final_out2"
            return 1
        fi
    fi
}

# Export variables and functions for GNU Parallel
export -f process_qc_bt2 process_kraken
export RESULT_DIR BBDUK_ENTROPY BBDUK_ENTROPY_WINDOW BBDUK_ENTROPY_K BOWTIE2_INDEX KRAKEN2_DB_PATH KRAKEN2_MIN_QUAL KRAKEN2_CONFIDENCE THREADS_PER_QC_BT2 THREADS_PER_KRAKEN

# Build parameter files for GNU Parallel
CMD_FILE_QC="$RESULT_DIR/bbduk/qc_commands.txt"
CMD_FILE_KRAKEN="$RESULT_DIR/bbduk/kraken_commands.txt"
> "$CMD_FILE_QC"
> "$CMD_FILE_KRAKEN"

while IFS=$'\t' read -r SAMPLE R1_PATH R2_PATH GENUS SPECIES; do
    if [[ "$SAMPLE" == "name" || -z "$SAMPLE" ]]; then
        continue
    fi
    
    FASTP_R1="$RESULT_DIR/fastp/trim.${SAMPLE}_1.fq.gz"
    FASTP_R2="$RESULT_DIR/fastp/trim.${SAMPLE}_2.fq.gz"
    
    # Check if fastp inputs exist
    if [[ -s "$FASTP_R1" && -s "$FASTP_R2" ]]; then
        echo "process_qc_bt2 \"$SAMPLE\" \"$FASTP_R1\" \"$FASTP_R2\"" >> "$CMD_FILE_QC"
        echo "process_kraken \"$SAMPLE\"" >> "$CMD_FILE_KRAKEN"
    else
        echo "WARNING: Fastp output not found for $SAMPLE. Skipping."
    fi
done < "$INPUT_SHEET"

# --- Run Stage 1 (QC & BT2) in parallel ---
if [[ -s "$CMD_FILE_QC" ]]; then
    echo "Running parallel processing for bbduk and bowtie2 (Jobs: $PARALLEL_JOBS_QC_BT2)..."
    cat "$CMD_FILE_QC" | pixi run --manifest-path "$WORKDIR/pixi.toml" parallel -j "$PARALLEL_JOBS_QC_BT2"
else
    echo "No QC/BT2 commands to run."
fi

# --- Run Stage 2 (Kraken2 & Extraction) sequentially or with limited concurrency ---
if [[ -s "$CMD_FILE_KRAKEN" ]]; then
    echo "Running parallel processing for kraken2 (Jobs: $PARALLEL_JOBS_KRAKEN)..."
    cat "$CMD_FILE_KRAKEN" | pixi run --manifest-path "$WORKDIR/pixi.toml" parallel -j "$PARALLEL_JOBS_KRAKEN"
else
    echo "No Kraken2 commands to run."
fi

echo "All bbduk, bowtie2, kraken2 processing complete."