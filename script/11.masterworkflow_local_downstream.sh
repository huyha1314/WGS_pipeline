#!/bin/bash

# --- Load Central Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

# Ensure local runs log directory exists
LOCAL_LOG_DIR="$LOG_DIR/local_runs"
mkdir -p "$LOCAL_LOG_DIR"
TIMELINE_FILE="$LOCAL_LOG_DIR/timeline.log"

echo "====================================================="
echo "  PRECISIONGENE WGS PIPELINE - LOCAL DOWNSTREAM RUN  "
echo "====================================================="
echo "Configured Workspace: $WORKDIR"
echo "Results Directory:    $RESULT_DIR"
echo "Samples Sheet:        $INPUT_SHEET"
echo "Local Logs Directory: $LOCAL_LOG_DIR"
echo "Timeline Log:         $TIMELINE_FILE"
echo "====================================================="

# Initialize timeline log header
echo "=====================================================" >> "$TIMELINE_FILE"
echo "   WGS PIPELINE DOWNSTREAM RUN - $(date '+%Y-%m-%d %H:%M:%S')" >> "$TIMELINE_FILE"
echo "=====================================================" >> "$TIMELINE_FILE"

# Check if samples sheet exists
if [[ ! -f "$INPUT_SHEET" ]]; then
    echo "ERROR: Samples sheet not found at $INPUT_SHEET."
    exit 1
fi

# Extract the first sample name to determine if step needs to be resumed or skipped
FIRST_SAMPLE=$(tail -n +2 "$INPUT_SHEET" | head -n 1 | cut -d$'\t' -f1)

if [[ -z "$FIRST_SAMPLE" ]]; then
    echo "ERROR: Samples sheet is empty. Please populate $INPUT_SHEET."
    exit 1
fi

echo "First sample in sheet: $FIRST_SAMPLE (used for checkpointing)"
echo "-----------------------------------------------------"

# --- Reset/Clean Downstream Results (To align with the filtered bins) ---
echo "Cleaning up old downstream outputs and flag files to match your filtered bins..."
# Clear success flags so they re-run
rm -f "$RESULT_DIR/refined_assemblies/magpurify_success.flag"
rm -f "$RESULT_DIR/checkm_cleaned/checkm_success.flag"
rm -f "$RESULT_DIR/gtdbtk/gtdbtk_success.flag"
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

# Clear old tree genome copies and alignments (to remove deleted bins)
rm -rf "$RESULT_DIR/tree/genomes"
rm -rf "$RESULT_DIR/tree/gtdbtk_out"
rm -f "$RESULT_DIR/tree"/*.treefile
rm -f "$RESULT_DIR/tree"/selected_taxa_*.txt
rm -f "$RESULT_DIR/tree"/clean_accessions.txt

# Clear old report outputs
rm -rf "$RESULT_DIR/rp"

echo "Cleanup complete. Starting downstream pipeline execution."
echo "-----------------------------------------------------"

# Helper to format duration in MMm SSs or HHh MMm SSs
format_duration() {
    local secs=$1
    if (( secs < 60 )); then
        echo "${secs}s"
    elif (( secs < 3600 )); then
        echo "$((secs / 60))m $((secs % 60))s"
    else
        echo "$((secs / 3600))h $(( (secs % 3600) / 60))m $((secs % 60))s"
    fi
}

# --- Smart Job Execution Function ---
run_job() {
    local step_name="$1"
    local script_file="$2"
    local target_out="$3"
    local log_file="$LOCAL_LOG_DIR/${step_name}.log"

    local is_done=0

    # Check if target output exists (Resume Logic)
    if [[ -f "$target_out" && -s "$target_out" ]]; then
        is_done=1
    elif [[ -d "$target_out" && "$(ls -A "$target_out" 2>/dev/null)" ]]; then
        is_done=1
    fi

    if [[ $is_done -eq 1 ]]; then
        echo "====================================================="
        echo "[SKIP] $step_name: Output already exists -> $target_out"
        echo "====================================================="
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [SKIP] $step_name (Output already exists)" >> "$TIMELINE_FILE"
    else
        local start_epoch=$(date +%s)
        local start_time_str=$(date '+%Y-%m-%d %H:%M:%S')
        
        echo "====================================================="
        echo "[START] Running step: $step_name"
        echo "Script: $script_file"
        echo "Log File: $log_file"
        echo "Started At: $start_time_str"
        echo "====================================================="
        
        echo "$start_time_str - [START] $step_name" >> "$TIMELINE_FILE"
        
        # Execute script locally in the foreground and log output to file
        bash "$script_file" > "$log_file" 2>&1
        local exit_code=$?
        
        local end_epoch=$(date +%s)
        local end_time_str=$(date '+%Y-%m-%d %H:%M:%S')
        local elapsed=$((end_epoch - start_epoch))
        local formatted_duration=$(format_duration $elapsed)
        
        if [[ $exit_code -ne 0 ]]; then
            echo "====================================================="
            echo "ERROR: Step $step_name failed with exit code $exit_code."
            echo "Log File: $log_file"
            echo "====================================================="
            echo "$end_time_str - [FAILED] $step_name (Exit Code: $exit_code, Duration: $formatted_duration)" >> "$TIMELINE_FILE"
            exit $exit_code
        fi
        
        echo "====================================================="
        echo "[SUCCESS] Completed step: $step_name"
        echo "Completed At: $end_time_str"
        echo "Duration: $formatted_duration"
        echo "====================================================="
        
        echo "$end_time_str - [SUCCESS] $step_name (Duration: $formatted_duration)" >> "$TIMELINE_FILE"
    fi
}


if [[ "$RUN_MAGPURIFY" == "true" ]]; then
    echo "MAGpurify contamination removal is ENABLED."
    
    # 8.5. Genome Refinement - MAGpurify
    run_job "MAGpurify" "$SCRIPT_DIR/8.5.magpurify.sh" "$RESULT_DIR/refined_assemblies/magpurify_success.flag"

    # 8.6. Quality Verification - CheckM (Cleaned Bins)
    run_job "CheckM_Cleaned" "$SCRIPT_DIR/8.6.checkm_cleaned.sh" "$RESULT_DIR/checkm_cleaned/checkm_success.flag"

    # 8.7. Taxonomy Classification - GTDB-Tk (Cleaned Bins)
    run_job "GTDB-Tk_Cleaned" "$SCRIPT_DIR/8.7.gtdbtk_cleaned.sh" "$RESULT_DIR/gtdbtk_cleaned/gtdbtk_success.flag"
else
    echo "MAGpurify contamination removal is DISABLED. Skipping refinement and post-cleaning verification."
fi

# 8.2. Taxonomy Classification - GTDB-Tk (Filtered Bins)
run_job "GTDB-Tk" "$SCRIPT_DIR/8.2.gtdbtk.sh" "$RESULT_DIR/gtdbtk/gtdbtk_success.flag"

# 7. Gene Prediction - Bakta
run_job "Bakta" "$SCRIPT_DIR/7.bakta.sh" "$RESULT_DIR/annotation/bakta_success.flag"

# 9. Functional Annotation - eggNOG
run_job "EggNOG" "$SCRIPT_DIR/9.eggnog.sh" "$RESULT_DIR/eggnog/eggnog_success.flag"

# 10. Genome Statistics - BUSCO
run_job "BUSCO" "$SCRIPT_DIR/10.busco.sh" "$RESULT_DIR/busco/busco_success.flag"

# 11. Plasmid & Virus Prediction - geNomad & CheckV
run_job "Plasmid_Virus_Prediction" "$SCRIPT_DIR/10.5.plasmid_prediction.sh" "$RESULT_DIR/genomad/genomad_success.flag"

# 11.5. AMR & Virulence Gene Finding
if [[ "$RUN_AMR_VIRULENCE" == "true" ]]; then
    run_job "AMR_Virulence" "$SCRIPT_DIR/10.6.amr_virulence.sh" "$RESULT_DIR/amr_virulence/amr_virulence_success.flag"
fi

# 11.6. Secondary Metabolite & Bacteriocin Analysis
if [[ "$RUN_ANTISMASH" == "true" || "$RUN_BAGEL4" == "true" ]]; then
    run_job "Secondary_Metabolites" "$SCRIPT_DIR/10.7.secondary_metabolites.sh" "$RESULT_DIR/secondary_metabolites/secondary_metabolites_success.flag"
fi

# 12. Reference Phylogenomic Tree Building - GTDB-Tk & IQ-TREE
run_job "Phylogeny_Tree" "$SCRIPT_DIR/12.build_tree.sh" "$RESULT_DIR/tree/tree_success.flag"

# 13. Generate R Visualizations
run_job "Genomic_Visualizations" "$SCRIPT_DIR/13.draw.sh" "$RESULT_DIR/rp/draw_success.flag"

# 14. Prepare Quarto Report QMD (Stops here to let user write custom conclusions)
run_job "Report_Prepare" "$SCRIPT_DIR/14.prepare_report.sh" "$RESULT_DIR/rp/14.rp.qmd"

echo "================================================================================"
echo "                 PIPELINE ANALYSIS COMPLETE (PAUSED FOR REPORT)                  "
echo "================================================================================"
echo "All genomic analysis, tree building, and visualizations have completed."
echo "The report template has been prepared at: $RESULT_DIR/rp/14.rp.qmd"
echo ""
echo "To customize your report before final generation:"
echo "1. Open the file: $RESULT_DIR/rp/14.rp.qmd"
echo "2. Navigate to the '# Conclusion' section at the bottom."
echo "3. Write your custom conclusions or explanations for the batch/samples."
echo "4. Save the file."
echo "5. Render the final HTML report by running:"
echo "   bash script/14.render_report.sh"
echo "================================================================================"
