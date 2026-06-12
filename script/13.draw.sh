#!/bin/bash

# ==============================================================================
# Master Script: Genomic Visualization Pipeline
# Purpose: Runs BUSCO, EggNOG/KEGG, Bakta, Assembly Taxonomy, and Phylogeny.
#          Archives all input data into the report folder.
# ==============================================================================

# --- Load Central Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

# Extract first sample name from the sheet for reporting
FIRST_GENOME_FILE=$(ls -1 "$RESULT_DIR/collected_assemblies"/*.fasta | grep -v "_original" | head -n 1)
FIRST_SAMPLE=$(basename "$FIRST_GENOME_FILE" .fasta)

if [[ -z "$FIRST_SAMPLE" ]]; then
    echo "ERROR: Collected assemblies folder is empty. Cannot run visualization."
    exit 1
fi

echo "Generating visualizations for sample: $FIRST_SAMPLE"

# --- 1. DYNAMIC INPUT PATHS ---

# 1. BUSCO Inputs (locates the correct JSON file dynamically)
BUSCO_JSON=$(find "$RESULT_DIR/busco/${FIRST_SAMPLE}_busco" -name "short_summary.specific.*.${FIRST_SAMPLE}_busco.json" | head -n 1)

# 2. EggNOG Inputs
EGGNOG_ANNOT="$RESULT_DIR/eggnog/${FIRST_SAMPLE}.emapper.annotations"

# 3. Bakta Inputs
BAKTA_TSV="$RESULT_DIR/annotation/${FIRST_SAMPLE}/${FIRST_SAMPLE}.tsv"
BAKTA_TXT="$RESULT_DIR/annotation/${FIRST_SAMPLE}/${FIRST_SAMPLE}.txt"

# 4. Assembly Taxonomy Inputs
CHECKM_TSV="$RESULT_DIR/checkm/checkm_summary.txt"

if [[ -f "$RESULT_DIR/gtdbtk_cleaned/gtdbtk.bac120.summary.tsv" ]]; then
    GTDB_TSV="$RESULT_DIR/gtdbtk_cleaned/gtdbtk.bac120.summary.tsv"
    GTDB_TREE=""
    for tree_candidate in \
        "$RESULT_DIR/gtdbtk_cleaned/classify/gtdbtk.bac120.classify.tree.1.tree" \
        "$RESULT_DIR/gtdbtk_cleaned/classify/gtdbtk.bac120.classify.tree" \
        "$RESULT_DIR/gtdbtk_cleaned/classify/gtdbtk.backbone.bac120.classify.tree"; do
        if [[ -f "$tree_candidate" ]]; then
            GTDB_TREE="$tree_candidate"
            break
        fi
    done
else
    GTDB_TSV="$RESULT_DIR/gtdbtk/gtdbtk.bac120.summary.tsv"
    GTDB_TREE=""
    for tree_candidate in \
        "$RESULT_DIR/gtdbtk/classify/gtdbtk.bac120.classify.tree.1.tree" \
        "$RESULT_DIR/gtdbtk/classify/gtdbtk.bac120.classify.tree" \
        "$RESULT_DIR/gtdbtk/classify/gtdbtk.backbone.bac120.classify.tree"; do
        if [[ -f "$tree_candidate" ]]; then
            GTDB_TREE="$tree_candidate"
            break
        fi
    done
fi

# 5. Phylogeny Inputs
ANNOTATED_TREE="$RESULT_DIR/tree/${BATCH_NAME}_annotated_tree.treefile"

# 6. QC Report
base_sample=$(echo "$FIRST_SAMPLE" | cut -d'_' -f1)
QC="$RESULT_DIR/multiqc/${base_sample}.report.html"

# --- 2. DIRECTORY SETUP ---
VIS_SCRIPT_DIR="$WORKDIR/vis"
BASE_OUTDIR="$RESULT_DIR/rp"
DATA_OUTDIR="$BASE_OUTDIR/data"

# Create specific output directories
mkdir -p "$BASE_OUTDIR/00_QC"
mkdir -p "$BASE_OUTDIR/01_BUSCO"
mkdir -p "$BASE_OUTDIR/02_Functional"
mkdir -p "$BASE_OUTDIR/03_Bakta"
mkdir -p "$BASE_OUTDIR/04_Taxonomy"
mkdir -p "$BASE_OUTDIR/05_Phylogeny"
mkdir -p "$BASE_OUTDIR/08_MGEs"
mkdir -p "$BASE_OUTDIR/06_AMR_Virulence"
mkdir -p "$BASE_OUTDIR/07_Secondary_Metabolites"
mkdir -p "$DATA_OUTDIR"

echo "======================================================="
echo "Starting Visualization Pipeline..."
echo "Output Directory: $BASE_OUTDIR"
echo "======================================================="

# --- 3. COPY DATA FOR ARCHIVE ---
echo "Copying input data to $DATA_OUTDIR for archiving..."

# Copy all QC reports
for qc_file in "$RESULT_DIR/multiqc"/*.report.html; do
    if [[ -f "$qc_file" ]]; then
        cp -p "$qc_file" "$BASE_OUTDIR/00_QC/"
    fi
done

[[ -f "$CHECKM_TSV" ]] && cp -p "$CHECKM_TSV" "$DATA_OUTDIR/"
[[ -f "$GTDB_TSV" ]] && cp -p "$GTDB_TSV" "$DATA_OUTDIR/"
[[ -f "$GTDB_TREE" ]] && cp -p "$GTDB_TREE" "$DATA_OUTDIR/"

for fasta in "$RESULT_DIR/collected_assemblies"/*.fasta; do
    if [[ -f "$fasta" && ! "$fasta" =~ _original\.fasta$ ]]; then
        SAMPLE=$(basename "$fasta" .fasta)
        
        # BUSCO
        BUSCO_JSON=$(find "$RESULT_DIR/busco/${SAMPLE}_busco" -name "short_summary.specific.*.${SAMPLE}_busco.json" | head -n 1)
        [[ -f "$BUSCO_JSON" ]] && cp -p "$BUSCO_JSON" "$DATA_OUTDIR/${SAMPLE}_busco_summary.json"
        
        # EggNOG
        EGGNOG_ANNOT="$RESULT_DIR/eggnog/${SAMPLE}.emapper.annotations"
        [[ -f "$EGGNOG_ANNOT" ]] && cp -p "$EGGNOG_ANNOT" "$DATA_OUTDIR/"
        
        # Bakta
        BAKTA_TSV="$RESULT_DIR/annotation/${SAMPLE}/${SAMPLE}.tsv"
        BAKTA_TXT="$RESULT_DIR/annotation/${SAMPLE}/${SAMPLE}.txt"
        [[ -f "$BAKTA_TSV" ]] && cp -p "$BAKTA_TSV" "$DATA_OUTDIR/"
        [[ -f "$BAKTA_TXT" ]] && cp -p "$BAKTA_TXT" "$DATA_OUTDIR/"
        
        # geNomad & CheckV
        [[ -f "$RESULT_DIR/genomad/${SAMPLE}/${SAMPLE}_summary/${SAMPLE}_plasmid_summary.tsv" ]] && cp -p "$RESULT_DIR/genomad/${SAMPLE}/${SAMPLE}_summary/${SAMPLE}_plasmid_summary.tsv" "$DATA_OUTDIR/${SAMPLE}_plasmid_summary.tsv"
        [[ -f "$RESULT_DIR/genomad/${SAMPLE}/${SAMPLE}_summary/${SAMPLE}_virus_summary.tsv" ]] && cp -p "$RESULT_DIR/genomad/${SAMPLE}/${SAMPLE}_summary/${SAMPLE}_virus_summary.tsv" "$DATA_OUTDIR/${SAMPLE}_virus_summary.tsv"
        [[ -f "$RESULT_DIR/checkv/${SAMPLE}/quality_summary.tsv" ]] && cp -p "$RESULT_DIR/checkv/${SAMPLE}/quality_summary.tsv" "$DATA_OUTDIR/${SAMPLE}_checkv_quality_summary.tsv"
        
        # AMR & Virulence
        [[ -f "$RESULT_DIR/amr_virulence/${SAMPLE}_card.tsv" ]] && cp -p "$RESULT_DIR/amr_virulence/${SAMPLE}_card.tsv" "$DATA_OUTDIR/"
        [[ -f "$RESULT_DIR/amr_virulence/${SAMPLE}_resfinder.tsv" ]] && cp -p "$RESULT_DIR/amr_virulence/${SAMPLE}_resfinder.tsv" "$DATA_OUTDIR/"
        [[ -f "$RESULT_DIR/amr_virulence/${SAMPLE}_vfdb.tsv" ]] && cp -p "$RESULT_DIR/amr_virulence/${SAMPLE}_vfdb.tsv" "$DATA_OUTDIR/"
        [[ -f "$RESULT_DIR/amr_virulence/${SAMPLE}_rgi.txt" ]] && cp -p "$RESULT_DIR/amr_virulence/${SAMPLE}_rgi.txt" "$DATA_OUTDIR/"
    fi
done

echo "[SUCCESS] Data copied."
echo "-------------------------------------------------------"

# --- 4. EXECUTION OF R VISUALIZATION SCRIPTS ---

# Loop over all bins to run visualizations in parallel
for fasta in "$RESULT_DIR/collected_assemblies"/*.fasta; do
    if [[ -f "$fasta" && ! "$fasta" =~ _original\.fasta$ ]]; then
        SAMPLE=$(basename "$fasta" .fasta)
        
        (
            echo "=== Processing Visualizations for: $SAMPLE ==="
            
            # A. BUSCO Plot
            BUSCO_JSON=$(find "$RESULT_DIR/busco/${SAMPLE}_busco" -name "short_summary.specific.*.${SAMPLE}_busco.json" | head -n 1)
            if [[ -f "$BUSCO_JSON" ]]; then
                echo "  -> Running BUSCO visualization for $SAMPLE..."
                pixi run -e r-drawing Rscript "$VIS_SCRIPT_DIR/busco.R" \
                    --input "$BUSCO_JSON" \
                    --output "$BASE_OUTDIR/01_BUSCO/${SAMPLE}_BUSCO_Report" \
                    --format "html,pdf"
            fi
            
            # B. EggNOG & KEGG Report
            EGGNOG_ANNOT="$RESULT_DIR/eggnog/${SAMPLE}.emapper.annotations"
            if [[ -f "$EGGNOG_ANNOT" ]]; then
                echo "  -> Running EggNOG/KEGG visualization for $SAMPLE..."
                mkdir -p "$BASE_OUTDIR/02_Functional/${SAMPLE}"
                pixi run -e r-drawing Rscript "$VIS_SCRIPT_DIR/eggnog.R" \
                    --eggnog "$EGGNOG_ANNOT" \
                    --outdir "$BASE_OUTDIR/02_Functional/${SAMPLE}"
            fi
            
            # C. Bakta Report
            BAKTA_TSV="$RESULT_DIR/annotation/${SAMPLE}/${SAMPLE}.tsv"
            BAKTA_TXT="$RESULT_DIR/annotation/${SAMPLE}/${SAMPLE}.txt"
            if [[ -f "$BAKTA_TSV" ]]; then
                echo "  -> Running Bakta visualization for $SAMPLE..."
                pixi run -e r-drawing Rscript "$VIS_SCRIPT_DIR/batka.R" \
                    --input "$BAKTA_TSV" \
                    --summary "$BAKTA_TXT" \
                    --output "$BASE_OUTDIR/03_Bakta/${SAMPLE}_bakta_report.html"
            fi

            # C.3. geNomad & CheckV Tables (Plotly)
            echo "  -> Running MGE tables visualization for $SAMPLE..."
            mkdir -p "$BASE_OUTDIR/08_MGEs/$SAMPLE"
            
            PLASMID_TSV="$RESULT_DIR/genomad/${SAMPLE}/${SAMPLE}_summary/${SAMPLE}_plasmid_summary.tsv"
            VIRUS_TSV="$RESULT_DIR/genomad/${SAMPLE}/${SAMPLE}_summary/${SAMPLE}_virus_summary.tsv"
            CHECKV_TSV="$RESULT_DIR/checkv/${SAMPLE}/quality_summary.tsv"
            
            pixi run -e r-drawing Rscript "$VIS_SCRIPT_DIR/mge_table.R" \
                -i "$PLASMID_TSV" \
                -o "$BASE_OUTDIR/08_MGEs/$SAMPLE/plasmid_table.html" \
                -t "Plasmid Summary (geNomad)"
                
            pixi run -e r-drawing Rscript "$VIS_SCRIPT_DIR/mge_table.R" \
                -i "$VIRUS_TSV" \
                -o "$BASE_OUTDIR/08_MGEs/$SAMPLE/virus_table.html" \
                -t "Virus Summary (geNomad)"
                
            pixi run -e r-drawing Rscript "$VIS_SCRIPT_DIR/mge_table.R" \
                -i "$CHECKV_TSV" \
                -o "$BASE_OUTDIR/08_MGEs/$SAMPLE/checkv_table.html" \
                -t "Virus Quality (CheckV)"

            # C.4. AMR & Virulence Tables
            echo "  -> Running AMR & Virulence tables visualization for $SAMPLE..."
            mkdir -p "$BASE_OUTDIR/06_AMR_Virulence/$SAMPLE"
            
            pixi run -e r-drawing Rscript "$VIS_SCRIPT_DIR/mge_table.R" \
                -i "$RESULT_DIR/amr_virulence/${SAMPLE}_card.tsv" \
                -o "$BASE_OUTDIR/06_AMR_Virulence/$SAMPLE/card_table.html" \
                -t "CARD Database (Antibiotic Resistance) - $SAMPLE"
                
            pixi run -e r-drawing Rscript "$VIS_SCRIPT_DIR/mge_table.R" \
                -i "$RESULT_DIR/amr_virulence/${SAMPLE}_resfinder.tsv" \
                -o "$BASE_OUTDIR/06_AMR_Virulence/$SAMPLE/resfinder_table.html" \
                -t "ResFinder Database (Antibiotic Resistance) - $SAMPLE"
                
            pixi run -e r-drawing Rscript "$VIS_SCRIPT_DIR/mge_table.R" \
                -i "$RESULT_DIR/amr_virulence/${SAMPLE}_vfdb.tsv" \
                -o "$BASE_OUTDIR/06_AMR_Virulence/$SAMPLE/vfdb_table.html" \
                -t "VFDB Database (Virulence Factors) - $SAMPLE"
                
            pixi run -e r-drawing Rscript "$VIS_SCRIPT_DIR/mge_table.R" \
                -i "$RESULT_DIR/amr_virulence/${SAMPLE}_rgi.txt" \
                -o "$BASE_OUTDIR/06_AMR_Virulence/$SAMPLE/rgi_table.html" \
                -t "RGI CARD Database (Antibiotic Resistance) - $SAMPLE"
        ) &
    fi
done

# Wait for all background sample drawing processes to finish
wait

echo "Running KEGG Pathway comparison heatmap..."
pixi run -e r-drawing Rscript "$VIS_SCRIPT_DIR/kegg_heatmap.R" \
    -i "$BASE_OUTDIR/02_Functional" \
    -o "$BASE_OUTDIR/02_Functional/kegg_pathway_heatmap.html"

# C.2. Run Kraken2 Abundance Report (Only once, covers all samples)
echo "Running Kraken2 Abundance visualization..."
pixi run -e r-drawing Rscript "$VIS_SCRIPT_DIR/kraken_vis.R" \
    -i "$RESULT_DIR" \
    -o "$BASE_OUTDIR/00_QC"

# D. Run Assembly Taxonomy Report (Only once, covers all bins)
if [[ -f "$CHECKM_TSV" && -f "$GTDB_TSV" ]]; then
    echo "Running Assembly Taxonomy visualization..."
    pixi run -e r-drawing Rscript "$VIS_SCRIPT_DIR/assembly_tax.R" \
        --checkm "$CHECKM_TSV" \
        --gtdbtk "$GTDB_TSV" \
        --out "$BASE_OUTDIR/04_Taxonomy/taxonomy_report"
fi

# E. Run Phylogenetic Tree Visualization (Only once)
FIRST_ANNOTATED_TREE=$(find "$RESULT_DIR/tree" -name "*_annotated_tree.treefile" | head -n 1)
if [[ -f "$FIRST_ANNOTATED_TREE" ]]; then
    echo "Running Phylogenetic Tree visualization..."
    cp -p "$FIRST_ANNOTATED_TREE" "$DATA_OUTDIR/"
    pixi run -e r-drawing Rscript "$VIS_SCRIPT_DIR/tree.R" \
        -i "$FIRST_ANNOTATED_TREE" \
        -g "$GTDB_TSV" \
        -o "$BASE_OUTDIR/05_Phylogeny/${BATCH_NAME}_final_publication_tree"
fi

# F. Copy Secondary Metabolites Reports (antiSMASH & BAGEL4)
echo "Archiving antiSMASH and BAGEL4 reports..."
if [[ -d "$RESULT_DIR/secondary_metabolites/antismash" ]]; then
    mkdir -p "$BASE_OUTDIR/07_Secondary_Metabolites/antismash"
    cp -r "$RESULT_DIR/secondary_metabolites/antismash"/* "$BASE_OUTDIR/07_Secondary_Metabolites/antismash/"
fi
if [[ -d "$RESULT_DIR/secondary_metabolites/bagel4" ]]; then
    mkdir -p "$BASE_OUTDIR/07_Secondary_Metabolites/bagel4"
    cp -r "$RESULT_DIR/secondary_metabolites/bagel4"/* "$BASE_OUTDIR/07_Secondary_Metabolites/bagel4/"
fi

echo "======================================================="
echo "Genomic Visualizations Complete! Outputs located in $BASE_OUTDIR"
echo "======================================================="
touch "$BASE_OUTDIR/draw_success.flag"