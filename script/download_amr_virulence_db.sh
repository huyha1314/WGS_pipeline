#!/bin/bash
# ==============================================================================
#                 DOWNLOAD AMR & VIRULENCE DATABASES (ABRICATE)
# ==============================================================================
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

# Ensure output database directory exists
mkdir -p "$ABRICATE_DB_DIR"

echo "====================================================================="
echo "   DOWNLOADING AMR AND VIRULENCE DATABASES FOR ABRICATE"
echo "   Target Directory: $ABRICATE_DB_DIR"
echo "====================================================================="

# Download CARD
echo "--> Downloading CARD database..."
if ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e amr-virulence abricate-get_db --db card --dbdir "$ABRICATE_DB_DIR" --force; then
    echo "ERROR: Failed to download CARD database."
    exit 1
fi

# Download ResFinder
echo "--> Downloading ResFinder database..."
if ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e amr-virulence abricate-get_db --db resfinder --dbdir "$ABRICATE_DB_DIR" --force; then
    echo "ERROR: Failed to download ResFinder database."
    exit 1
fi

# Download VFDB
echo "--> Downloading VFDB database..."
if ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e amr-virulence abricate-get_db --db vfdb --dbdir "$ABRICATE_DB_DIR" --force; then
    echo "ERROR: Failed to download VFDB database."
    exit 1
fi

# --- RGI Database Setup ---
echo ""
echo "====================================================================="
echo "   DOWNLOADING CARD DATABASE FOR RGI"
echo "   Target Directory: $RGI_DB_DIR"
echo "====================================================================="
mkdir -p "$RGI_DB_DIR"
CARD_URL="https://card.mcmaster.ca/latest/data"

echo "--> Downloading CARD data archive..."
if command -v aria2c &> /dev/null; then
    if ! aria2c -c -x 8 -s 8 -d "$RGI_DB_DIR" -o card_data.tar.bz2 "$CARD_URL"; then
        echo "aria2c failed, trying wget..."
        wget -c -O "$RGI_DB_DIR/card_data.tar.bz2" "$CARD_URL"
    fi
else
    echo "aria2c not found, trying wget..."
    if ! wget -c -O "$RGI_DB_DIR/card_data.tar.bz2" "$CARD_URL"; then
        echo "wget failed, trying curl..."
        curl -L -o "$RGI_DB_DIR/card_data.tar.bz2" "$CARD_URL"
    fi
fi

echo "--> Extracting card.json..."
tar -xjf "$RGI_DB_DIR/card_data.tar.bz2" -C "$RGI_DB_DIR" card.json

echo "--> Loading CARD database into RGI..."
if ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e rgi rgi load --card_json "$RGI_DB_DIR/card.json"; then
    echo "ERROR: Failed to load CARD database into RGI."
    exit 1
fi

echo ""
echo "=== Setup complete! Available databases in ABRicate: ==="
pixi run --manifest-path "$WORKDIR/pixi.toml" -e amr-virulence abricate --datadir "$ABRICATE_DB_DIR" --list
echo ""
echo "=== Setup complete! RGI CARD database version: ==="
pixi run --manifest-path "$WORKDIR/pixi.toml" -e rgi rgi database --version
echo "====================================================================="
