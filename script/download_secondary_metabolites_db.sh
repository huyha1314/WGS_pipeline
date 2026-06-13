#!/bin/bash
# ==============================================================================
#                 DOWNLOAD SECONDARY METABOLITES DATABASES
# ==============================================================================
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

echo "====================================================================="
echo "   DOWNLOADING SECONDARY METABOLITE DATABASES (ANTISMASH & BAGEL4)"
echo "====================================================================="

# --- 1. antiSMASH Databases ---
echo "--> Setting up antiSMASH Database..."
mkdir -p "$ANTISMASH_DB_DIR"
if ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e secondary-metabolites download-antismash-databases --database-dir "$ANTISMASH_DB_DIR"; then
    echo "WARNING: antiSMASH automatic database downloader failed or skipped."
    echo "We will try running antiSMASH with internal checks later."
fi

# --- 2. BAGEL4 Codebase and Databases ---
echo "--> Setting up BAGEL4 standalone codebase in $BAGEL4_DIR..."
mkdir -p "$BAGEL4_DIR"

if [ ! -d "$BAGEL4_DIR/.git" ]; then
    echo "Cloning BAGEL4 from GitHub..."
    if ! git clone https://github.com/annejong/BAGEL4.git "$BAGEL4_DIR"; then
        echo "ERROR: Failed to clone BAGEL4 repository."
        exit 1
    fi
else
    echo "BAGEL4 repository already exists. Updating..."
    cd "$BAGEL4_DIR" && git pull && cd - > /dev/null
fi

# Set up BAGEL4 database directory
mkdir -p "$BAGEL4_DB_DIR"

echo "--> Downloading Pfam-A database for BAGEL4..."
PFAM_URL="https://ftp.ebi.ac.uk/pub/databases/Pfam/releases/Pfam31.0/Pfam-A.hmm.gz"
PFAM_HMM="$BAGEL4_DB_DIR/Pfam-A.hmm"

if [ ! -f "$PFAM_HMM" ]; then
    echo "Downloading Pfam-A.hmm.gz from EBI..."
    if command -v aria2c &> /dev/null; then
        echo "Using aria2c for download..."
        if ! aria2c -c -x 1 -s 1 -j 1 -d "$BAGEL4_DB_DIR" -o Pfam-A.hmm.gz "$PFAM_URL"; then
            echo "aria2c failed, trying curl..."
            if ! curl -L -C - -o "$BAGEL4_DB_DIR/Pfam-A.hmm.gz" "$PFAM_URL"; then
                echo "ERROR: Failed to download Pfam-A database."
                exit 1
            fi
        fi
    else
        echo "aria2c not found, trying wget..."
        if ! wget -c -O "$BAGEL4_DB_DIR/Pfam-A.hmm.gz" "$PFAM_URL"; then
            echo "wget failed, trying curl..."
            if ! curl -L -C - -o "$BAGEL4_DB_DIR/Pfam-A.hmm.gz" "$PFAM_URL"; then
                echo "ERROR: Failed to download Pfam-A database."
                exit 1
            fi
        fi
    fi
    echo "Extracting Pfam-A.hmm.gz..."
    gunzip -f "$BAGEL4_DB_DIR/Pfam-A.hmm.gz"
fi

if [ ! -f "${PFAM_HMM}.h3m" ]; then
    echo "Indexing Pfam-A.hmm with hmmpress..."
    if ! pixi run --manifest-path "$WORKDIR/pixi.toml" -e secondary-metabolites hmmpress -f "$PFAM_HMM"; then
        echo "ERROR: Failed to run hmmpress on Pfam-A.hmm."
        exit 1
    fi
fi

# --- 3. Dynamically Generate BAGEL4 configuration ---
echo "--> Generating bagel4.conf..."

# Resolve executable paths inside secondary-metabolites environment
BLASTALL_PATH=$(pixi run --manifest-path "$WORKDIR/pixi.toml" -e secondary-metabolites which blastall 2>/dev/null || echo "blastall")
FORMATDB_PATH=$(pixi run --manifest-path "$WORKDIR/pixi.toml" -e secondary-metabolites which formatdb 2>/dev/null || echo "formatdb")
HMMSEARCH_PATH=$(pixi run --manifest-path "$WORKDIR/pixi.toml" -e secondary-metabolites which hmmsearch 2>/dev/null || echo "hmmsearch")
HMMPRESS_PATH=$(pixi run --manifest-path "$WORKDIR/pixi.toml" -e secondary-metabolites which hmmpress 2>/dev/null || echo "hmmpress")
GLIMMER_PATH=$(pixi run --manifest-path "$WORKDIR/pixi.toml" -e secondary-metabolites which glimmer3 2>/dev/null || echo "glimmer3")
PFAMSCAN_PATH=$(pixi run --manifest-path "$WORKDIR/pixi.toml" -e secondary-metabolites which pfam_scan.pl 2>/dev/null || echo "pfam_scan.pl")

cat <<EOF > "$BAGEL4_DIR/bagel4.conf"
[query]
# Default parameters
cpu = 8

[database]
# Path to databases
pfam = $PFAM_HMM
bagel = $BAGEL4_DIR/db/bacteriocin.fa

[programs]
blastall = $BLASTALL_PATH
formatdb = $FORMATDB_PATH
hmmsearch = $HMMSEARCH_PATH
hmmpress = $HMMPRESS_PATH
glimmer3 = $GLIMMER_PATH
pfamscan = $PFAMSCAN_PATH
EOF

echo "BAGEL4 configuration successfully generated at $BAGEL4_DIR/bagel4.conf"
echo "====================================================================="
echo "   SECONDARY METABOLITES SETUP COMPLETED SUCCESSFULLY"
echo "====================================================================="
