#!/bin/bash
# ==============================================================================
#                 PRECISIONGENE WGS PIPELINE - DATABASE VERIFIER
# ==============================================================================
# This script sources config.sh and checks the existence and integrity of
# all reference databases required by the pipeline.

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Source configuration file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}[ERROR] Configuration file config.sh not found at: $CONFIG_FILE${NC}"
    exit 1
fi

source "$CONFIG_FILE"

echo -e "======================================================================"
echo -e "           PRECISIONGENE WGS PIPELINE - DATABASE STATUS CHECK"
echo -e "======================================================================"
echo -e "Base Database Directory: ${BLUE}$DB_DIR${NC}\n"

# Helper function to print status
print_status() {
    local db_name="$1"
    local status="$2"
    local details="$3"
    
    case "$status" in
        "READY")
            echo -e "[ ${GREEN}READY${NC} ] ${db_name}"
            ;;
        "EXTRACTING")
            echo -e "[ ${YELLOW}EXTRACTING${NC} ] ${db_name} - ${details}"
            ;;
        "DOWNLOADING")
            echo -e "[ ${YELLOW}DOWNLOADING${NC} ] ${db_name} - ${details}"
            ;;
        "INCOMPLETE")
            echo -e "[ ${RED}INCOMPLETE${NC} ] ${db_name} - ${details}"
            ;;
        "MISSING")
            echo -e "[ ${RED}MISSING${NC} ] ${db_name} - ${details}"
            ;;
    esac
}

# 1. GTDB-Tk
if [ -d "$GTDBTK_DATA_PATH" ]; then
    gzip_pid=$(pgrep -f "gzip -d" | head -n 1)
    if [ -n "$gzip_pid" ] && [ -d "/proc/$gzip_pid" ]; then
        total_sz=60806405195
        pos1=$(grep -s "pos:" "/proc/$gzip_pid/fdinfo/0" | awk '{print $2}')
        if [ -n "$pos1" ]; then
            sleep 1
            pos2=$(grep -s "pos:" "/proc/$gzip_pid/fdinfo/0" | awk '{print $2}')
            if [ -n "$pos2" ]; then
                speed=$(( pos2 - pos1 ))
                pct_int=$(( pos2 * 100 / total_sz ))
                pct_dec=$(( (pos2 * 10000 / total_sz) % 100 ))
                if [ $speed -gt 0 ]; then
                    remaining=$(( (total_sz - pos2) / speed ))
                    min=$(( remaining / 60 ))
                    sec=$(( remaining % 60 ))
                    time_str="${min}m ${sec}s remaining"
                else
                    time_str="finishing up"
                fi
                print_status "GTDB-Tk" "EXTRACTING" "Currently uncompressing gtdbtk_data.tar.gz (${pct_int}.${pct_dec}% complete, ${time_str})"
            else
                print_status "GTDB-Tk" "EXTRACTING" "Currently uncompressing gtdbtk_data.tar.gz"
            fi
        else
            print_status "GTDB-Tk" "EXTRACTING" "Currently uncompressing gtdbtk_data.tar.gz"
        fi
    elif pgrep -f "gtdbtk_data.tar.gz" > /dev/null; then
        print_status "GTDB-Tk" "EXTRACTING" "Currently uncompressing/extracting gtdbtk_data.tar.gz (please wait a few minutes)."
    elif [ -d "$GTDBTK_DATA_PATH/taxonomy" ] && { [ -d "$GTDBTK_DATA_PATH/fastani" ] || [ -d "$GTDBTK_DATA_PATH/skani" ]; }; then
        print_status "GTDB-Tk" "READY"
    elif [ -f "$GTDBTK_DATA_PATH/gtdbtk_data.tar.gz" ]; then
        print_status "GTDB-Tk" "INCOMPLETE" "Downloaded archive exists but is not extracted. Run: tar -xvzf $GTDBTK_DATA_PATH/gtdbtk_data.tar.gz -C $GTDBTK_DATA_PATH --strip-components=1 && rm $GTDBTK_DATA_PATH/gtdbtk_data.tar.gz"
    else
        print_status "GTDB-Tk" "MISSING" "Directory exists but required subdirectories (taxonomy, fastani/skani) are missing."
    fi
else
    print_status "GTDB-Tk" "MISSING" "Run: pixi run download-db-gtdbtk"
fi

# 2. Bakta
BAKTA_DB_PATH=$(dirname "$BAKTA_DB")
if [ -d "$BAKTA_DB_PATH" ]; then
    xz_pid=$(pgrep -f "xz -d.*db.tar.xz" | head -n 1)
    if [ -z "$xz_pid" ]; then
        xz_pid=$(pgrep -f "xz -d" | head -n 1)
    fi
    
    if [ -n "$xz_pid" ] && [ -d "/proc/$xz_pid" ]; then
        total_sz=31921769288
        pos1=$(grep -s "pos:" "/proc/$xz_pid/fdinfo/0" | awk '{print $2}')
        if [ -n "$pos1" ]; then
            sleep 1
            pos2=$(grep -s "pos:" "/proc/$xz_pid/fdinfo/0" | awk '{print $2}')
            if [ -n "$pos2" ]; then
                speed=$(( pos2 - pos1 ))
                pct_int=$(( pos2 * 100 / total_sz ))
                pct_dec=$(( (pos2 * 10000 / total_sz) % 100 ))
                if [ $speed -gt 0 ]; then
                    remaining=$(( (total_sz - pos2) / speed ))
                    min=$(( remaining / 60 ))
                    sec=$(( remaining % 60 ))
                    time_str="${min}m ${sec}s remaining"
                else
                    time_str="finishing up"
                fi
                print_status "Bakta" "EXTRACTING" "Currently uncompressing db.tar.xz (${pct_int}.${pct_dec}% complete, ${time_str})"
            else
                print_status "Bakta" "EXTRACTING" "Currently uncompressing db.tar.xz"
            fi
        else
            print_status "Bakta" "EXTRACTING" "Currently uncompressing db.tar.xz"
        fi
    elif pgrep -f "db.tar.xz" > /dev/null || pgrep -f "bakta" | grep -v "verify_databases" > /dev/null; then
        print_status "Bakta" "EXTRACTING" "Currently uncompressing/extracting db.tar.xz (check htop or wait a few minutes)."
    elif [ -f "$BAKTA_DB_PATH/db/psc.dmnd" ] && [ -f "$BAKTA_DB_PATH/db/version.json" ]; then
        print_status "Bakta" "READY"
    elif [ -f "$BAKTA_DB_PATH/db.tar.xz" ]; then
        print_status "Bakta" "INCOMPLETE" "Downloaded archive exists but is not fully extracted. Run: tar -xvf $BAKTA_DB_PATH/db.tar.xz -C $BAKTA_DB_PATH && rm $BAKTA_DB_PATH/db.tar.xz"
    else
        print_status "Bakta" "MISSING" "Directory exists but signature files are missing."
    fi
else
    print_status "Bakta" "MISSING" "Run: pixi run download-db-bakta"
fi

# 3. CheckV
if [ -d "$CHECKV_DB_PATH" ]; then
    if [ -d "$CHECKV_DB_PATH/checkv-db-v1.5/genome_db" ] && [ -d "$CHECKV_DB_PATH/checkv-db-v1.5/hmm_db" ]; then
        print_status "CheckV" "READY"
    elif [ -f "$CHECKV_DB_PATH/checkv-db-v1.5.tar.gz" ]; then
        print_status "CheckV" "INCOMPLETE" "Downloaded archive exists but is not extracted."
    else
        print_status "CheckV" "MISSING" "Directory exists but subdirectories are missing."
    fi
else
    print_status "CheckV" "MISSING" "Run: pixi run download-db-checkv"
fi

# 4. CheckM
if [ -d "$CHECKM_DB_PATH" ]; then
    if [ -d "$CHECKM_DB_PATH/hmms" ] && [ -f "$CHECKM_DB_PATH/selected_marker_sets.tsv" ]; then
        # Check if root is set in home directory
        if [ -d "$HOME/.checkm" ]; then
            print_status "CheckM" "READY"
        else
            print_status "CheckM" "INCOMPLETE" "Database files present but CheckM path not configured. Run: pixi run -e taxonomy checkm data setRoot $CHECKM_DB_PATH"
        fi
    else
        print_status "CheckM" "MISSING" "Directory exists but markers/HMMs are missing."
    fi
else
    print_status "CheckM" "MISSING" "Run: pixi run download-db-checkm"
fi

# 5. geNomad
if [ -d "$GENOMAD_DB_PATH" ]; then
    if [ -f "$GENOMAD_DB_PATH/genomad_db/genomad_db" ] && [ -f "$GENOMAD_DB_PATH/genomad_db/version.txt" ]; then
        print_status "geNomad" "READY"
    else
        print_status "geNomad" "MISSING" "Directory exists but genomad_db files are missing."
    fi
else
    print_status "geNomad" "MISSING" "Run: pixi run download-db-genomad"
fi

# 6. eggNOG
if [ -d "$EGGNOG_DB_PATH" ]; then
    if [ -f "$EGGNOG_DB_PATH/eggnog.db" ] && [ -f "$EGGNOG_DB_PATH/eggnog_proteins.dmnd" ] && [ -f "$EGGNOG_DB_PATH/eggnog.taxa.db" ]; then
        print_status "eggNOG" "READY"
    elif pgrep -f "download-db-eggnog" > /dev/null || pgrep -f "gunzip" | grep -v "verify_databases" > /dev/null; then
        print_status "eggNOG" "EXTRACTING" "Currently uncompressing eggnog.db/eggnog_proteins.dmnd (please wait a few minutes)."
    elif [ -f "$EGGNOG_DB_PATH/eggnog.db.gz" ] || [ -f "$EGGNOG_DB_PATH/eggnog_proteins.dmnd.gz" ] || [ -f "$EGGNOG_DB_PATH/eggnog.taxa.tar.gz" ]; then
        print_status "eggNOG" "INCOMPLETE" "Files downloaded but not fully uncompressed. Run: cd $EGGNOG_DB_PATH && gunzip -f *.gz && tar -zxf *.tar.gz"
    else
        print_status "eggNOG" "MISSING" "Directory exists but files are missing."
    fi
else
    print_status "eggNOG" "MISSING" "Run: pixi run download-db-eggnog"
fi

# 7. Kraken2
if [ -d "$KRAKEN2_DB_PATH" ]; then
    if [ -f "$KRAKEN2_DB_PATH/hash.k2d" ] && [ -f "$KRAKEN2_DB_PATH/opts.k2d" ] && [ -f "$KRAKEN2_DB_PATH/taxo.k2d" ]; then
        print_status "Kraken2" "READY"
    elif [ -f "$KRAKEN2_DB_PATH/k2_pluspf.tar.gz.aria2" ]; then
        # Check download progress
        progress=""
        if [ -f "$KRAKEN2_DB_PATH/k2_pluspf.tar.gz" ]; then
            current_sz=$(stat -c %s "$KRAKEN2_DB_PATH/k2_pluspf.tar.gz")
            # Convert to GB for readability
            progress_gb=$((current_sz / 1073741824))
            progress="($progress_gb GB allocated)"
        fi
        print_status "Kraken2" "DOWNLOADING" "Currently downloading k2_pluspf.tar.gz via aria2c $progress"
    elif [ -f "$KRAKEN2_DB_PATH/k2_pluspf.tar.gz" ]; then
        print_status "Kraken2" "INCOMPLETE" "Downloaded archive exists but is not extracted. Run: tar -xvzf $KRAKEN2_DB_PATH/k2_pluspf.tar.gz -C $KRAKEN2_DB_PATH && rm $KRAKEN2_DB_PATH/k2_pluspf.tar.gz"
    else
        print_status "Kraken2" "MISSING" "Directory exists but index files are missing."
    fi
else
    print_status "Kraken2" "MISSING" "Run: pixi run download-db-kraken2"
fi

# 8. Bowtie2 Human Filtering Index
if [ -n "$BOWTIE2_INDEX" ]; then
    if [ -f "${BOWTIE2_INDEX}.1.bt2" ] || [ -f "${BOWTIE2_INDEX}.1.bt2l" ]; then
        print_status "Bowtie2" "READY"
    else
        print_status "Bowtie2" "MISSING" "Index files not found at prefix: ${BOWTIE2_INDEX}. Check config.sh."
    fi
else
    print_status "Bowtie2" "MISSING" "BOWTIE2_INDEX is not configured in config.sh."
fi

# 9. MAGpurify Database
if [ -d "$MAGPURIFYDB" ]; then
    if [ -f "$MAGPURIFYDB/clade-markers.db" ] || [ -f "$MAGPURIFYDB/phyeco.hmm" ] || [ -n "$(ls -A "$MAGPURIFYDB" 2>/dev/null)" ]; then
        print_status "MAGpurify" "READY"
    elif [ -f "$MAGPURIFYDB/MAGpurify-db-v1.0.tar.bz2" ]; then
        print_status "MAGpurify" "INCOMPLETE" "Downloaded archive exists but is not extracted."
    else
        print_status "MAGpurify" "MISSING" "Directory exists but database files are missing."
    fi
else
    print_status "MAGpurify" "MISSING" "Run: pixi run download-db-magpurify"
fi

echo -e "======================================================================"
