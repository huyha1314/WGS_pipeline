#!/bin/bash
# ==============================================================================
#             AUTOMATED POST-DOWNLOAD PIPELINE COMPLETION SCRIPT
# ==============================================================================
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/../config.sh"

echo "================================================================="
echo "   Starting pipeline completion manager..."
echo "   Workdir: $RESULT_DIR"
echo "================================================================="

# 1. Wait for fast databases download to complete
echo "--> Waiting for background fast databases downloader script to complete..."
while ps -ef | grep download_fast_dbs.sh | grep -v grep >/dev/null; do
    sleep 30
done
echo "--> Fast databases download complete."

# 2. Wait for Pfam-A.hmm.gz to complete
echo "--> Waiting for Pfam-A.hmm.gz download to complete..."
PFAM_FILE="/worker_data1/huyha/db/antismash/pfam/35.0/Pfam-A.hmm.gz"
PFAM_ARIA2="${PFAM_FILE}.aria2"

while :; do
    if [ -f "$PFAM_FILE" ] && [ ! -f "$PFAM_ARIA2" ]; then
        # Check if file has some minimum size
        size=$(stat -c%s "$PFAM_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt 200000000 ]; then
            break
        fi
    fi
    sleep 30
done
echo "--> Pfam-A.hmm.gz download complete (size: $size bytes)."

# 3. Run antiSMASH database builder/downloader to checksum and verify everything
echo "--> Running antiSMASH database downloader to verify files and build indexes..."
if ! pixi run -e secondary-metabolites download-antismash-databases --database-dir "$ANTISMASH_DB_DIR"; then
    echo "ERROR: antiSMASH database verification/indexing failed."
    exit 1
fi
echo "--> antiSMASH databases successfully verified and indexed."

# 4. Clean up failed secondary metabolite outputs to ensure a clean run
echo "--> Cleaning up partial/failed secondary metabolite directories..."
rm -rf "$RESULT_DIR/secondary_metabolites/antismash"
rm -rf "$RESULT_DIR/secondary_metabolites/bagel4"
rm -f "$RESULT_DIR/secondary_metabolites/secondary_metabolites_success.flag"

# 5. Run Secondary Metabolites analysis script
echo "--> Running secondary metabolites analysis..."
if ! bash script/10.7.secondary_metabolites.sh; then
    echo "ERROR: Secondary metabolites analysis failed."
    exit 1
fi
echo "--> Secondary metabolites analysis completed successfully."

# 6. Render final report
echo "--> Rendering final HTML report..."
if ! bash script/14.render_report.sh; then
    echo "ERROR: Report rendering failed."
    exit 1
fi

echo "================================================================="
echo "   Pipeline completion automated run finished successfully!"
echo "   Final report generated at results/rp/14.rp.html"
echo "================================================================="
