#!/bin/bash
#SBATCH --job-name=custom_tree
#SBATCH --output=log/tree_%j.out
#SBATCH --error=log/tree_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --mem=256G

# --- Load Central Configuration ---
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

FIRST_GENOME_FILE=$(ls -1 "$RESULT_DIR/collected_assemblies"/*.fasta | grep -v "_original" | head -n 1)
FIRST_SAMPLE=$(basename "$FIRST_GENOME_FILE" .fasta)
INPUT_LIST="$RESULT_DIR/tree/selected_taxa_${FIRST_SAMPLE}.txt"
WORK_DIR="$RESULT_DIR/tree"
THREADS=48

echo "=== 1. Preparing Working Directory ==="
mkdir -p "$WORK_DIR/genomes"
mkdir -p "$WORK_DIR/gtdbtk_out"

# Copy all local assemblies from collected_assemblies/ to genomes/ for GTDB-Tk mapping
echo "Copying local assemblies to $WORK_DIR/genomes/..."
for fasta in "$RESULT_DIR/collected_assemblies"/*.fasta; do
    if [[ -f "$fasta" && ! "$fasta" =~ _original\.fasta$ ]]; then
        cp "$fasta" "$WORK_DIR/genomes/$(basename "$fasta")"
    fi
done

echo "=== 2. Preparing Selected Taxa ==="
if [ ! -s "$INPUT_LIST" ]; then
    echo " -> Generating selected taxa list dynamically using python.find_tax.py..."
    GTDB_CLASSIFY_TREE="$RESULT_DIR/gtdbtk_cleaned/classify/gtdbtk.bac120.classify.tree.1.tree"
    if [ ! -f "$GTDB_CLASSIFY_TREE" ]; then
        GTDB_CLASSIFY_TREE="$RESULT_DIR/gtdbtk/classify/gtdbtk.bac120.classify.tree.1.tree"
    fi
    if [ -f "$GTDB_CLASSIFY_TREE" ]; then
        mkdir -p "$(dirname "$INPUT_LIST")"
        pixi run -e tree python3 "$SCRIPT_DIR/python.find_tax.py" \
            -i "$GTDB_CLASSIFY_TREE" \
            -t "$FIRST_SAMPLE" \
            -o "$INPUT_LIST" \
            -n 20
    else
        echo "ERROR: GTDB-Tk classification tree not found in either gtdbtk_cleaned or gtdbtk."
        echo "Please ensure step 8 (CheckM & GTDB-Tk) has run successfully."
        exit 1
    fi
fi

echo "=== 3. Cleaning NCBI Accessions ==="
if [ -s "$WORK_DIR/clean_accessions.txt" ]; then
    echo " -> Skipping: clean_accessions.txt already exists."
else
    # Remove FIRST_SAMPLE and strip 'RS_' and 'GB_' prefixes
    if [ -f "$INPUT_LIST" ]; then
        grep -v "^${FIRST_SAMPLE}" "$INPUT_LIST" | sed -e 's/^RS_//' -e 's/^GB_//' > "$WORK_DIR/clean_accessions.txt"
    else
        echo "ERROR: Input list not found at $INPUT_LIST. Cannot proceed."
        exit 1
    fi
fi

echo "=== 3. Downloading Reference Genomes ==="
if unzip -tq "$WORK_DIR/ncbi_dataset.zip" &> /dev/null; then
    echo " -> Skipping: Valid ncbi_dataset.zip already exists."
else
    MAX_RETRIES=5
    count=0
    download_success=false

    while [ $count -lt $MAX_RETRIES ]; do
        echo "Download attempt $((count+1)) of $MAX_RETRIES..."
        
        pixi run -e tree datasets download genome accession \
            --inputfile "$WORK_DIR/clean_accessions.txt" \
            --include genome \
            --filename "$WORK_DIR/ncbi_dataset.zip"
        
        if unzip -tq "$WORK_DIR/ncbi_dataset.zip" &> /dev/null; then
            echo "Download successful and zip archive is valid!"
            download_success=true
            break
        else
            echo "WARNING: Download failed or zip is corrupted. Retrying in 10 seconds..."
            rm -f "$WORK_DIR/ncbi_dataset.zip"
            sleep 10
            count=$((count+1))
        fi
    done

    if [ "$download_success" = false ]; then
        echo "FATAL ERROR: Failed to download valid genomes from NCBI after $MAX_RETRIES attempts."
        exit 1
    fi
fi

echo "=== 4. Extracting and Standardizing Genomes ==="
# Check if we already have reference genomes extracted (counting files starting with myref_)
if [ $(ls -1 "$WORK_DIR/genomes/myref_*.fasta" 2>/dev/null | wc -l) -gt 0 ]; then
    echo " -> Skipping: Reference genomes are already extracted in genomes/ folder."
else
    mkdir -p "$WORK_DIR/extracted"
    unzip -q "$WORK_DIR/ncbi_dataset.zip" -d "$WORK_DIR/extracted"
    while read -r acc; do
        fna_file=$(find "$WORK_DIR/extracted/ncbi_dataset/data/$acc" -name "*.fna" | head -n 1)
        if [[ ! -z "$fna_file" ]]; then
            cp "$fna_file" "$WORK_DIR/genomes/myref_${acc}.fasta"
        fi
    done < "$WORK_DIR/clean_accessions.txt"
    # Clean up extraction temp folder to save space
    rm -rf "$WORK_DIR/extracted"
fi

echo "=== 5. Extracting Marker Genes (GTDB-Tk) ==="
if [ -d "$WORK_DIR/gtdbtk_out/identify" ]; then
    echo " -> Skipping: GTDB-Tk identify directory already exists."
else
    pixi run -e taxonomy gtdbtk identify \
        --genome_dir "$WORK_DIR/genomes" \
        --out_dir "$WORK_DIR/gtdbtk_out" \
        --extension fasta \
        --force \
        --cpus "$THREADS"
fi

echo "=== 6. Aligning Marker Genes (GTDB-Tk) ==="
if [ -d "$WORK_DIR/gtdbtk_out/align" ]; then
    echo " -> Skipping: GTDB-Tk align directory already exists."
else
    pixi run -e taxonomy gtdbtk align \
        --identify_dir "$WORK_DIR/gtdbtk_out" \
        --out_dir "$WORK_DIR/gtdbtk_out" \
        --cpus "$THREADS"
fi

echo "=== 7. Building Tree (IQ-TREE) ==="
if [ -f "$WORK_DIR/${FIRST_SAMPLE}_custom_tree.treefile" ]; then
    echo " -> Skipping: IQ-TREE output already exists."
else
    # Find aligned user msa file
    msa_file=$(find "$WORK_DIR/gtdbtk_out/align" -name "*user_msa.fasta.gz" | head -n 1)
    if [[ -z "$msa_file" ]]; then
        msa_file="$WORK_DIR/gtdbtk_out/align/gtdbtk.bac120.user_msa.fasta.gz"
    fi
    
    pixi run -e tree iqtree \
        -s "$msa_file" \
        -m TEST \
        -B 1000 \
        -T "$THREADS" \
        --prefix "$WORK_DIR/${FIRST_SAMPLE}_custom_tree"
fi

echo "=== 8. Adding Species Names to the Tree ==="
if [ -f "$WORK_DIR/${FIRST_SAMPLE}_annotated_tree.treefile" ]; then
    echo " -> Skipping: Annotated tree already exists."
else
    # Save the raw JSON output directly, ignoring the broken dataformat tool
    pixi run -e tree datasets summary genome accession \
        --inputfile "$WORK_DIR/clean_accessions.txt" > "$WORK_DIR/taxonomy_summary.json"

    # Use Python to safely parse the JSON and rename the tree branches
    pixi run -e default python3 -c '
import sys
import json

tree_path = sys.argv[1]
json_path = sys.argv[2]
out_path = sys.argv[3]

mapping = {}
try:
    with open(json_path, "r") as f:
        data = json.load(f)
        
        for report in data.get("reports", []):
            acc = report.get("accession")
            if not acc:
                continue
            
            # Catch both naming conventions NCBI uses just to be safe
            org_info = report.get("organism", {})
            org_name = org_info.get("organism_name") or org_info.get("organismName") or "Unknown_Species"
            
            # Clean up the organism name for Newick format
            clean_name = org_name.replace(" ", "_").replace("(", "").replace(")", "").replace(":", "").replace("/", "_")
            mapping[acc] = f"{clean_name}_{acc}"
            
except Exception as e:
    print(f"WARNING: Could not parse NCBI JSON: {e}. Tree will remain unannotated.")
    sys.exit(0)

with open(tree_path, "r") as f:
    tree_text = f.read()

# Replace the plain accessions (including the myref_ tag) with the new descriptive names
for acc, new_name in mapping.items():
    tree_text = tree_text.replace(f"myref_{acc}", new_name)

with open(out_path, "w") as f:
    f.write(tree_text)
' "$WORK_DIR/${FIRST_SAMPLE}_custom_tree.treefile" "$WORK_DIR/taxonomy_summary.json" "$WORK_DIR/${FIRST_SAMPLE}_annotated_tree.treefile"
fi

echo "=== Pipeline Complete! ==="
echo "Your fully annotated tree is here: $WORK_DIR/${FIRST_SAMPLE}_annotated_tree.treefile"
touch "$WORK_DIR/tree_success.flag"