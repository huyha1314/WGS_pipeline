#!/bin/bash
#SBATCH --job-name=metabat2_binning
#SBATCH --output=log/metabat2_%j.out
#SBATCH --error=log/metabat2_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=56
#SBATCH --mem=256G

# --- Load Central Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

POLISHED_DIR="${RESULT_DIR}/final_polished"
READ_DIR="${RESULT_DIR}/k2"
BINNING_DIR="${RESULT_DIR}/binning"
BINNED_DIR="${RESULT_DIR}/binned_assemblies"

mkdir -p "$BINNING_DIR" "$BINNED_DIR" "$LOG_DIR"

echo "====================================================="
echo "        METABAT2 AUTOMATED METAGENOME BINNING        "
echo "====================================================="
echo "Input Polished Assemblies: $POLISHED_DIR"
echo "Reads Directory:           $READ_DIR"
echo "Output Directory:          $BINNING_DIR"
echo "Binned Assemblies Dir:     $BINNED_DIR"
echo "====================================================="

# Loop through samples in the samples sheet
while IFS=$'\t' read -r SAMPLE R1_PATH R2_PATH GENUS SPECIES; do
    if [[ "$SAMPLE" == "name" || -z "$SAMPLE" ]]; then
        continue
    fi

    echo "=== Processing Binning for Sample: $SAMPLE ==="

    assembly="${POLISHED_DIR}/${SAMPLE}/${SAMPLE}_final_polished.fasta"
    if [[ ! -f "$assembly" ]]; then
        echo "Warning: Polished assembly for $SAMPLE not found at $assembly. Skipping."
        continue
    fi

    WORK_DIR="${BINNING_DIR}/${SAMPLE}"
    mkdir -p "$WORK_DIR"
    
    # Define Inputs/Outputs
    fq1="${READ_DIR}/clean.${SAMPLE}_1.fq.gz"
    fq2="${READ_DIR}/clean.${SAMPLE}_2.fq.gz"
    bam_file="${WORK_DIR}/${SAMPLE}.sorted.bam"
    depth_file="${WORK_DIR}/${SAMPLE}_depth.txt"
    bin_dir="${WORK_DIR}/bins"

    # --- Step 1: Mapping (Required for Metabat2 Coverage) ---
    if [[ ! -f "$bam_file" ]]; then
        echo "--> Mapping reads to polished assembly..."
        
        # Index assembly
        pixi run --manifest-path "$WORKDIR/pixi.toml" -e assembly bwa index "$assembly"
        
        # Map and Sort (using CPUS_MED for mem, CPUS_MIN for sort)
        pixi run --manifest-path "$WORKDIR/pixi.toml" -e assembly bwa mem -t "$CPUS_MED" "$assembly" "$fq1" "$fq2" | \
            pixi run --manifest-path "$WORKDIR/pixi.toml" -e assembly samtools sort -@ "$CPUS_MIN" -m 4G -o "$bam_file" -
        
        pixi run --manifest-path "$WORKDIR/pixi.toml" -e assembly samtools index "$bam_file"
    else
        echo "--> BAM exists, skipping mapping."
    fi

    # --- Step 2: Metabat2 Binning ---
    if [[ ! -d "$bin_dir" || -z "$(ls -A "$bin_dir" 2>/dev/null)" ]]; then
        echo "--> Running Metabat2..."
        mkdir -p "$bin_dir"

        # Calculate coverage
        pixi run --manifest-path "$WORKDIR/pixi.toml" -e taxonomy jgi_summarize_bam_contig_depths \
            --outputDepth "$depth_file" \
            "$bam_file"

        # Run Binning
        pixi run --manifest-path "$WORKDIR/pixi.toml" -e taxonomy metabat2 \
            -i "$assembly" \
            -a "$depth_file" \
            -o "${bin_dir}/${SAMPLE}_bin" \
            -t "$CPUS_MED" \
            -m 1500 # Min contig size 1500bp
    else
        echo "--> Bins exist, skipping binning."
    fi

    # --- Step 2.5: MaxBin2 Binning ---
    maxbin_dir="${WORK_DIR}/maxbin"
    if [[ "$RUN_MAXBIN" == "true" ]]; then
        if [[ ! -d "$maxbin_dir" || -z "$(ls -A "$maxbin_dir"/*.fasta 2>/dev/null)" ]]; then
            echo "--> Running MaxBin2..."
            mkdir -p "$maxbin_dir"
            
            # Prepare abundance file for MaxBin2
            abund_file="${WORK_DIR}/${SAMPLE}_maxbin_abund.txt"
            tail -n +2 "$depth_file" | cut -f1,3 > "$abund_file"
            
            # Run MaxBin2
            pixi run --manifest-path "$WORKDIR/pixi.toml" -e taxonomy run_MaxBin.pl \
                -contig "$assembly" \
                -abund "$abund_file" \
                -out "${maxbin_dir}/${SAMPLE}_maxbin" \
                -thread "$CPUS_MED" \
                -min_contig_length 1500 &> "$RESULT_DIR/binning/${SAMPLE}.maxbin.log"
                
            echo "--> MaxBin2 binning completed for $SAMPLE."
        else
            echo "--> MaxBin2 bins exist, skipping binning."
        fi
    fi

    # --- Step 3: DAS Tool Refinement & Export ---
    # Merge and purify bins from MetaBAT2 and MaxBin2 to generate the best high-quality bins
    local copied_any=false
    dastool_dir="${WORK_DIR}/dastool"
    
    if [[ "$RUN_MAXBIN" == "true" ]]; then
        echo "--> Preparing DAS Tool refinement..."
        mkdir -p "$dastool_dir"
        
        # 3.1: Generate Scaffolds2Bin TSVs
        metabat_tsv="${dastool_dir}/metabat.scaffolds2bin.tsv"
        maxbin_tsv="${dastool_dir}/maxbin.scaffolds2bin.tsv"
        
        pixi run --manifest-path "$WORKDIR/pixi.toml" -e taxonomy Fasta_to_Scaffolds2Bin.sh -i "$bin_dir" -e fa > "$metabat_tsv" 2>/dev/null
        pixi run --manifest-path "$WORKDIR/pixi.toml" -e taxonomy Fasta_to_Scaffolds2Bin.sh -i "$maxbin_dir" -e fasta > "$maxbin_tsv" 2>/dev/null
        
        # 3.2: Validate TSVs to prevent DAS Tool crashes if a binner failed to find bins
        valid_tsvs=""
        valid_labels=""
        
        if [[ -s "$metabat_tsv" ]]; then
            valid_tsvs="$metabat_tsv"
            valid_labels="metabat"
        fi
        
        if [[ -s "$maxbin_tsv" ]]; then
            if [[ -n "$valid_tsvs" ]]; then
                valid_tsvs="${valid_tsvs},${maxbin_tsv}"
                valid_labels="${valid_labels},maxbin"
            else
                valid_tsvs="$maxbin_tsv"
                valid_labels="maxbin"
            fi
        fi
        
        # 3.3: Run DAS Tool if we have at least one valid bin set (preferably both)
        if [[ -n "$valid_tsvs" ]]; then
            echo "--> Running DAS Tool to merge and purify [$valid_labels] bins..."
            # Using diamond as search engine for speed
            pixi run --manifest-path "$WORKDIR/pixi.toml" -e taxonomy DAS_Tool -i "$valid_tsvs" \
                -l "$valid_labels" \
                -c "$assembly" \
                -o "${dastool_dir}/${SAMPLE}_das" \
                -t "$CPUS_MED" \
                --search_engine diamond \
                --write_bins &> "$RESULT_DIR/binning/${SAMPLE}.dastool.log"
                
            das_bins_dir="${dastool_dir}/${SAMPLE}_das_DASTool_bins"
            
            # Copy Purified Bins
            if [[ -d "$das_bins_dir" && -n "$(ls "$das_bins_dir"/*.fa 2>/dev/null)" ]]; then
                for bin_file in "$das_bins_dir"/*.fa; do
                    bin_name=$(basename "$bin_file" .fa)
                    # Append .fasta for downstream consistency
                    cp "$bin_file" "$BINNED_DIR/${bin_name}.fasta"
                    copied_any=true
                done
                echo "--> Copied purified DAS Tool bins for $SAMPLE to $BINNED_DIR"
            else
                echo "WARNING: DAS Tool failed or yielded no bins. Check $RESULT_DIR/binning/${SAMPLE}.dastool.log"
            fi
        fi
    fi

    # --- Step 3.5: Fallback Logic ---
    # If DAS Tool was skipped or failed, fallback to copying raw bins
    if [[ "$copied_any" == "false" ]]; then
        echo "--> DAS Tool step skipped or yielded no output. Falling back to copying raw bins..."
        
        # Copy MetaBAT2 bins
        if [[ -n "$(ls "$bin_dir"/*.fa 2>/dev/null)" ]]; then
            for bin_file in "$bin_dir"/*.fa; do
                bin_name=$(basename "$bin_file" .fa)
                cp "$bin_file" "$BINNED_DIR/${bin_name}.fasta"
                copied_any=true
            done
            echo "--> Copied all raw MetaBAT2 bins to $BINNED_DIR"
        fi
        
        # Copy MaxBin2 bins
        if [[ "$RUN_MAXBIN" == "true" && -n "$(ls "$maxbin_dir"/*.fasta 2>/dev/null)" ]]; then
            for bin_file in "$maxbin_dir"/*.fasta; do
                bin_name=$(basename "$bin_file" .fasta)
                cp "$bin_file" "$BINNED_DIR/${bin_name}.fasta"
                copied_any=true
            done
            echo "--> Copied all raw MaxBin2 bins to $BINNED_DIR"
        fi
        
        # Final Fallback: if absolutely no bins were generated
        if [[ "$copied_any" == "false" ]]; then
            echo "WARNING: No bins generated by any tool for $SAMPLE. Using entire polished assembly as fallback."
            cp "$assembly" "$BINNED_DIR/${SAMPLE}.fasta"
        fi
    fi

    echo "=== Finished Sample $SAMPLE ==="
    echo "-----------------------------------------------------"
done < "$INPUT_SHEET"

# Create success flag for pipeline resume mechanism
touch "$BINNED_DIR/metabat_success.flag"
echo "Binning stage completed successfully!"
echo "====================================================="
