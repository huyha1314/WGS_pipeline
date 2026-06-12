#!/bin/bash
# --- Load Central Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

echo "======================================================="
# Verify target output directory exists
mkdir -p "$RESULT_DIR/rp"

# Extract first sample name dynamically from the collected assemblies
FIRST_GENOME_FILE=$(ls -1 "$RESULT_DIR/collected_assemblies"/*.fasta | grep -v "_original" | head -n 1)
if [[ -z "$FIRST_GENOME_FILE" ]]; then
    echo "ERROR: No genome fasta files found in collected assemblies."
    exit 1
fi

FIRST_SAMPLE=$(basename "$FIRST_GENOME_FILE" .fasta)
base_sample=$(echo "$FIRST_SAMPLE" | cut -d'_' -f1)

# Create the specialized purine project report template by copying the master
cp -p "$WORKDIR/14.rp.qmd" "$WORKDIR/14.rp_purine_project.qmd"

# Run the target genes screening to generate data matrix and append it to the purine template
python3 "$WORKDIR/scratch/search_target_genes_pure.py"

# Copy the qmd templates and header_footer to the report directory so all relative paths resolve
cp -p "$WORKDIR/14.rp.qmd" "$RESULT_DIR/rp/"
cp -p "$WORKDIR/14.rp_purine_project.qmd" "$RESULT_DIR/rp/"
cp -r "$WORKDIR/header_footer" "$RESULT_DIR/rp/"

# Copy the generated targeted genes CSV to the report staging directory
mkdir -p "$RESULT_DIR/rp/02_Functional"
[[ -f "$WORKDIR/02_Functional/targeted_genes.csv" ]] && cp -p "$WORKDIR/02_Functional/targeted_genes.csv" "$RESULT_DIR/rp/02_Functional/"

# Make the python script executable and generate the dynamic report sections
chmod +x "$WORKDIR/script/generate_report_sections.py"
python3 "$WORKDIR/script/generate_report_sections.py" "$RESULT_DIR/collected_assemblies" "$RESULT_DIR/rp/14.rp.qmd"
python3 "$WORKDIR/script/generate_report_sections.py" "$RESULT_DIR/collected_assemblies" "$RESULT_DIR/rp/14.rp_purine_project.qmd"

# Replace hardcoded 'sam1' and BUSCO JSON path with dynamic values for all reports
for qmd in "$RESULT_DIR/rp"/14.rp*.qmd; do
    if [[ -f "$qmd" ]]; then
        sed -i "s/title: \"WGS-bacomix\"/title: \"WGS Analysis - ${BATCH_NAME}\"/g" "$qmd"
        sed -i "s/sam1_final_publication_tree/${BATCH_NAME}_final_publication_tree/g" "$qmd"
        sed -i "s/sam1_annotated_tree/${BATCH_NAME}_annotated_tree/g" "$qmd"
        sed -i "s/short_summary.specific.enterobacteriaceae_odb12.sam1_busco.json/${FIRST_SAMPLE}_busco_summary.json/g" "$qmd"
        sed -i "s/00_QC\/sam1/00_QC\/${base_sample}/g" "$qmd"
        sed -i "s/download=\"sam1/download=\"${base_sample}/g" "$qmd"
        sed -i "s/sam1/${FIRST_SAMPLE}/g" "$qmd"
    fi
done

echo "======================================================="
echo "Report Preparation Complete!"
echo "Quarto template is ready for editing at: $RESULT_DIR/rp/14.rp.qmd"
echo "You can open this file and add your custom conclusions/explanations."
echo "======================================================="
