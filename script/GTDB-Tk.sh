#!/bin/bash
#SBATCH --job-name=gtdbtk_class
#SBATCH --output=./log/gtdb_%j.out
#SBATCH --error=./log/gtdb_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=300G 

# Load Central Configuration
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

BINNING_DIR="${RESULT_DIR}/binning"
GTDB_OUT_DIR="${RESULT_DIR}/gtdbtk"
GOOD_BINS_DIR="${RESULT_DIR}/good_bins_collection"

mkdir -p "$GTDB_OUT_DIR" "$GOOD_BINS_DIR"

echo "Gathering bins from all samples..."

for sample_dir in ${BINNING_DIR}/*; do
    sample=$(basename "$sample_dir")
    
    # Check if bins directory exists
    if [[ -d "${sample_dir}/bins" ]]; then
        # Copy bins to the collection folder
        # We rename them to ensure uniqueness: sample_bin.1.fa
        for bin in ${sample_dir}/bins/*.fa; do
            bin_name=$(basename "$bin")
            cp "$bin" "${GOOD_BINS_DIR}/${sample}_${bin_name}"
        done
    fi
done

echo "Total bins collected: $(ls $GOOD_BINS_DIR | wc -l)"

# --- Step 2: Run GTDB-Tk ---
echo "Running GTDB-Tk Classify Workflow..."

pixi run -e taxonomy gtdbtk classify_wf \
    --genome_dir "$GOOD_BINS_DIR" \
    --out_dir "$GTDB_OUT_DIR" \
    --extension fa \
    --cpus 40 \
    --min_perc_aa "$GTDBTK_MIN_PERC_AA"

echo "GTDB-Tk Finished."