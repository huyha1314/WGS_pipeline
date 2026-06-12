#!/bin/bash
#SBATCH --job-name=bin_cleanup
#SBATCH --output=log/cleanup_%j.out
#SBATCH --error=log/cleanup_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G

# --- Define Target Directory ---
TARGET_DIR="/worker_data2/huyha/precisiongene/suran_wgs/results/collected_assemblies"
BACKUP_DIR="${TARGET_DIR}/removed_junk_bins"

mkdir -p "$BACKUP_DIR"

echo "====================================================="
echo "        METAGENOMIC BIN REFINEMENT & CLEANUP         "
echo "====================================================="
echo "Target Workspace: $TARGET_DIR"
echo "Backup Junk Dir:  $BACKUP_DIR"
echo "====================================================="

# Function to safely migrate junk bins instead of destructive deletion
remove_bin() {
    local bin_name="$1"
    if [[ -f "${TARGET_DIR}/${bin_name}" ]]; then
        echo "--> Removing/Archiving: $bin_name"
        mv "${TARGET_DIR}/${bin_name}" "$BACKUP_DIR/"
    fi
}

# ==============================================================================
# SAMPLE 243 CLEANUP: Keeping only the pristine MetaBAT2 bin (243_bin.2.fasta)
# ==============================================================================
echo "Processing Sample 243..."
remove_bin "243.fasta"              # Contaminated raw assembly
remove_bin "243_bin.1.fasta"        # Questionable domain warning
remove_bin "243_bin.3.fasta"        # Broken fragment
remove_bin "243_maxbin.001.fasta"   # Redundant/Inferior resolution
remove_bin "243_maxbin.002.fasta"   # Extreme 45% contamination match

# ==============================================================================
# SAMPLE 27 CLEANUP: Keeping only the unified MaxBin2 bin (27_maxbin.002.fasta)
# ==============================================================================
echo "Processing Sample 27..."
remove_bin "27.fasta"               # Raw unbinned file
remove_bin "27_bin.1.fasta"         # Over-binned shard
remove_bin "27_bin.2.fasta"         # Over-binned shard
remove_bin "27_bin.3.fasta"         # Over-binned shard
remove_bin "27_bin.4.fasta"         # Over-binned shard
remove_bin "27_maxbin.001.fasta"    # Lower completeness representative

# ==============================================================================
# SAMPLE 85 CLEANUP: Keeping MaxBin2 targets (.001 for Lysini, .002 for Lacto)
# ==============================================================================
echo "Processing Sample 85..."
remove_bin "85.fasta"               # Heavily mixed >100% contaminated assembly
remove_bin "85_bin.1.fasta"         # Removing all broken MetaBAT2 fragments
remove_bin "85_bin.2.fasta"
remove_bin "85_bin.3.fasta"
remove_bin "85_bin.4.fasta"
remove_bin "85_bin.5.fasta"
remove_bin "85_bin.6.fasta"
remove_bin "85_bin.7.fasta"
remove_bin "85_bin.8.fasta"         # Complete failure (8.9% MSA amino acids)
remove_bin "85_bin.9.fasta"         # MetaBAT2 clone of MaxBin target

# ==============================================================================
# SAMPLE TC3 CLEANUP: Keeping the unbroken original assembly (TC3.fasta)
# ==============================================================================
echo "Processing Sample TC3..."
# CRITICAL UPDATE: We now keep TC3.fasta because it is an unbroken, pure genome!
remove_bin "TC3_bin.1.fasta"        # Redundant MetaBAT2 split
remove_bin "TC3_bin.2.fasta"        # Redundant MetaBAT2 split
remove_bin "TC3_maxbin.001.fasta"   # Redundant MaxBin2 slice 1
remove_bin "TC3_maxbin.002.fasta"   # Redundant MaxBin2 slice 2

echo "====================================================="
echo "Cleanup completed successfully!"
echo "Pristine assemblies remaining in active pool:"
ls -F "$TARGET_DIR" | grep -v '/'
echo "====================================================="