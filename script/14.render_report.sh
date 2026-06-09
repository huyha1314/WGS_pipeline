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

# Extract first sample name dynamically from the collected assemblies
FIRST_GENOME_FILE=$(ls -1 "$RESULT_DIR/collected_assemblies"/*.fasta | grep -v "_original" | head -n 1)
FIRST_SAMPLE=$(basename "$FIRST_GENOME_FILE" .fasta)
base_sample=$(echo "$FIRST_SAMPLE" | cut -d'_' -f1)

# Copy the qmd template and header_footer to the report directory so all relative paths resolve
cp -p "$WORKDIR/14.rp.qmd" "$RESULT_DIR/rp/"
cp -r "$WORKDIR/header_footer" "$RESULT_DIR/rp/"

# Make the python script executable and generate the dynamic report sections
chmod +x "$WORKDIR/script/generate_report_sections.py"
python3 "$WORKDIR/script/generate_report_sections.py" "$RESULT_DIR/collected_assemblies" "$RESULT_DIR/rp/14.rp.qmd"

# Replace hardcoded 'sam1' and BUSCO JSON path with dynamic values
sed -i "s/short_summary.specific.enterobacteriaceae_odb12.sam1_busco.json/${FIRST_SAMPLE}_busco_summary.json/g" "$RESULT_DIR/rp/14.rp.qmd"
sed -i "s/00_QC\/sam1/00_QC\/${base_sample}/g" "$RESULT_DIR/rp/14.rp.qmd"
sed -i "s/download=\"sam1/download=\"${base_sample}/g" "$RESULT_DIR/rp/14.rp.qmd"
sed -i "s/sam1/${FIRST_SAMPLE}/g" "$RESULT_DIR/rp/14.rp.qmd"

# Save current dir
ORIG_DIR="$PWD"
cd "$RESULT_DIR/rp" || exit 1

# Render the document using the Pixi report environment
pixi run -e report quarto render 14.rp.qmd --to html

# Return to original dir
cd "$ORIG_DIR"

# Compress the report directory
echo "Compressing report folder..."
cd "$RESULT_DIR" || exit 1

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
