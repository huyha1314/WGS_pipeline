#!/bin/bash
# ==============================================================================
#                 PRECISIONGENE WGS PIPELINE CONFIGURATION FILE
# ==============================================================================
# This file centralizes all directories, databases, computer resources, and tool
# arguments. All pipeline scripts source this file.

# --- 1. DIRECTORY CONFIGURATION ---
export WORKDIR="/worker_data2/huyha/precisiongene/suran_wgs"
export RESULT_DIR="$WORKDIR/results"
export LOG_DIR="$WORKDIR/log"
export INPUT_SHEET="$WORKDIR/samples.tsv"

# Create directories if they do not exist
mkdir -p "$RESULT_DIR" "$LOG_DIR"

# --- 2. COMPUTER RESOURCES ---
# Threads/CPUs to use for various steps
export CPUS_MAX=64
export CPUS_MED=56
export CPUS_MIN=48

# Memory limits (useful for Java heap or Slurm resource requests)
export MEM_MAX="385G"
export MEM_MED="256G"
export MEM_MIN="192G"

# Parallel fastp configuration
export PARALLEL_JOBS_FASTP=3
export THREADS_PER_FASTP=16

# Parallel BBDuk / Bowtie2 / Kraken2 configuration
export PARALLEL_JOBS_QC_BT2=8
export THREADS_PER_QC_BT2=8
export PARALLEL_JOBS_KRAKEN=2
export THREADS_PER_KRAKEN=32

# --- 3. DATABASE CONFIGURATION ---
# Base database directory
export DB_DIR="/worker_data1/huyha/db"

# Create database directory if it does not exist
mkdir -p "$DB_DIR"

# GTDB-Tk Reference Database
export GTDBTK_DATA_PATH="$DB_DIR/gtdbtk"

# Bakta Annotation Database
export BAKTA_DB="/worker_data1/huyha/db/bakta/db"

# eggNOG Functional Annotation Database
export EGGNOG_DB_PATH="$DB_DIR/eggnog"

# Kraken2 Taxonomic Database
export KRAKEN2_DB_PATH="$DB_DIR/kraken2"

# CheckV Viral Identification Database
export CHECKV_DB_PATH="$DB_DIR/checkv/checkv-db-v1.5"

# geNomad Plasmid/Virus Identification Database
export GENOMAD_DB_PATH="$DB_DIR/genomad/genomad_db"

# CheckM Quality Assessment Database
export CHECKM_DB_PATH="$DB_DIR/checkm"

# MAGpurify Reference Database
export MAGPURIFYDB="$DB_DIR/magpurify"

# Bowtie2 Index for Human Read Filtering (e.g. hg38)
export BOWTIE2_INDEX="$DB_DIR/bowtie2_indexes/GRCh38_noalt_as/GRCh38_noalt_as"

# ABRicate (AMR & Virulence) Database Directory
export ABRICATE_DB_DIR="$DB_DIR/abricate"

# RGI (CARD) Database Directory
export RGI_DB_DIR="$DB_DIR/rgi"

# antiSMASH secondary metabolite database
export ANTISMASH_DB_DIR="$DB_DIR/antismash"

# BAGEL4 secondary metabolite directory & database
export BAGEL4_DIR="$DB_DIR/bagel4"
export BAGEL4_DB_DIR="$BAGEL4_DIR/db"

# --- 4. TOOL-SPECIFIC PARAMETERS ---
# fastp
export FASTP_TRIM_FRONT1=8
export FASTP_TRIM_FRONT2=8
export FASTP_LENGTH_REQUIRED=50
export FASTP_QUALIFIED_QUALITY_PHRED=25

# bbduk
export BBDUK_ENTROPY=0.6
export BBDUK_ENTROPY_WINDOW=50
export BBDUK_ENTROPY_K=5

# kraken2
export KRAKEN2_CONFIDENCE=0.1
export KRAKEN2_MIN_QUAL=20

# megahit
export MEGAHIT_MEM_FRACTION="0.95"
export MEGAHIT_MIN_CONTIG_LEN=500
export MEGAHIT_K_LIST="21,33,55,77,99,127"

# SSPACE scaffolding
export SSPACE_INSERT_SIZE=350
export SSPACE_INSERT_ERR=0.5

# Bakta default metadata
export BAKTA_GENUS="Salmonella"
export BAKTA_SPECIES="enterica"

# GTDB-Tk filters
export GTDBTK_MIN_PERC_AA=10

# --- 5. PIPELINE EXECUTION OPTIONS ---
# Assembler tool to use. Options: megahit, spades, flye
# (Note: Megahit & SPAdes support short-reads; Flye is for long-reads)
export ASSEMBLER="megahit"

# Auto-default polishing (Pilon) and scaffolding (SSpaces) based on assembler choice.
# SPAdes and Flye assemblies do not need Pilon polishing and SSPACE scaffolding by default.
# Megahit assemblies require polishing and scaffolding.
# You can override these defaults by explicitly setting them to true or false.
if [[ "$ASSEMBLER" == "spades" || "$ASSEMBLER" == "flye" ]]; then
    export RUN_POLISHING=${RUN_POLISHING:-false}
    export RUN_SCAFFOLDING=${RUN_SCAFFOLDING:-false}
else
    export RUN_POLISHING=${RUN_POLISHING:-true}
    export RUN_SCAFFOLDING=${RUN_SCAFFOLDING:-true}
fi

# Set to true to run MAGpurify contaminant removal and checkm/gtdbtk on cleaned bins, or false to skip
export RUN_MAGPURIFY=false

# Set to true to run MaxBin2 in addition to MetaBAT2, or false to skip
export RUN_MAXBIN=true

# Set to true to run AMR and Virulence gene search (ResFinder + CARD + VFDB) via abricate, or false to skip
export RUN_AMR_VIRULENCE=true

# Set to true to run antiSMASH secondary metabolite analysis, or false to skip
export RUN_ANTISMASH=true

# Set to true to run BAGEL4 bacteriocin analysis, or false to skip
export RUN_BAGEL4=true


# --- 6. BATCH RUN CONFIGURATION ---
# You can manually name this batch run (e.g., export BATCH_NAME="my_custom_batch").
# If left empty, it will automatically default to the name of the workspace directory.
export BATCH_NAME="${BATCH_NAME:-$(basename "$WORKDIR")}"


