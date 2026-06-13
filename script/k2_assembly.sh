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

mkdir -p "$RESULT_DIR/k2_as"
for i1 in "$RESULT_DIR/fastp"/*_1.fq.gz; do
    sample=$(basename "$i1" | cut -d "_" -f1)
    i2=${i1/_1.fq.gz/_2.fq.gz}
    echo "Processing sample: $sample"
    # Run Kraken2
    pixi run -e tree kraken2 \
        --db "$KRAKEN2_DB_PATH" \
        --threads 20 \
        --report "$RESULT_DIR/k2_as/${sample}.report.txt" \
        --output "$RESULT_DIR/k2_as/${sample}.kraken.txt" \
        --minimum-base-quality 20 \
        --confidence 0.1 \
        "$RESULT_DIR/megahit/${sample}_assembly/final.contigs.fa"
    echo "Finished sample: $sample"
done
