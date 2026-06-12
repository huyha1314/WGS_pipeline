#!/bin/bash
#SBATCH --job-name=render_report
#SBATCH --output=log/render_report_%j.out
#SBATCH --error=log/render_report_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G

# --- Load Central Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

echo "======================================================="
echo "Rendering Quarto Genomic Report..."
echo "======================================================="

# Verify target output directory exists
mkdir -p "$RESULT_DIR/rp"

# Ensure report is prepared
if [[ ! -f "$RESULT_DIR/rp/14.rp.qmd" ]]; then
    echo " -> Prepared Quarto file not found. Running preparation step..."
    bash "$SCRIPT_DIR/14.prepare_report.sh"
fi

# Save current dir
ORIG_DIR="$PWD"
cd "$RESULT_DIR/rp" || exit 1

# Render the document using the Pixi report environment
pixi run -e report quarto render 14.rp.qmd --to html
if [[ -f "14.rp_purine_project.qmd" ]]; then
    pixi run -e report quarto render 14.rp_purine_project.qmd --to html
    rm -f 14.rp_purine_project.qmd
fi

# Remove the source QMD file so it is not included in the final export folder
rm -f 14.rp.qmd

# Return to original dir
cd "$ORIG_DIR"

# Compress the report directory
echo "Compressing report folder..."
cd "$RESULT_DIR" || exit 1

# Remove existing archives to prevent retaining deleted files
rm -f rp.zip rp.tar.gz

# Generate both zip and tar.gz files
zip -q -r rp.zip rp
tar -czf rp.tar.gz rp

cd "$ORIG_DIR" || exit 1

echo "======================================================="
echo "Report Rendering & Compression Complete!"
echo "Final Report HTML: $RESULT_DIR/rp/14.rp.html"
echo "Compressed ZIP:    $RESULT_DIR/rp.zip"
echo "Compressed TAR.GZ: $RESULT_DIR/rp.tar.gz"
echo "======================================================="
touch "$RESULT_DIR/rp/report_success.flag"
