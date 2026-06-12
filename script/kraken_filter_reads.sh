#!/bin/bash
# ==============================================================================
# Script: kraken_filter_reads.sh
# Purpose: Classifies reads using Kraken2, extracts reads belonging to a specific
#          taxonomic ID (and its children), and registers them as a new sample
#          in the samples sheet for target assembly.
# ==============================================================================

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

# Helper for usage
usage() {
    echo "Usage: $0 -s <source_sample> -t <taxon_id> -o <output_sample_name> [-g <genus>] [-c <species>] [-p]"
    echo "  -s: Source sample name (must exist in samples.tsv)"
    echo "  -t: Taxonomic ID to filter for (e.g. 1392 for Bacillus)"
    echo "  -o: Name of the new filtered sample to create"
    echo "  -g: (Optional) Genus name for the new sample entry (default: Unknown)"
    echo "  -c: (Optional) Species name for the new sample entry (default: sp.)"
    echo "  -p: (Optional) Include parent taxonomic levels (e.g. genus reads for a species ID)"
    exit 1
}

SRC_SAMPLE=""
TAXID=""
OUT_SAMPLE=""
GENUS="Unknown"
SPECIES="sp."
INCLUDE_PARENTS="false"

# Parse arguments
while getopts "s:t:o:g:c:p" opt; do
    case "$opt" in
        s) SRC_SAMPLE="$OPTARG" ;;
        t) TAXID="$OPTARG" ;;
        o) OUT_SAMPLE="$OPTARG" ;;
        g) GENUS="$OPTARG" ;;
        c) SPECIES="$OPTARG" ;;
        p) INCLUDE_PARENTS="true" ;;
        *) usage ;;
    esac
done

if [[ -z "$SRC_SAMPLE" || -z "$TAXID" || -z "$OUT_SAMPLE" ]]; then
    usage
fi

echo "======================================================="
echo "Filtering reads for Specific Species Assembly"
echo "Source Sample:      $SRC_SAMPLE"
echo "Target Taxon ID:    $TAXID"
echo "New Sample Name:    $OUT_SAMPLE"
echo "Expected Taxonomy:  $GENUS $SPECIES"
echo "======================================================="

# --- Step 1: Find Input Reads ---
R1_IN=""
R2_IN=""

# Try Bowtie2 host-filtered reads first (highly clean input)
BT2_R1="$RESULT_DIR/bowtie2/nohuman.${SRC_SAMPLE}.fq.1.gz"
BT2_R2="$RESULT_DIR/bowtie2/nohuman.${SRC_SAMPLE}.fq.2.gz"

if [[ -f "$BT2_R1" && -f "$BT2_R2" ]]; then
    echo "Found Bowtie2 host-filtered reads for $SRC_SAMPLE. Using as input."
    R1_IN="$BT2_R1"
    R2_IN="$BT2_R2"
else
    # Fallback: search in samples.tsv
    echo "Bowtie2 reads not found. Searching raw reads in samples.tsv..."
    while IFS=$'\t' read -r name r1 r2 gen spec; do
        if [[ "$name" == "$SRC_SAMPLE" ]]; then
            R1_IN="$r1"
            R2_IN="$r2"
            break
        fi
    done < "$WORKDIR/samples.tsv"
fi

if [[ -z "$R1_IN" || ! -f "$R1_IN" ]]; then
    echo "ERROR: Input reads for sample '$SRC_SAMPLE' not found or do not exist."
    exit 1
fi

# --- Step 2: Run Kraken2 (if not already done) ---
KRAKEN_REPORT="$RESULT_DIR/k2/${SRC_SAMPLE}.report.txt"
KRAKEN_OUT="$RESULT_DIR/k2/${SRC_SAMPLE}.kraken.txt"

if [[ ! -f "$KRAKEN_OUT" || ! -f "$KRAKEN_REPORT" ]]; then
    echo "Running Kraken2 classification on $SRC_SAMPLE..."
    mkdir -p "$RESULT_DIR/k2"
    pixi run -e tree kraken2 \
        --db "$KRAKEN2_DB_PATH" \
        --paired "$R1_IN" "$R2_IN" \
        --threads "$CPUS_MED" \
        --report "$KRAKEN_REPORT" \
        --output "$KRAKEN_OUT" \
        --minimum-base-quality "$KRAKEN2_MIN_QUAL" \
        --gzip-compressed \
        --confidence "$KRAKEN2_CONFIDENCE"
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Kraken2 classification failed."
        exit 1
    fi
else
    echo "Found existing Kraken2 classification data."
fi

# --- Step 3: Extract Specific Reads ---
OUT_R1_RAW="$WORKDIR/data/${OUT_SAMPLE}_R1.fastq"
OUT_R2_RAW="$WORKDIR/data/${OUT_SAMPLE}_R2.fastq"
OUT_R1_GZ="$WORKDIR/data/${OUT_SAMPLE}_R1.fastq.gz"
OUT_R2_GZ="$WORKDIR/data/${OUT_SAMPLE}_R2.fastq.gz"

PARENTS_FLAG=""
if [[ "$INCLUDE_PARENTS" == "true" ]]; then
    echo "Extracting reads matching taxon ID $TAXID (including children and parents)..."
    PARENTS_FLAG="--include-parents"
else
    echo "Extracting reads matching taxon ID $TAXID (including children, excluding parents)..."
fi
rm -f "$OUT_R1_RAW" "$OUT_R2_RAW" "$OUT_R1_GZ" "$OUT_R2_GZ"

pixi run -e tree extract_kraken_reads.py \
    -k "$KRAKEN_OUT" \
    -r "$KRAKEN_REPORT" \
    -s "$R1_IN" \
    -s2 "$R2_IN" \
    -o "$OUT_R1_RAW" \
    -o2 "$OUT_R2_RAW" \
    -t "$TAXID" \
    --include-children \
    $PARENTS_FLAG \
    --fastq-output

if [[ $? -ne 0 || ! -s "$OUT_R1_RAW" ]]; then
    echo "ERROR: Read extraction failed or no reads matched the taxon ID."
    rm -f "$OUT_R1_RAW" "$OUT_R2_RAW"
    exit 1
fi

# --- Step 4: Compress Extracted Reads ---
echo "Compressing extracted reads..."
pixi run -e default pigz -p "$CPUS_MED" "$OUT_R1_RAW"
pixi run -e default pigz -p "$CPUS_MED" "$OUT_R2_RAW"

if [[ ! -f "$OUT_R1_GZ" ]]; then
    echo "ERROR: Compression failed."
    exit 1
fi

# --- Step 5: Register New Sample in samples.tsv ---
# Remove if already exists to prevent duplication
if grep -q "^${OUT_SAMPLE}[[:space:]]" "$WORKDIR/samples.tsv"; then
    echo "Warning: Sample '$OUT_SAMPLE' is already registered. Overwriting registration."
    sed -i "/^${OUT_SAMPLE}[[:space:]]/d" "$WORKDIR/samples.tsv"
fi

# Append new entry
echo -e "${OUT_SAMPLE}\t${OUT_R1_GZ}\t${OUT_R2_GZ}\t${GENUS}\t${SPECIES}" >> "$WORKDIR/samples.tsv"

echo "======================================================="
echo "SUCCESS! Extracted reads for Taxon ID $TAXID."
echo "New Sample registered: $OUT_SAMPLE"
echo "Registered path R1:    $OUT_R1_GZ"
echo "Registered path R2:    $OUT_R2_GZ"
echo ""
echo "To assemble and process this specific organism, run:"
echo "  pixi run run-pipeline-local-upstream"
echo "======================================================="
chmod +x "$0"
