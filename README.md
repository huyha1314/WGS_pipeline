# Bacterial WGS Analysis Pipeline (`suran_sal`)

A modern, reproducible, and configuration-driven bacterial Whole Genome Sequencing (WGS) pipeline orchestrated with **Pixi** and **SLURM**.

---

## Table of Contents
1. [Pipeline Overview](#pipeline-overview)
2. [Prerequisites & Setup](#prerequisites--setup)
3. [Configuration (`config.sh`)](#configuration-configsh)
4. [Downloading Reference Databases](#downloading-reference-databases)
5. [Step-by-Step Usage Tutorial](#step-by-step-usage-tutorial)
   * [Step 1: Generate Input Sheet](#step-1-generate-input-sheet)
   * [Step 2: Run Master Workflow](#step-2-run-master-workflow)
   * [Step 3: Build Reference Trees](#step-3-build-reference-trees)
6. [Pipeline Features & Modules](#pipeline-features--modules)
7. [Job Resume & Checkpoint Logic](#job-resume--checkpoint-logic)

---

## Pipeline Overview

This pipeline automates short-read bacterial genome assembly, polishing, scaffolding, quality check, taxonomic classification, gene prediction, plasmid/viral identification, and functional annotation.

```mermaid
graph TD
    A[Raw FASTQ Reads] --> B[1. Fastp Trimming]
    B --> C[2. BBDuk / Bowtie2 / Kraken2]
    C --> D[3. Megahit Assembly]
    D --> E[4. Pilon Polishing R1]
    E --> F[5. SSPACE Scaffolding]
    F --> G[6. Pilon Polishing R2]
    G --> H[6.5. MetaBAT2 Binning]
    H --> I[8. CheckM & GTDB-Tk (Original Bins)]
    I --> J[8.5. MAGpurify Refinement]
    J --> K[8.6. CheckM & GTDB-Tk (Cleaned Bins)]
    K --> L[7. Bakta Annotation]
    K --> M[9. eggNOG Annotation]
    K --> N[10. BUSCO Completeness]
    K --> O[10.5. geNomad & CheckV]
    K --> P[12. Phylogenomic Tree]
    L --> M
```

---

## Prerequisites & Setup

Ensure you have [Pixi](https://pixi.sh/) installed on your Linux system. If not, install it via:
```bash
curl -fsSL https://pixi.sh/install.sh | bash
```
Restart your shell after installation.

Initialize the environments and install all pipeline dependencies automatically:
```bash
# Clone the repository
git clone https://github.com/huyha1314/suran_sal.git
cd suran_wgs

# Solve and install all environment feature-sets (QC, Assembly, Annotation, Taxonomy, etc.)
pixi install --all
```

---

## Configuration (`config.sh`)

All project-wide settings, directories, computer resources, and tool arguments are managed in [config.sh](config.sh). Open and edit this file to suit your system resources.

Key variables in `config.sh`:
*   `DB_DIR`: Default path for all databases, set to `/worker_data1/huyha/db`.
*   `CPUS_MAX` / `CPUS_MED` / `CPUS_MIN`: CPU allocations for the Slurm jobs.
*   `FASTP_*` / `BBDUK_*` / `MEGAHIT_*`: Hardcoded parameters for the bioinformatics tools.

---

## Downloading Reference Databases

Large reference databases are downloaded directly to `/worker_data1/huyha/db` using multi-connection `aria2c` for maximum speed.

> [!IMPORTANT]
> Always run tasks using **`pixi run <task-name>`**. Running `pixi <task-name>` without `run` will result in an unrecognized subcommand error.

Run the corresponding command to download and extract the required databases:

```bash
# 1. GTDB-Tk Reference Database (~100 GB)
pixi run download-db-gtdbtk

# 2. Bakta Annotation Database (~40 GB)
pixi run download-db-bakta

# 3. CheckV Viral Database (~1.5 GB)
pixi run download-db-checkv

# 4. CheckM Marker Database (~1.4 GB)
pixi run download-db-checkm

# 5. geNomad Plasmid/Virus Database (~10 GB)
pixi run download-db-genomad

# 6. eggNOG Functional Annotation Database (~15 GB)
pixi run download-db-eggnog

# 7. Kraken2 PlusPF (Fungi & Protozoa) Database (~75 GB compressed)
pixi run download-db-kraken2
```

### Checking Database Status
You can verify the download, extraction, and readiness status of all 7 required databases at any time by running:
```bash
./script/verify_databases.sh
```

---

## Step-by-Step Usage Tutorial

### Step 1: Generate Input Sheet
Scan your raw fastq folder to pair forward and reverse reads and automatically generate a `samples.tsv` file:
```bash
pixi run create-sheet -i data/20260509 -o samples.tsv
```
This produces a tab-separated sheet containing three columns:
1.  `name`: Sample unique identifier.
2.  `path_R1`: Absolute path to forward read file.
3.  `path_R2`: Absolute path to reverse read file.

### Step 2: Run Master Workflow

#### Option A: Slurm Cluster Mode (Recommended for cluster environments)
Submit all pipeline modules (from Quality Control to Assembly, Scaffolding, Annotation, Phylogeny, Visualization, and Quarto HTML rendering) to the SLURM cluster scheduler. Job dependency tracking is handled automatically:
```bash
./script/11.masterworkflow.sh
```
To monitor your submitted Slurm jobs, run:
```bash
squeue -u $USER
```

#### Option B: Standalone Local Mode (Fallback for local machines or drained nodes)
If the Slurm scheduler is unavailable, offline, or nodes are drained, you can execute the entire pipeline sequentially directly on the local high-performance node (this automatically activates the pixi default environment with all tools like GNU Parallel and pigz):
```bash
pixi run run-pipeline-local
```

Once all jobs complete, the pipeline will automatically compile the interactive HTML report and archive the entire dashboard directory into:
*   `results/rp/14.rp.html` (The interactive HTML dashboard)
*   `results/rp.zip` (Compressed ZIP archive of the report)
*   `results/rp.tar.gz` (Compressed tarball of the report)

---

## Pipeline Features & Modules

### 🧼 Quality Control & Filtering
*   **Trimming**: [1.fastp.sh](script/1.fastp.sh) performs adapter removal, quality-sliding windows, and low-quality filtering.
*   **Contaminant Removal**: [2.bbduk.sh](script/2.bbduk.sh) filters out low-entropy/sequence-artifact reads, runs `Bowtie2` to filter out human host reads (e.g. hg38), and classifies taxonomic reads with `Kraken2`.

### 🧬 Genome Assembly & Polishing
*   **De Novo Assembly**: [3.megahit.sh](script/3.megahit.sh) runs MEGAHIT to build contigs.
*   **Polishing**: [4.pilon.sh](script/4.pilon.sh) maps clean reads back to assemblies using `bwa` and runs Pilon to correct mismatches and small indels.
*   **Scaffolding**: [5.sspaces.sh](script/5.sspaces.sh) runs SSPACE to join contigs into longer scaffolds using paired-read spacing information.
*   **Final Correction**: [6.pilon_ss.sh](script/6.pilon_ss.sh) maps reads to scaffolded sequences for a second round of polishing.

### 🧬 Genome Binning & Contaminant Refinement
*   **Binning**: [6.5.metabat2.sh](script/6.5.metabat2.sh) runs MetaBAT2 to bin polished contigs, separating chromosomal DNA from plasmids or potential cellular contamination.
*   **Quality Stats (Original Bins)**: [8.checkm_GTDB_wgs.sh](script/8.checkm_GTDB_wgs.sh) assesses genome quality (completeness/contamination) of all MetaBAT2 bins via CheckM, and classifies taxonomy using GTDB-Tk.
*   **Automated Bin Refinement**: [8.5.magpurify.sh](script/8.5.magpurify.sh) runs MAGpurify to flag and discard outlier contigs (based on GC content, tetranucleotide frequencies, and conflicting phylogenetic clade markers).
*   **Post-Cleaning Verification**: [8.6.checkm_cleaned.sh](script/8.6.checkm_cleaned.sh) runs CheckM and GTDB-Tk on cleaned assemblies to verify that contamination dropped below 5% and finalize taxonomy.

### 🏷️ Genome Annotation & Downstream Analysis
*   **Gene Annotation**: [7.bakta.sh](script/7.bakta.sh) runs Bakta on the refined main bins to predict coding sequences (CDS), tRNAs, rRNAs, and annotate them.
*   **Functional Annotation**: [9.eggnog.sh](script/9.eggnog.sh) predicts functional classes and GO terms using Diamond alignments against the eggNOG database.
*   **Completeness**: [10.busco.sh](script/10.busco.sh) checks genome assembly completeness against conserved single-copy orthologs.
*   **Plasmids & Viruses**: [10.5.plasmid_prediction.sh](script/10.5.plasmid_prediction.sh) runs geNomad on the refined bins to identify plasmids or viral contigs and evaluates virus qualities with CheckV.

---

## Job Resume & Checkpoint Logic

The pipeline is fully resume-compatible. If the workflow is interrupted or a node fails:
1.  Edit `samples.tsv` or your configurations if needed.
2.  Relaunch `./script/11.masterworkflow.sh` (or `pixi run run-pipeline-local` if running locally).
3.  The master script will look for checkpoint files (e.g., `.gbff` for Bakta, `.fasta` for Pilon, `checkm_summary.txt` for CheckM).
4.  Completed tasks will be **skipped**, and only failed/incomplete steps will be processed.

---

## Troubleshooting & Known Issues

### 1. GTDB-Tk / Skani Database "index out of range for slice" Panic
*   **Symptom**: During step 8 (`CheckM & GTDB-Tk`), GTDB-Tk fails with a Rust panic from the underlying `skani` tool:
    ```text
    thread '<unnamed>' panicked at src/sketch_db.rs:114:35:
    range start index XXXXXXXX out of range for slice of length 54843010048
    ```
*   **Cause**: This error occurs when the GTDB-Tk reference database file `sketches.db` is truncated or corrupted on disk (for example, if a previous download or extraction was interrupted or ran out of disk space). Skani memory-maps the truncated file, but then tries to look up offsets from the index that extend beyond the truncated file size (which is 54,843,010,048 bytes when truncated instead of the complete 75,270,701,831 bytes).
*   **Fix**:
    Re-extract the `sketches.db` file from the downloaded `gtdbtk_data.tar.gz` archive. You can do this by running:
    ```bash
    # Rename/backup the truncated file
    mv /worker_data1/huyha/db/gtdbtk/skani/database/sketches.db /worker_data1/huyha/db/gtdbtk/skani/database/sketches.db.truncated
    
    # Extract the complete sketches.db file (parallelized using pigz)
    pixi run tar -I pigz -xvf /worker_data1/huyha/db/gtdbtk_download/gtdbtk_data.tar.gz -C /worker_data1/huyha/db/gtdbtk --strip-components=1 release232/skani/database/sketches.db
    
    # Verify the extracted size is 75,270,701,831 bytes (approx. 71 GB)
    stat --format="%s" /worker_data1/huyha/db/gtdbtk/skani/database/sketches.db
    
    # Clean up the backup
    rm /worker_data1/huyha/db/gtdbtk/skani/database/sketches.db.truncated
    ```
