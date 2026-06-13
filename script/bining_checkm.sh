#!/bin/bash
#SBATCH --job-name=binning_checkm
#SBATCH --output=./log/binning_%j.out
#SBATCH --error=./log/binning_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=200G

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

POLISHED_DIR="${RESULT_DIR}/final_polished"  # Input from Pilon
READ_DIR="${RESULT_DIR}/k2"                   # Clean reads
OUT_DIR="${RESULT_DIR}/binning"

mkdir -p "$OUT_DIR" log

# Loop through polished assemblies
for assembly in ${POLISHED_DIR}/*/*_final_polished.fasta; do

    # 1. Setup names and folders
    filename=$(basename "$assembly")
    sample=$(echo "$filename" | sed 's/_final_polished.fasta//')
    
    echo "=== Processing Binning for Sample: $sample ==="

    WORK_DIR="${OUT_DIR}/${sample}"
    mkdir -p "$WORK_DIR"
    
    # Define Inputs/Outputs
    fq1="${READ_DIR}/clean.trim.${sample}_1.fq.gz"
    fq2="${READ_DIR}/clean.trim.${sample}_2.fq.gz"
    bam_file="${WORK_DIR}/${sample}.sorted.bam"
    depth_file="${WORK_DIR}/${sample}_depth.txt"
    bin_dir="${WORK_DIR}/bins"
    checkm_dir="${WORK_DIR}/checkm_stats"

    # --- Step 1: Mapping (Required for Metabat2 Coverage) ---
    if [[ ! -f "$bam_file" ]]; then
        echo "--> Mapping reads to polished assembly..."
        
        # Index assembly
        pixi run --manifest-path "$WORKDIR/pixi.toml" -e assembly bwa index "$assembly"
        
        # Map and Sort (30 threads map, 10 sort)
        pixi run --manifest-path "$WORKDIR/pixi.toml" -e assembly bwa mem -t 30 "$assembly" "$fq1" "$fq2" | \
            pixi run --manifest-path "$WORKDIR/pixi.toml" -e assembly samtools sort -@ 10 -m 4G -o "$bam_file" -
        
        pixi run --manifest-path "$WORKDIR/pixi.toml" -e assembly samtools index "$bam_file"
    else
        echo "--> BAM exists, skipping mapping."
    fi

    # --- Step 2: Metabat2 Binning ---
    if [[ ! -d "$bin_dir" || -z "$(ls -A $bin_dir)" ]]; then
        echo "--> Running Metabat2..."
        mkdir -p "$bin_dir"

        # Calculate coverage (jgi_summarize_bam_contig_depths comes with metabat2)
        pixi run --manifest-path "$WORKDIR/pixi.toml" -e taxonomy jgi_summarize_bam_contig_depths \
            --outputDepth "$depth_file" \
            "$bam_file"

        # Run Binning
        pixi run --manifest-path "$WORKDIR/pixi.toml" -e taxonomy metabat2 \
            -i "$assembly" \
            -a "$depth_file" \
            -o "${bin_dir}/${sample}_bin" \
            -t 40 \
            -m 1500 # Min contig size 1500bp
    else
        echo "--> Bins exist, skipping binning."
    fi

    # --- Step 3: CheckM Quality Control ---
    if [[ ! -f "${checkm_dir}/lineage.ms" ]]; then
        echo "--> Running CheckM..."
        
        # Set database path for CheckM
        if [[ -d "$CHECKM_DB_PATH" ]]; then
            pixi run --manifest-path "$WORKDIR/pixi.toml" -e taxonomy checkm data setRoot "$CHECKM_DB_PATH"
        fi

        # CheckM uses a lot of RAM. We reduce threads for the 'pplacer' step to avoid crashes.
        # -x fa: tells CheckM looking for files ending in .fa (Metabat output is .fa)
        pixi run --manifest-path "$WORKDIR/pixi.toml" -e taxonomy checkm lineage_wf \
            -t 40 \
            --pplacer_threads 4 \
            -x fa \
            "$bin_dir" \
            "$checkm_dir" \
            --file "${WORK_DIR}/${sample}_checkm_summary.txt"
    fi

    echo "=== Finished Sample $sample ==="
done