#!/bin/bash
# ==============================================================================
#                 PRECISIONGENE WGS PIPELINE - MAGPURIFY BIN REFINEMENT
# ==============================================================================
# This script runs the MAGpurify pipeline on the collected assemblies to 
# automatically flag and remove taxonomic, GC, and tetranucleotide contaminants.

# Sbatch options for cluster runs if needed
#SBATCH --job-name=MAGpurify
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=log/slurm_logs/magpurify_%j.log

# --- Load Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

COLLECTED_DIR="$RESULT_DIR/collected_assemblies"
REFINED_DIR="$RESULT_DIR/refined_assemblies"

mkdir -p "$REFINED_DIR"

echo "====================================================="
echo "         MAGPURIFY AUTOMATED BIN REFINEMENT          "
echo "====================================================="
echo "Database Directory: $MAGPURIFYDB"
echo "Input Directory:    $COLLECTED_DIR"
echo "Output Directory:   $REFINED_DIR"
echo "====================================================="

# Check database
if [[ ! -d "$MAGPURIFYDB" || ! -d "$MAGPURIFYDB/clade-markers" ]]; then
    echo "ERROR: MAGpurify database not found at $MAGPURIFYDB."
    echo "Please run 'pixi run --manifest-path "$WORKDIR/pixi.toml" download-db-magpurify' first."
    exit 1
fi

export MAGPURIFYDB="$MAGPURIFYDB"

# Loop over all genomes in the collection
for mag_path in "$COLLECTED_DIR"/*.fasta; do
    [ -e "$mag_path" ] || continue
    mag_name=$(basename "$mag_path" .fasta)
    
    # Skip already backed up original files or already cleaned files
    if [[ "$mag_name" == *"_original" ]]; then
        continue
    fi
    
    echo "Processing Bin: $mag_name..."
    tmp_out_dir="$REFINED_DIR/${mag_name}_magpurify_tmp"
    mkdir -p "$tmp_out_dir"
    
    # 1. Flag contigs with conflicting phylogenetic marker genes
    echo " -> Running phylo-markers..."
    pixi run --manifest-path "$WORKDIR/pixi.toml" -e magpurify magpurify phylo-markers "$mag_path" "$tmp_out_dir"
    if [ $? -ne 0 ]; then
        echo "ERROR: MAGpurify phylo-markers failed on $mag_name!"
        exit 1
    fi
    
    # 2. Flag contigs with conflicting clade-specific markers
    echo " -> Running clade-markers..."
    pixi run --manifest-path "$WORKDIR/pixi.toml" -e magpurify magpurify clade-markers "$mag_path" "$tmp_out_dir"
    if [ $? -ne 0 ]; then
        echo "ERROR: MAGpurify clade-markers failed on $mag_name!"
        exit 1
    fi
    
    # 3. Flag contigs with weird tetranucleotide frequencies
    echo " -> Running tetra-freq..."
    pixi run --manifest-path "$WORKDIR/pixi.toml" -e magpurify magpurify tetra-freq "$mag_path" "$tmp_out_dir"
    if [ $? -ne 0 ]; then
        echo "ERROR: MAGpurify tetra-freq failed on $mag_name!"
        exit 1
    fi
    
    # 4. Flag contigs with outlier GC content
    echo " -> Running gc-content..."
    pixi run --manifest-path "$WORKDIR/pixi.toml" -e magpurify magpurify gc-content "$mag_path" "$tmp_out_dir"
    if [ $? -ne 0 ]; then
        echo "ERROR: MAGpurify gc-content failed on $mag_name!"
        exit 1
    fi
    
    # 5. Flag known contaminants
    echo " -> Running known-contam..."
    pixi run --manifest-path "$WORKDIR/pixi.toml" -e magpurify magpurify known-contam "$mag_path" "$tmp_out_dir"
    if [ $? -ne 0 ]; then
        echo "ERROR: MAGpurify known-contam failed on $mag_name!"
        exit 1
    fi
    
    # Clean output FASTA
    cleaned_path="$REFINED_DIR/${mag_name}_cleaned.fasta"
    echo " -> Generating cleaned bin: $cleaned_path..."
    pixi run --manifest-path "$WORKDIR/pixi.toml" -e magpurify magpurify clean-bin "$mag_path" "$tmp_out_dir" "$cleaned_path"
    if [ $? -ne 0 ]; then
        echo "ERROR: MAGpurify clean-bin failed on $mag_name!"
        exit 1
    fi
    
    # Cleanup temp dir
    rm -rf "$tmp_out_dir"
    
    # Back up the original file
    backup_path="$COLLECTED_DIR/${mag_name}_original.fasta.bak"
    if [ ! -f "$backup_path" ]; then
        echo " -> Backing up original assembly to $backup_path"
        cp "$mag_path" "$backup_path"
    fi
    
    # Replace the collected assembly with the cleaned version
    echo " -> Overwriting original collected assembly with cleaned version..."
    cp "$cleaned_path" "$mag_path"
    
    echo "Finished processing $mag_name."
    echo "-----------------------------------------------------"
done

# Clean up downstream results of contaminated genomes to force re-running on cleaned versions
echo " -> Clearing old downstream directories of contaminated genomes..."
rm -rf "$RESULT_DIR/annotation"
rm -rf "$RESULT_DIR/eggnog"
rm -rf "$RESULT_DIR/busco"
rm -rf "$RESULT_DIR/genomad"
rm -rf "$RESULT_DIR/tree"
rm -rf "$RESULT_DIR/rp"
rm -rf "$RESULT_DIR/checkm_cleaned"
rm -rf "$RESULT_DIR/gtdbtk_cleaned"

touch "$REFINED_DIR/magpurify_success.flag"
echo "MAGpurify refinement step completed successfully!"
echo "====================================================="
