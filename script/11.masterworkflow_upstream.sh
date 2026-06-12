#!/bin/bash

# --- Load Central Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

# Ensure log directories exist
mkdir -p "$LOG_DIR" "$LOG_DIR/slurm_logs"

echo "====================================================="
echo "  PRECISIONGENE WGS PIPELINE - UPSTREAM SLURM SUBMIT "
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

FIRST_SAMPLE=$(tail -n +2 "$INPUT_SHEET" | head -n 1 | cut -d$'\t' -f1)

if [[ -z "$FIRST_SAMPLE" ]]; then
    echo "ERROR: Samples sheet is empty. Please populate $INPUT_SHEET."
    exit 1
fi

JOB1=$(submit_job "Fastp" "$SCRIPT_DIR/1.fastp.sh" "$RESULT_DIR/fastp/trim.${FIRST_SAMPLE}_1.fq.gz" "")
JOB2=$(submit_job "BBDuk" "$SCRIPT_DIR/2.bbduk.sh" "$RESULT_DIR/k2/clean.${FIRST_SAMPLE}_1.fq.gz" "$JOB1")
JOB3=$(submit_job "Assembly" "$SCRIPT_DIR/3.assembly.sh" "$RESULT_DIR/assembly/${FIRST_SAMPLE}_assembly/final.contigs.fa" "$JOB2")
JOB4=$(submit_job "Pilon_R1" "$SCRIPT_DIR/4.pilon.sh" "$RESULT_DIR/bwa_pilon/${FIRST_SAMPLE}/${FIRST_SAMPLE}_pilon.fasta" "$JOB3")
JOB5=$(submit_job "SSpaces" "$SCRIPT_DIR/5.sspaces.sh" "$RESULT_DIR/sspaces/${FIRST_SAMPLE}_scaffold/${FIRST_SAMPLE}_sspace.final.scaffolds.fasta" "$JOB4")
JOB6=$(submit_job "Pilon_R2" "$SCRIPT_DIR/6.pilon_ss.sh" "$RESULT_DIR/final_polished/${FIRST_SAMPLE}/${FIRST_SAMPLE}_final_polished.fasta" "$JOB5")
JOB6_5=$(submit_job "MetaBAT2" "$SCRIPT_DIR/6.5.metabat2.sh" "$RESULT_DIR/binned_assemblies/metabat_success.flag" "$JOB6")
JOB8_1=$(submit_job "CheckM" "$SCRIPT_DIR/8.1.checkm.sh" "$RESULT_DIR/checkm/checkm_success.flag" "$JOB6_5")

echo "================================================================================"
echo "                   UPSTREAM PIPELINE JOBS SUBMITTED!                            "
echo "================================================================================"
echo "CheckM quality control job has been submitted (JobID: $JOB8_1)."
echo "Use 'squeue -u $USER' to monitor your jobs."
echo ""
echo "To filter out/select which bins/assemblies to carry forward to the downstream steps:"
echo "1. Wait for CheckM to complete."
echo "2. Go to the collected assemblies directory:"
echo "   cd $RESULT_DIR/collected_assemblies"
echo "3. Review the CheckM report and delete/move files you wish to discard/filter out."
echo "4. Once only the desired bins/assemblies remain in that folder, run the downstream"
echo "   pipeline using:"
echo "   pixi run run-pipeline-downstream"
echo "================================================================================"
