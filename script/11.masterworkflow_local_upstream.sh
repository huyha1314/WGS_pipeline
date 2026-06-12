#!/bin/bash

# --- Load Central Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

# Ensure local runs log directory exists
LOCAL_LOG_DIR="$LOG_DIR/local_runs"
mkdir -p "$LOCAL_LOG_DIR"
TIMELINE_FILE="$LOCAL_LOG_DIR/timeline.log"

echo "====================================================="
echo "  PRECISIONGENE WGS PIPELINE - LOCAL UPSTREAM RUN    "
echo "====================================================="
echo "Configured Workspace: $WORKDIR"
echo "Results Directory:    $RESULT_DIR"
echo "Samples Sheet:        $INPUT_SHEET"
echo "Local Logs Directory: $LOCAL_LOG_DIR"
echo "Timeline Log:         $TIMELINE_FILE"
echo "====================================================="

# Initialize timeline log header
echo "=====================================================" >> "$TIMELINE_FILE"
echo "   WGS PIPELINE UPSTREAM RUN - $(date '+%Y-%m-%d %H:%M:%S')" >> "$TIMELINE_FILE"
echo "=====================================================" >> "$TIMELINE_FILE"

# Check if samples sheet exists
if [[ ! -f "$INPUT_SHEET" ]]; then
    echo "ERROR: Samples sheet not found at $INPUT_SHEET."
    echo "Please run 'pixi run create-sheet -i <data_directory>' first to create it."
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

# 1. Quality Control - Fastp
run_job "Fastp" "$SCRIPT_DIR/1.fastp.sh" "$RESULT_DIR/fastp/trim.${FIRST_SAMPLE}_1.fq.gz"

# 2. Quality Control & Filtering - BBDuk / Bowtie / Kraken2
run_job "BBDuk" "$SCRIPT_DIR/2.bbduk.sh" "$RESULT_DIR/k2/clean.${FIRST_SAMPLE}_1.fq.gz"

# 3. Genome Assembly
run_job "Assembly" "$SCRIPT_DIR/3.assembly.sh" "$RESULT_DIR/assembly/${FIRST_SAMPLE}_assembly/final.contigs.fa"

# 4. Genome Polishing - Pilon Round 1
run_job "Pilon_R1" "$SCRIPT_DIR/4.pilon.sh" "$RESULT_DIR/bwa_pilon/${FIRST_SAMPLE}/${FIRST_SAMPLE}_pilon.fasta"

# 5. Scaffolding - SSpaces
run_job "SSpaces" "$SCRIPT_DIR/5.sspaces.sh" "$RESULT_DIR/sspaces/${FIRST_SAMPLE}_scaffold/${FIRST_SAMPLE}_sspace.final.scaffolds.fasta"

# 6. Polishing Round 2 - Pilon SS
run_job "Pilon_R2" "$SCRIPT_DIR/6.pilon_ss.sh" "$RESULT_DIR/final_polished/${FIRST_SAMPLE}/${FIRST_SAMPLE}_final_polished.fasta"

# 6.5. Genome Binning - MetaBAT2
run_job "MetaBAT2" "$SCRIPT_DIR/6.5.metabat2.sh" "$RESULT_DIR/binned_assemblies/metabat_success.flag"

# 8.1. Genome Statistics & Quality - CheckM (Original Bins)
run_job "CheckM" "$SCRIPT_DIR/8.1.checkm.sh" "$RESULT_DIR/checkm/checkm_success.flag"

echo "================================================================================"
echo "                   UPSTREAM PIPELINE EXECUTION COMPLETE!                        "
echo "================================================================================"
echo "CheckM quality control has finished."
echo "Please review the report at:"
echo "  CheckM summary: $RESULT_DIR/checkm/checkm_summary.txt"
echo ""
echo "To filter out/select which bins/assemblies to carry forward to the downstream steps:"
echo "1. Go to the collected assemblies directory:"
echo "   cd $RESULT_DIR/collected_assemblies"
echo "2. Look at the FASTA files in that directory. They correspond to original polished"
echo "   assemblies and individual MetaBAT2/MaxBin2 bins."
echo "3. Delete or move any files you wish to discard/filter out (e.g., using test.sh)."
echo "4. Once only the desired bins/assemblies remain in that folder, run the downstream"
echo "   pipeline using:"
echo "   pixi run run-pipeline-local-downstream"
echo "================================================================================"
