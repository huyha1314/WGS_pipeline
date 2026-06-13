#!/bin/bash
# Load Central Configuration
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

FIRST_SAMPLE=$(tail -n +2 "$INPUT_SHEET" | head -n 1 | cut -d$'\t' -f1)

mkdir -p "$RESULT_DIR/tree"
pixi run --manifest-path "$WORKDIR/pixi.toml" -e tree python3 "$SCRIPT_DIR/python.find_tax.py" \
  -i "$RESULT_DIR/gtdbtk_cleaned/classify/gtdbtk.bac120.classify.tree.1.tree" \
  -t "$FIRST_SAMPLE" \
  -o "$RESULT_DIR/tree/selected_taxa_${FIRST_SAMPLE}.txt" \
  -n 20