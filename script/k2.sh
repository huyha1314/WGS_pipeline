#!/bin/bash
#SBATCH --job-name=k2_pipeline
#SBATCH --output=./log/k2_%j.out
#SBATCH --error=./log/k2_%j.err
#SBATCH --ntasks=1
#SBATCH --mem=164G
#SBATCH --cpus-per-task=20

# Load Central Configuration
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

mkdir -p "$RESULT_DIR/k2"
for i1 in "$RESULT_DIR/fastp"/*_1.fq.gz; do
    sample=$(basename "$i1" | cut -d "_" -f1)
    i2=${i1/_1.fq.gz/_2.fq.gz}
    if [[ -s "$RESULT_DIR/k2/${sample}.report.txt" ]]; then 
        echo "Skipping ${sample}"
        continue
    fi
    echo "Processing sample: $sample"
    
    # --- Step 4: Extract reads of interest from Kraken2 report ---
    pixi run --manifest-path "$WORKDIR/pixi.toml" -e tree extract_kraken_reads.py \
        -r "$RESULT_DIR/k2/${sample}.report.txt" \
        -k "$RESULT_DIR/k2/${sample}.kraken.txt" \
        -s "$RESULT_DIR/bowtie2/nohuman.${sample}.fq.1.gz" \
        -s2 "$RESULT_DIR/bowtie2/nohuman.${sample}.fq.2.gz" \
        -o "$RESULT_DIR/k2/extract_${sample}_1.fq" \
        -o2 "$RESULT_DIR/k2/extract_${sample}_2.fq" \
        -t 5073 --include-children --fastq-output 

    cat "$RESULT_DIR/k2/uncl.clean.${sample}_1.fq" > "$RESULT_DIR/k2/clean.${sample}_1.fq" 
    cat "$RESULT_DIR/k2/uncl.clean.${sample}_2.fq" > "$RESULT_DIR/k2/clean.${sample}_2.fq"
    cat "$RESULT_DIR/k2/extract_${sample}_1.fq" >> "$RESULT_DIR/k2/clean.${sample}_1.fq" 
    cat "$RESULT_DIR/k2/extract_${sample}_2.fq" >> "$RESULT_DIR/k2/clean.${sample}_2.fq"

    pigz -p 20 "$RESULT_DIR/k2/clean.${sample}_1.fq" 
    pigz -p 20 "$RESULT_DIR/k2/clean.${sample}_2.fq"

    echo "Finished sample: $sample"
done
