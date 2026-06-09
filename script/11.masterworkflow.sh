#!/bin/bash

# --- Load Central Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

# Ensure log directories exist
mkdir -p "$LOG_DIR" "$LOG_DIR/slurm_logs"

echo "====================================================="
echo "  PRECISIONGENE WGS PIPELINE - AUTO SUBMIT & RESUME  "
echo "====================================================="
echo "Configured Workspace: $WORKDIR"
echo "Results Directory:    $RESULT_DIR"
echo "Samples Sheet:        $INPUT_SHEET"
echo "====================================================="

# Check if samples sheet exists
if [[ ! -f "$INPUT_SHEET" ]]; then
    echo "ERROR: Samples sheet not found at $INPUT_SHEET."
    echo "Please run 'pixi run create-sheet -i <data_directory>' first to create it."
    exit 1
fi

# --- Smart Job Submission Function ---
# Syntax: submit_job <Step_Name> <Script_File> <Expected_Output_Path> <Dependent_Job_ID>
submit_job() {
    local step_name="$1"
    local script_file="$2"
    local target_out="$3"
    local dep_job_id="$4"

    local is_done=0

    # Check if target output exists (Resume Logic)
    if [[ -f "$target_out" && -s "$target_out" ]]; then
        # File exists and is not empty
        is_done=1
    elif [[ -d "$target_out" && "$(ls -A "$target_out" 2>/dev/null)" ]]; then
        # Directory exists and is not empty
        is_done=1
    fi

    if [[ $is_done -eq 1 ]]; then
        echo "[SKIP] $step_name: Output already exists -> $target_out" >&2
        echo "DONE" # Return DONE keyword instead of Job ID
    else
        local sbatch_args="--parsable"
        
        # If dependent job is running, wait for it
        if [[ -n "$dep_job_id" && "$dep_job_id" != "DONE" ]]; then
            sbatch_args="$sbatch_args --dependency=afterok:$dep_job_id"
        fi
        
        # Submit script to SLURM scheduler
        local job_id=$(sbatch $sbatch_args "$script_file")
        echo "[SUBMIT] $step_name: JobID $job_id" >&2
        echo "$job_id"
    fi
}

# --- PIPELINE PIPES ---
# Define targets based on first sample in the sheet for checkpoint checking
# We extract the first sample name to determine if step needs to be resumed or skipped
FIRST_SAMPLE=$(tail -n +2 "$INPUT_SHEET" | head -n 1 | cut -d$'\t' -f1)

if [[ -z "$FIRST_SAMPLE" ]]; then
    echo "ERROR: Samples sheet is empty. Please populate $INPUT_SHEET."
    exit 1
fi

echo "First sample in sheet: $FIRST_SAMPLE (used for checkpointing)"
echo "-----------------------------------------------------"

# 1. Quality Control - Fastp
JOB1=$(submit_job "Fastp" "$SCRIPT_DIR/1.fastp.sh" "$RESULT_DIR/fastp/trim.${FIRST_SAMPLE}_1.fq.gz" "")

# 2. Quality Control & Filtering - BBDuk / Bowtie / Kraken2
JOB2=$(submit_job "BBDuk" "$SCRIPT_DIR/2.bbduk.sh" "$RESULT_DIR/k2/clean.${FIRST_SAMPLE}_1.fq.gz" "$JOB1")

# 3. Genome Assembly - Megahit
JOB3=$(submit_job "Megahit" "$SCRIPT_DIR/3.megahit.sh" "$RESULT_DIR/megahit/${FIRST_SAMPLE}_assembly/final.contigs.fa" "$JOB2")

# 4. Genome Polishing - Pilon Round 1
JOB4=$(submit_job "Pilon_R1" "$SCRIPT_DIR/4.pilon.sh" "$RESULT_DIR/bwa_pilon/${FIRST_SAMPLE}/${FIRST_SAMPLE}_pilon.fasta" "$JOB3")

# 5. Scaffolding - SSpaces
JOB5=$(submit_job "SSpaces" "$SCRIPT_DIR/5.sspaces.sh" "$RESULT_DIR/sspaces/${FIRST_SAMPLE}_scaffold/${FIRST_SAMPLE}_sspace.final.scaffolds.fasta" "$JOB4")

# 6. Polishing Round 2 - Pilon SS
JOB6=$(submit_job "Pilon_R2" "$SCRIPT_DIR/6.pilon_ss.sh" "$RESULT_DIR/final_polished/${FIRST_SAMPLE}/${FIRST_SAMPLE}_final_polished.fasta" "$JOB5")

# 6.5. Genome Binning - MetaBAT2
JOB6_5=$(submit_job "MetaBAT2" "$SCRIPT_DIR/6.5.metabat2.sh" "$RESULT_DIR/binned_assemblies/metabat_success.flag" "$JOB6")

# --- Helper to Build Slurm Dependencies ---
build_deps() {
    local deps=""
    for job in "$@"; do
        if [[ "$job" != "DONE" && -n "$job" ]]; then
            if [[ -z "$deps" ]]; then
                deps="$job"
            else
                deps="$deps:$job"
            fi
        fi
    done
    echo "$deps"
}

# 8.1. Genome Statistics & Quality - CheckM (Original Bins)
JOB8_1=$(submit_job "CheckM" "$SCRIPT_DIR/8.1.checkm.sh" "$RESULT_DIR/checkm/checkm_success.flag" "$JOB6_5")

# 8.2. Taxonomy Classification - GTDB-Tk (Original Bins)
JOB8_2=$(submit_job "GTDB-Tk" "$SCRIPT_DIR/8.2.gtdbtk.sh" "$RESULT_DIR/gtdbtk/gtdbtk_success.flag" "$JOB6_5")

if [[ "$RUN_MAGPURIFY" == "true" ]]; then
    echo "MAGpurify contamination removal is ENABLED."
    
    # 8.5. Genome Refinement - MAGpurify
    DEP_MAG=$(build_deps "$JOB8_1" "$JOB8_2")
    JOB8_5=$(submit_job "MAGpurify" "$SCRIPT_DIR/8.5.magpurify.sh" "$RESULT_DIR/refined_assemblies/magpurify_success.flag" "$DEP_MAG")

    # 8.6. Quality Verification - CheckM (Cleaned Bins)
    JOB8_6=$(submit_job "CheckM_Cleaned" "$SCRIPT_DIR/8.6.checkm_cleaned.sh" "$RESULT_DIR/checkm_cleaned/checkm_success.flag" "$JOB8_5")

    # 8.7. Taxonomy Classification - GTDB-Tk (Cleaned Bins)
    JOB8_7=$(submit_job "GTDB-Tk_Cleaned" "$SCRIPT_DIR/8.7.gtdbtk_cleaned.sh" "$RESULT_DIR/gtdbtk_cleaned/gtdbtk_success.flag" "$JOB8_5")
    
    LAST_TAX_JOB=$(build_deps "$JOB8_6" "$JOB8_7")
else
    echo "MAGpurify contamination removal is DISABLED. Skipping refinement and post-cleaning verification."
    LAST_TAX_JOB=$(build_deps "$JOB8_1" "$JOB8_2")
fi

# 7. Gene Prediction - Bakta
JOB7=$(submit_job "Bakta" "$SCRIPT_DIR/7.bakta.sh" "$RESULT_DIR/annotation/bakta_success.flag" "$LAST_TAX_JOB")

# 9. Functional Annotation - eggNOG
JOB9=$(submit_job "EggNOG" "$SCRIPT_DIR/9.eggnog.sh" "$RESULT_DIR/eggnog/eggnog_success.flag" "$JOB7")

# 10. Genome Statistics - BUSCO
JOB10=$(submit_job "BUSCO" "$SCRIPT_DIR/10.busco.sh" "$RESULT_DIR/busco/busco_success.flag" "$LAST_TAX_JOB")

# 11. Plasmid & Virus Prediction - geNomad & CheckV
JOB11=$(submit_job "Plasmid_Virus_Prediction" "$SCRIPT_DIR/10.5.plasmid_prediction.sh" "$RESULT_DIR/genomad/genomad_success.flag" "$LAST_TAX_JOB")

# 12. Reference Phylogenomic Tree Building - GTDB-Tk & IQ-TREE
JOB12=$(submit_job "Phylogeny_Tree" "$SCRIPT_DIR/12.build_tree.sh" "$RESULT_DIR/tree/tree_success.flag" "$LAST_TAX_JOB")

# --- Report Generation & Visualizations (Depends on all downstream steps) ---

# Build colon-separated dependency list of active Slurm Job IDs
DRAW_DEPS=$(build_deps "$JOB7" "$JOB9" "$JOB10" "$JOB12")

# 13. Generate R Visualizations
JOB13=$(submit_job "Genomic_Visualizations" "$SCRIPT_DIR/13.draw.sh" "$RESULT_DIR/rp/draw_success.flag" "$DRAW_DEPS")

# 14. Render Quarto Report HTML
JOB14=$(submit_job "Report_Render" "$SCRIPT_DIR/14.render_report.sh" "$RESULT_DIR/rp/report_success.flag" "$JOB13")

echo "====================================================="
echo "Pipeline execution checks complete!"
echo "Use 'squeue -u $USER' to monitor the submitted jobs."
echo "====================================================="