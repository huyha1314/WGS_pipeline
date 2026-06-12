#!/bin/bash

# --- Load Central Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

# Ensure log directories exist
mkdir -p "$LOG_DIR" "$LOG_DIR/slurm_logs"

echo "====================================================="
echo "  PRECISIONGENE WGS PIPELINE - DOWNSTREAM SLURM SUBMIT"
echo "====================================================="
echo "Configured Workspace: $WORKDIR"
echo "Results Directory:    $RESULT_DIR"
echo "Samples Sheet:        $INPUT_SHEET"
echo "====================================================="

# Check if samples sheet exists
if [[ ! -f "$INPUT_SHEET" ]]; then
    echo "ERROR: Samples sheet not found at $INPUT_SHEET."
    exit 1
fi

FIRST_SAMPLE=$(tail -n +2 "$INPUT_SHEET" | head -n 1 | cut -d$'\t' -f1)

if [[ -z "$FIRST_SAMPLE" ]]; then
    echo "ERROR: Samples sheet is empty. Please populate $INPUT_SHEET."
    exit 1
fi

# --- Reset/Clean Downstream Results (To align with the filtered bins) ---
echo "Cleaning up old downstream outputs and flag files to match your filtered bins..."
rm -f "$RESULT_DIR/refined_assemblies/magpurify_success.flag"
rm -f "$RESULT_DIR/checkm_cleaned/checkm_success.flag"
rm -f "$RESULT_DIR/gtdbtk_cleaned/gtdbtk_success.flag"
rm -f "$RESULT_DIR/annotation/bakta_success.flag"
rm -f "$RESULT_DIR/eggnog/eggnog_success.flag"
rm -f "$RESULT_DIR/busco/busco_success.flag"
rm -f "$RESULT_DIR/genomad/genomad_success.flag"
rm -f "$RESULT_DIR/amr_virulence/amr_virulence_success.flag"
rm -f "$RESULT_DIR/secondary_metabolites/secondary_metabolites_success.flag"
rm -f "$RESULT_DIR/tree/tree_success.flag"
rm -f "$RESULT_DIR/rp/draw_success.flag"
rm -f "$RESULT_DIR/rp/report_success.flag"

rm -rf "$RESULT_DIR/tree/genomes"
rm -rf "$RESULT_DIR/tree/gtdbtk_out"
rm -f "$RESULT_DIR/tree"/*.treefile
rm -f "$RESULT_DIR/tree"/selected_taxa_*.txt
rm -f "$RESULT_DIR/tree"/clean_accessions.txt
rm -rf "$RESULT_DIR/rp"

submit_job() {
    local step_name="$1"
    local script_file="$2"
    local target_out="$3"
    local dep_job_id="$4"

    local is_done=0

    # Check if target output exists (Resume Logic)
    if [[ -f "$target_out" && -s "$target_out" ]]; then
        is_done=1
    elif [[ -d "$target_out" && "$(ls -A "$target_out" 2>/dev/null)" ]]; then
        is_done=1
    fi

    if [[ $is_done -eq 1 ]]; then
        echo "[SKIP] $step_name: Output already exists -> $target_out" >&2
        echo "DONE"
    else
        local sbatch_args="--parsable"
        if [[ -n "$dep_job_id" && "$dep_job_id" != "DONE" ]]; then
            sbatch_args="$sbatch_args --dependency=afterok:$dep_job_id"
        fi
        local job_id=$(sbatch $sbatch_args "$script_file")
        echo "[SUBMIT] $step_name: JobID $job_id" >&2
        echo "$job_id"
    fi
}

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

# 8.2. Taxonomy Classification - GTDB-Tk (Filtered Bins)
JOB8_2=$(submit_job "GTDB-Tk" "$SCRIPT_DIR/8.2.gtdbtk.sh" "$RESULT_DIR/gtdbtk/gtdbtk_success.flag" "")

if [[ "$RUN_MAGPURIFY" == "true" ]]; then
    echo "MAGpurify contamination removal is ENABLED."
    
    # 8.5. Genome Refinement - MAGpurify
    JOB8_5=$(submit_job "MAGpurify" "$SCRIPT_DIR/8.5.magpurify.sh" "$RESULT_DIR/refined_assemblies/magpurify_success.flag" "")

    # 8.6. Quality Verification - CheckM (Cleaned Bins)
    JOB8_6=$(submit_job "CheckM_Cleaned" "$SCRIPT_DIR/8.6.checkm_cleaned.sh" "$RESULT_DIR/checkm_cleaned/checkm_success.flag" "$JOB8_5")

    # 8.7. Taxonomy Classification - GTDB-Tk (Cleaned Bins)
    JOB8_7=$(submit_job "GTDB-Tk_Cleaned" "$SCRIPT_DIR/8.7.gtdbtk_cleaned.sh" "$RESULT_DIR/gtdbtk_cleaned/gtdbtk_success.flag" "$JOB8_5")
    
    LAST_TAX_JOB=$(build_deps "$JOB8_2" "$JOB8_6" "$JOB8_7")
else
    echo "MAGpurify contamination removal is DISABLED. Skipping refinement and post-cleaning verification."
    LAST_TAX_JOB="$JOB8_2"
fi

# 7. Gene Prediction - Bakta
JOB7=$(submit_job "Bakta" "$SCRIPT_DIR/7.bakta.sh" "$RESULT_DIR/annotation/bakta_success.flag" "$LAST_TAX_JOB")

# 9. Functional Annotation - eggNOG
JOB9=$(submit_job "EggNOG" "$SCRIPT_DIR/9.eggnog.sh" "$RESULT_DIR/eggnog/eggnog_success.flag" "$JOB7")

# 10. Genome Statistics - BUSCO
JOB10=$(submit_job "BUSCO" "$SCRIPT_DIR/10.busco.sh" "$RESULT_DIR/busco/busco_success.flag" "$LAST_TAX_JOB")

# 11. Plasmid & Virus Prediction - geNomad & CheckV
JOB11=$(submit_job "Plasmid_Virus_Prediction" "$SCRIPT_DIR/10.5.plasmid_prediction.sh" "$RESULT_DIR/genomad/genomad_success.flag" "$LAST_TAX_JOB")

# 11.5. AMR & Virulence Gene Finding
if [[ "$RUN_AMR_VIRULENCE" == "true" ]]; then
    JOB11_5=$(submit_job "AMR_Virulence" "$SCRIPT_DIR/10.6.amr_virulence.sh" "$RESULT_DIR/amr_virulence/amr_virulence_success.flag" "$LAST_TAX_JOB")
else
    JOB11_5="DONE"
fi

# 11.6. Secondary Metabolite & Bacteriocin Analysis
if [[ "$RUN_ANTISMASH" == "true" || "$RUN_BAGEL4" == "true" ]]; then
    JOB11_6=$(submit_job "Secondary_Metabolites" "$SCRIPT_DIR/10.7.secondary_metabolites.sh" "$RESULT_DIR/secondary_metabolites/secondary_metabolites_success.flag" "$JOB7")
else
    JOB11_6="DONE"
fi

# 12. Reference Phylogenomic Tree Building - GTDB-Tk & IQ-TREE
JOB12=$(submit_job "Phylogeny_Tree" "$SCRIPT_DIR/12.build_tree.sh" "$RESULT_DIR/tree/tree_success.flag" "$LAST_TAX_JOB")

DRAW_DEPS=$(build_deps "$JOB7" "$JOB9" "$JOB10" "$JOB11" "$JOB11_5" "$JOB11_6" "$JOB12")

# 13. Generate R Visualizations
JOB13=$(submit_job "Genomic_Visualizations" "$SCRIPT_DIR/13.draw.sh" "$RESULT_DIR/rp/draw_success.flag" "$DRAW_DEPS")

# 14. Render Quarto Report HTML
JOB14=$(submit_job "Report_Render" "$SCRIPT_DIR/14.render_report.sh" "$RESULT_DIR/rp/report_success.flag" "$JOB13")

echo "====================================================="
echo "Downstream jobs submitted!"
echo "Use 'squeue -u $USER' to monitor."
echo "====================================================="
