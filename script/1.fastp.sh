#!/bin/bash
#SBATCH --job-name=fastp
#SBATCH --output=./log/fastp.%j.out
#SBATCH --error=./log/fastp.%j.err
#SBATCH --ntasks=1           
#SBATCH --mem=124G           
#SBATCH --cpus-per-task=48   

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

# Create directories
mkdir -p "$LOG_DIR" "$RESULT_DIR/fastp" "$RESULT_DIR/multiqc"

CMD_FILE="$RESULT_DIR/fastp/fastp_commands.txt"
> "$CMD_FILE"

echo "Preparing fastp commands from samples sheet..."

# Read samples sheet
if [[ ! -f "$INPUT_SHEET" ]]; then
    echo "ERROR: Input sheet not found at $INPUT_SHEET"
    exit 1
fi

# Skip header row and read TSV
while IFS=$'\t' read -r SAMPLE R1_PATH R2_PATH; do
    if [[ "$SAMPLE" == "name" || -z "$SAMPLE" ]]; then
        continue
    fi

    # Define Output Filenames
    OUT_R1="$RESULT_DIR/fastp/trim.${SAMPLE}_1.fq.gz"
    OUT_R2="$RESULT_DIR/fastp/trim.${SAMPLE}_2.fq.gz"
    REPORT_HTML="$RESULT_DIR/multiqc/${SAMPLE}.report.html"
    REPORT_JSON="$RESULT_DIR/multiqc/${SAMPLE}.report.json"

    # --- CHECK: If output exists and is not empty, skip ---
    if [[ -s "$OUT_R1" && -s "$OUT_R2" ]]; then
        echo "SKIPPING: $SAMPLE (Files already exist)"
    else
        # Add command to file
        echo "pixi run -e qc fastp \
            -i \"$R1_PATH\" -I \"$R2_PATH\" \
            -o \"$OUT_R1\" -O \"$OUT_R2\" \
            --trim_front1 $FASTP_TRIM_FRONT1 --trim_front2 $FASTP_TRIM_FRONT2 \
            --length_required $FASTP_LENGTH_REQUIRED \
            --qualified_quality_phred $FASTP_QUALIFIED_QUALITY_PHRED \
            --thread $THREADS_PER_FASTP \
            --html \"$REPORT_HTML\" \
            --json \"$REPORT_JSON\"" >> "$CMD_FILE"
    fi
done < "$INPUT_SHEET"

# Run commands in parallel if the file is not empty
if [[ -s "$CMD_FILE" ]]; then
    job_count=$(wc -l < "$CMD_FILE")
    echo "Running $job_count jobs with $PARALLEL_JOBS_FASTP parallel processes..."
    cat "$CMD_FILE" | pixi run parallel -j "$PARALLEL_JOBS_FASTP"
else
    echo "All files already processed. No jobs to run."
fi