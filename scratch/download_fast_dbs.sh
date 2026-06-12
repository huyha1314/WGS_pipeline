#!/bin/bash
set -e

DB_DIR="/worker_data1/huyha/db/antismash"
mkdir -p "$DB_DIR"

echo "--> Starting fast database downloads into $DB_DIR..."

# Function to download using aria2c
download_fast() {
    local url=$1
    local dest_dir=$2
    local filename=$3
    mkdir -p "$dest_dir"
    echo "Downloading $url to $dest_dir/$filename..."
    pixi run aria2c -c -x 16 -s 16 -j 16 -d "$dest_dir" -o "$filename" "$url"
}

# 1. MITE
download_fast "https://dl.secondarymetabolites.org/releases/mite/mite_1.3.tar.xz" "$DB_DIR/mite" "mite.tar.xz"
cd "$DB_DIR/mite"
tar -xvf mite.tar.xz
rm -f mite.tar.xz
cd - > /dev/null

# 2. Resfam
download_fast "https://dl.secondarymetabolites.org/releases/resfams/Resfams.hmm.gz" "$DB_DIR/resfam" "Resfams.hmm.gz"
cd "$DB_DIR/resfam"
gunzip -f Resfams.hmm.gz
cd - > /dev/null

# 3. TIGRFam
download_fast "https://dl.secondarymetabolites.org/releases/tigrfam/TIGRFam.hmm.gz" "$DB_DIR/tigrfam" "TIGRFam.hmm.gz"
cd "$DB_DIR/tigrfam"
gunzip -f TIGRFam.hmm.gz
cd - > /dev/null

# 4. ClusterBlast
download_fast "https://dl.secondarymetabolites.org/releases/clusterblast/clusterblast_4.0.tar.xz" "$DB_DIR" "clusterblast_4.0.tar.xz"
cd "$DB_DIR"
tar -xvf clusterblast_4.0.tar.xz
rm -f clusterblast_4.0.tar.xz
cd - > /dev/null

# 5. KnownClusterBlast
download_fast "https://dl.secondarymetabolites.org/releases/knownclusterblast/kcb_4.0.tar.xz" "$DB_DIR/knownclusterblast" "kcb_4.0.tar.xz"
cd "$DB_DIR/knownclusterblast"
tar -xvf kcb_4.0.tar.xz
rm -f kcb_4.0.tar.xz
cd - > /dev/null

# 6. ClusterCompare (MIBiG)
download_fast "https://dl.secondarymetabolites.org/releases/clustercompare/cc_mibig_4.0.tar.xz" "$DB_DIR/clustercompare/mibig" "cc_mibig_4.0.tar.xz"
cd "$DB_DIR/clustercompare/mibig"
tar -xvf cc_mibig_4.0.tar.xz
rm -f cc_mibig_4.0.tar.xz
cd - > /dev/null

# 7. CompaRiPPson (ASDB & MIBiG)
download_fast "https://dl.secondarymetabolites.org/releases/comparippson/asdb_4.0.tar.xz" "$DB_DIR/comparippson/asdb" "asdb_4.0.tar.xz"
cd "$DB_DIR/comparippson/asdb"
tar -xvf asdb_4.0.tar.xz
rm -f asdb_4.0.tar.xz
cd - > /dev/null

download_fast "https://dl.secondarymetabolites.org/releases/comparippson/mibig_4.0.tar.xz" "$DB_DIR/comparippson/mibig" "mibig_4.0.tar.xz"
cd "$DB_DIR/comparippson/mibig"
tar -xvf mibig_4.0.tar.xz
rm -f mibig_4.0.tar.xz
cd - > /dev/null

# 8. Stachelhaus
download_fast "https://dl.secondarymetabolites.org/releases/stachelhaus/1.1/signatures.tsv.xz" "$DB_DIR/nrps_pks/stachelhaus/1.1" "signatures.tsv.xz"
cd "$DB_DIR/nrps_pks/stachelhaus/1.1"
xz -d -f signatures.tsv.xz
cd - > /dev/null

# 9. NRPS SVM
download_fast "https://dl.secondarymetabolites.org/releases/nrps_svm/2.0/models.tar.xz" "$DB_DIR/nrps_pks/svm/2.0" "models.tar.xz"
cd "$DB_DIR/nrps_pks/svm/2.0"
tar -xvf models.tar.xz
rm -f models.tar.xz
cd - > /dev/null

# 10. TransATor
download_fast "https://dl.secondarymetabolites.org/releases/transATor/transATor_2023.02.23.tar.xz" "$DB_DIR/nrps_pks/transATor/2023.02.23" "transATor_2023.02.23.tar.xz"
cd "$DB_DIR/nrps_pks/transATor/2023.02.23"
tar -xvf transATor_2023.02.23.tar.xz
rm -f transATor_2023.02.23.tar.xz
cd - > /dev/null

echo "--> All secondary metabolite databases (except Pfam-A) have been successfully downloaded and extracted."
