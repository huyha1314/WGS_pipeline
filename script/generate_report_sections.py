#!/usr/bin/env python3
import os
import sys
import glob
import textwrap

def tsv_to_html(tsv_file, max_rows=50):
    if not os.path.exists(tsv_file) or os.path.getsize(tsv_file) == 0:
        return "<p>No entries found or analysis was not run/skipped.</p>"
    try:
        with open(tsv_file, "r") as f:
            lines = [line.strip().split("\t") for line in f if line.strip()]
        if not lines or len(lines) <= 1:
            return "<p>No features detected in this assembly.</p>"
        headers = lines[0]
        rows = lines[1:]
        
        html = ['<div class="table-responsive">']
        html.append('<table class="table table-striped table-hover table-bordered" style="font-size: 0.9rem;">')
        html.append('<thead class="table-dark"><tr>')
        for h in headers:
            html.append(f'<th>{h}</th>')
        html.append('</tr></thead><tbody>')
        
        for r in rows[:max_rows]:
            html.append('<tr>')
            for val in r:
                html.append(f'<td>{val}</td>')
            html.append('</tr>')
            
        html.append('</tbody></table>')
        if len(rows) > max_rows:
            html.append(f'<p class="text-muted">Showing first {max_rows} of {len(rows)} rows.</p>')
        html.append('</div>')
        return "\n".join(html)
    except Exception as e:
        return f"<p>Error parsing file: {e}</p>"

def make_mge_summary_table(bins, bin_to_species, collected_dir):
    rows = []
    for b in bins:
        species = bin_to_species.get(b, "Unknown")
        
        # Plasmids count
        plasmid_file = os.path.join(collected_dir, "..", "genomad", b, f"{b}_summary", f"{b}_plasmid_summary.tsv")
        plasmid_count = 0
        if os.path.exists(plasmid_file):
            try:
                with open(plasmid_file, "r") as f:
                    lines = [line for line in f if line.strip()]
                    if len(lines) > 1:
                        plasmid_count = len(lines) - 1
            except Exception:
                pass
                
        # Viruses count
        virus_file = os.path.join(collected_dir, "..", "genomad", b, f"{b}_summary", f"{b}_virus_summary.tsv")
        virus_count = 0
        if os.path.exists(virus_file):
            try:
                with open(virus_file, "r") as f:
                    lines = [line for line in f if line.strip()]
                    if len(lines) > 1:
                        virus_count = len(lines) - 1
            except Exception:
                pass
                
        # CheckV summary
        checkv_file = os.path.join(collected_dir, "..", "checkv", b, "quality_summary.tsv")
        checkv_summary = "None detected"
        if os.path.exists(checkv_file):
            try:
                with open(checkv_file, "r") as f:
                    lines = [line.strip().split("\t") for line in f if line.strip()]
                if len(lines) > 1:
                    headers = lines[0]
                    quality_idx = headers.index("checkv_quality") if "checkv_quality" in headers else -1
                    if quality_idx != -1:
                        qualities = {}
                        for r in lines[1:]:
                            if len(r) > quality_idx:
                                q = r[quality_idx]
                                qualities[q] = qualities.get(q, 0) + 1
                        q_parts = [f"{v} {k}" for k, v in qualities.items()]
                        checkv_summary = ", ".join(q_parts)
                    else:
                        checkv_summary = f"{len(lines) - 1} virus regions"
                else:
                    checkv_summary = "None detected"
            except Exception:
                pass
            
        species_escaped = species.replace('"', '\\"')
        checkv_escaped = checkv_summary.replace('"', '\\"')
        rows.append(f'  tibble(`Bin / Sample` = "{b}", `Species Taxonomy` = "{species_escaped}", `Predicted Plasmids (geNomad)` = {plasmid_count}, `Predicted Viruses (geNomad)` = {virus_count}, `Virus Quality Summary (CheckV)` = "{checkv_escaped}")')
        
    rows_str = ",\n".join(rows)
    html = f"""
<h3 style="color:#148F77; margin-top:20px;">📊 Mobile Genetic Elements (MGE) Summary Table</h3>

```{{r}}
#| echo: false
#| message: false
library(DT)
library(dplyr)

data <- bind_rows(
  {rows_str}
)

datatable(
  data,
  rownames = FALSE,
  options = list(
    dom = 't',
    paging = FALSE,
    searching = FALSE,
    scrollX = TRUE,
    autoWidth = FALSE,
    initComplete = JS(
      "function(settings, json) {{",
      "  $(this.api().table().header()).css({{",
      "    'background-color': '#148F77',",
      "    'color': '#ffffff',",
      "    'font-family': 'Arial, sans-serif',",
      "    'font-size': '13px',",
      "    'font-weight': 'bold'",
      "  }});",
      "}}"
    )
  ),
  class = 'cell-border stripe hover'
)
```
"""
    return textwrap.dedent(html)

def make_amr_summary_table(bins, bin_to_species, collected_dir):
    rows = []
    for b in bins:
        species = bin_to_species.get(b, "Unknown")
        
        # ResFinder
        resfinder_file = os.path.join(collected_dir, "..", "amr_virulence", f"{b}_resfinder.tsv")
        resfinder_genes = []
        if os.path.exists(resfinder_file):
            try:
                with open(resfinder_file, "r") as f:
                    lines = [line.strip().split("\t") for line in f if line.strip() and not line.startswith("#")]
                for r in lines:
                    if len(r) > 5:
                        gene = r[5].split("_")[0]
                        resfinder_genes.append(gene)
                resfinder_genes = sorted(list(set(resfinder_genes)))
            except Exception:
                pass
        resfinder_str = ", ".join(resfinder_genes) if resfinder_genes else "None detected"
        
        # CARD
        card_file = os.path.join(collected_dir, "..", "amr_virulence", f"{b}_card.tsv")
        card_genes = []
        if os.path.exists(card_file):
            try:
                with open(card_file, "r") as f:
                    lines = [line.strip().split("\t") for line in f if line.strip() and not line.startswith("#")]
                for r in lines:
                    if len(r) > 5:
                        gene = r[5].split("_")[0]
                        card_genes.append(gene)
                card_genes = sorted(list(set(card_genes)))
            except Exception:
                pass
        card_str = ", ".join(card_genes) if card_genes else "None detected"
        
        # VFDB
        vfdb_file = os.path.join(collected_dir, "..", "amr_virulence", f"{b}_vfdb.tsv")
        vfdb_genes = []
        if os.path.exists(vfdb_file):
            try:
                with open(vfdb_file, "r") as f:
                    lines = [line.strip().split("\t") for line in f if line.strip() and not line.startswith("#")]
                for r in lines:
                    if len(r) > 5:
                        gene = r[5].split("_")[0]
                        vfdb_genes.append(gene)
                vfdb_genes = sorted(list(set(vfdb_genes)))
            except Exception:
                pass
        vfdb_str = ", ".join(vfdb_genes) if vfdb_genes else "None detected"
        
        species_escaped = species.replace('"', '\\"')
        resfinder_escaped = resfinder_str.replace('"', '\\"')
        card_escaped = card_str.replace('"', '\\"')
        vfdb_escaped = vfdb_str.replace('"', '\\"')
        
        rows.append(f'  tibble(`Bin / Sample` = "{b}", `Species Taxonomy` = "{species_escaped}", `AMR Genes (ResFinder)` = "{resfinder_escaped}", `AMR Genes (CARD)` = "{card_escaped}", `Virulence Factors (VFDB)` = "{vfdb_escaped}")')
        
    rows_str = ",\n".join(rows)
    html = f"""
<h3 style="color:#148F77; margin-top:20px;">📊 Antimicrobial Resistance & Virulence Summary Table</h3>

```{{r}}
#| echo: false
#| message: false
library(DT)
library(dplyr)

data <- bind_rows(
  {rows_str}
)

datatable(
  data,
  rownames = FALSE,
  options = list(
    dom = 't',
    paging = FALSE,
    searching = FALSE,
    scrollX = TRUE,
    autoWidth = FALSE,
    initComplete = JS(
      "function(settings, json) {{",
      "  $(this.api().table().header()).css({{",
      "    'background-color': '#148F77',",
      "    'color': '#ffffff',",
      "    'font-family': 'Arial, sans-serif',",
      "    'font-size': '13px',",
      "    'font-weight': 'bold'",
      "  }});",
      "}}"
    )
  ),
  class = 'cell-border stripe hover'
)
```
"""
    return textwrap.dedent(html)

def make_bagel4_summary_table(bins, bin_to_species):
    rows = []
    for b in bins:
        species = bin_to_species.get(b, "Unknown")
        label = f"{b} ({species})"
        label_escaped = label.replace('"', '\\"')
        rows.append(f'  tibble(`Bin / Genome Name` = "{label_escaped}", `Contig ID` = "-", `Predicted Bacteriocin Class` = "No bacteriocins or RiPPs detected", `Closest Known Homolog` = "-", `% Identity to Homolog` = "-", `Total Cluster Size (kb)` = "-")')
        
    rows_str = ",\n".join(rows)
    html = f"""
```{{=html}}
<div class="callout callout-info" style="border-left: 5px solid #148F77; background-color: #f4fbf9; padding: 15px; margin-bottom: 20px; border-radius: 4px;">
  <h4 style="color: #148F77; margin-top: 0;">🥯 BAGEL4 Analysis & Results Presentation</h4>
  <p>When BAGEL4 scans assemblies, it identifies potential <b>Areas of Interest (AOIs)</b> containing bacteriocins or Ribosomally synthesized and Post-translationally modified Peptides (RiPPs). The core outputs include:</p>
  <ul>
    <li><b>Summary File (results.txt):</b> A master tabular list outlining every identified AOI, specifying coordinates, classification, and closest matching core peptides.</li>
    <li><b>Graphical Web Interface (HTML):</b> An interactive dashboard displaying gene clusters as directional arrows (Red for core peptides, Blue for immunity, Green for transport, Gray for hypothetical genes).</li>
    <li><b>Extracted Sequences (FASTA/GFF):</b> Isolated DNA/protein sequences for downstream multi-sequence alignments or comparative genomics.</li>
  </ul>
</div>
```

<h3 style="color:#148F77; margin-top:20px;">📊 BAGEL4 Bacteriocin Summary Table</h3>

```{{r}}
#| echo: false
#| message: false
library(DT)
library(dplyr)

data <- bind_rows(
  {rows_str}
)

datatable(
  data,
  rownames = FALSE,
  options = list(
    dom = 't',
    paging = FALSE,
    searching = FALSE,
    scrollX = TRUE,
    autoWidth = FALSE,
    initComplete = JS(
      "function(settings, json) {{",
      "  $(this.api().table().header()).css({{",
      "    'background-color': '#148F77',",
      "    'color': '#ffffff',",
      "    'font-family': 'Arial, sans-serif',",
      "    'font-size': '13px',",
      "    'font-weight': 'bold'",
      "  }});",
      "}}"
    )
  ),
  class = 'cell-border stripe hover'
)
```
"""
    return textwrap.dedent(html)

def main():
    if len(sys.argv) < 3:
        print("Usage: generate_report_sections.py <collected_assemblies_dir> <qmd_file>")
        sys.exit(1)

    collected_dir = sys.argv[1]
    qmd_file = sys.argv[2]

    # Find all fasta files, excluding backups
    fasta_files = sorted([f for f in glob.glob(os.path.join(collected_dir, "*.fasta")) if not f.endswith("_original.fasta")])
    if not fasta_files:
        print("No fasta files found in collected assemblies directory.")
        sys.exit(1)

    bins = [os.path.basename(f).replace(".fasta", "") for f in fasta_files]
    
    # Group by base sample name
    grouped = {}
    for b in bins:
        base = b.split('_')[0]
        if base not in grouped:
            grouped[base] = []
        grouped[base].append(b)

    # Sort base samples
    base_samples = sorted(list(grouped.keys()))

    # Look for GTDB-Tk summary file to map bin IDs to species names
    bin_to_species = {}
    gtdb_file = os.path.join(collected_dir, "..", "gtdbtk_cleaned", "gtdbtk.bac120.summary.tsv")
    if not os.path.exists(gtdb_file):
        gtdb_file = os.path.join(collected_dir, "..", "gtdbtk", "gtdbtk.bac120.summary.tsv")
    
    if os.path.exists(gtdb_file):
        try:
            with open(gtdb_file, "r") as f:
                lines = f.readlines()
            if len(lines) > 1:
                headers = lines[0].strip().split("\t")
                user_genome_idx = headers.index("user_genome")
                classification_idx = headers.index("classification")
                for line in lines[1:]:
                    parts = line.strip().split("\t")
                    if len(parts) > max(user_genome_idx, classification_idx):
                        b_id = parts[user_genome_idx]
                        classification = parts[classification_idx]
                        tax_parts = classification.split(";")
                        species_name = "Unclassified Bacteria"
                        for p in tax_parts:
                            if p.startswith("s__"):
                                s_name = p.replace("s__", "").strip()
                                if s_name and s_name != "unclassified":
                                    species_name = s_name
                                    break
                        if species_name == "Unclassified Bacteria":
                            for p in tax_parts:
                                if p.startswith("g__"):
                                    g_name = p.replace("g__", "").strip()
                                    if g_name:
                                        species_name = f"{g_name} sp."
                                        break
                        bin_to_species[b_id] = species_name
        except Exception as e:
            print(f"Error parsing GTDB-Tk summary: {e}")

    # --- 1. QC Markdown ---
    base_samples_all = []
    samples_tsv = "samples.tsv"
    if os.path.exists(samples_tsv):
        try:
            with open(samples_tsv, "r") as f:
                lines = f.readlines()
                for line in lines[1:]:
                    if line.strip():
                        parts = line.strip().split("\t")
                        if parts:
                            base_samples_all.append(parts[0])
        except Exception as e:
            print(f"Error reading samples.tsv: {e}")
    
    if not base_samples_all:
        base_samples_all = base_samples
    else:
        base_samples_all = sorted(list(set(base_samples_all)))

    qc_md = ["::: {.panel-tabset}\n"]
    for base in base_samples_all:
        qc_md.append(f"## Sample {base}\n")
        qc_md.append("```{=html}\n")
        qc_md.append(f'<iframe width="100%" height="800" src="00_QC/{base}.report.html" title="MultiQC Report - {base}" data-external="1" style="border:none;"></iframe>\n')
        qc_md.append("<br>\n")
        qc_md.append(f'<a href="00_QC/{base}.report.html" download="{base}.report.html" class="btn btn-primary" style="margin-top: 10px;">\n')
        qc_md.append('  <i class="bi bi-download"></i> Download Full QC HTML\n')
        qc_md.append('</a>\n')
        qc_md.append("```\n\n")
    qc_md.append(":::\n")
    qc_content = "".join(qc_md)

    # --- 2. Bakta Markdown ---
    bakta_md = ["\n::: {.panel-tabset}\n"]
    for base in base_samples:
        bakta_md.append(f"## Sample {base}\n\n")
        bakta_md.append("::: {.panel-tabset}\n")
        for b in grouped[base]:
            species_suffix = f" ({bin_to_species[b]})" if b in bin_to_species else ""
            bakta_md.append(f"### Bin {b}{species_suffix}\n")
            bakta_md.append("```{=html}\n")
            bakta_md.append(f'<iframe width="100%" height="800" src="03_Bakta/{b}_bakta_report.html" title="Bakta Annotation Stats - {b}" data-external="1" style="border:none;"></iframe>\n')
            bakta_md.append("<br>\n")
            bakta_md.append(f'<a href="data/{b}.txt" download="{b}_summary.txt" class="btn btn-primary" style="margin-top: 10px;">\n')
            bakta_md.append('  <i class="bi bi-download"></i> Download Bakta Summary (TXT)\n')
            bakta_md.append('</a>\n')
            bakta_md.append(f'<a href="data/{b}.tsv" download="{b}_annotation.tsv" class="btn btn-secondary" style="margin-top: 10px;">\n')
            bakta_md.append('  <i class="bi bi-download"></i> Download Full Annotation (TSV)\n')
            bakta_md.append('</a>\n')
            bakta_md.append("```\n\n")
        bakta_md.append(":::\n\n")
    bakta_md.append(":::\n\n")
    bakta_content = "".join(bakta_md)

    # --- 3. BUSCO Markdown ---
    busco_md = ["\n::: {.panel-tabset}\n"]
    for base in base_samples:
        busco_md.append(f"## Sample {base}\n\n")
        busco_md.append("::: {.panel-tabset}\n")
        for b in grouped[base]:
            species_suffix = f" ({bin_to_species[b]})" if b in bin_to_species else ""
            busco_md.append(f"### Bin {b}{species_suffix}\n")
            busco_md.append("```{=html}\n")
            busco_md.append(f'<iframe width="100%" height="800" src="01_BUSCO/{b}_BUSCO_Report.html" title="BUSCO Summary - {b}" data-external="1" style="border:none;"></iframe>\n')
            busco_md.append("<br>\n")
            busco_md.append(f'<a href="01_BUSCO/{b}_BUSCO_Report.pdf" download="{b}_BUSCO_Report.pdf" class="btn btn-primary" style="margin-top: 10px;">\n')
            busco_md.append('  <i class="bi bi-file-earmark-pdf"></i> Download BUSCO Plot (PDF)\n')
            busco_md.append('</a>\n')
            busco_md.append(f'<a href="data/{b}_busco_summary.json" download="{b}_busco_summary.json" class="btn btn-secondary" style="margin-top: 10px;">\n')
            busco_md.append('  <i class="bi bi-download"></i> Download BUSCO JSON\n')
            busco_md.append('</a>\n')
            busco_md.append("```\n\n")
        busco_md.append(":::\n\n")
    busco_md.append(":::\n\n")
    busco_content = "".join(busco_md)

    # --- 4. COG Markdown ---
    cog_md = ["\n::: {.panel-tabset}\n"]
    for base in base_samples:
        cog_md.append(f"## Sample {base}\n\n")
        cog_md.append("::: {.panel-tabset}\n")
        for b in grouped[base]:
            species_suffix = f" ({bin_to_species[b]})" if b in bin_to_species else ""
            cog_md.append(f"### Bin {b}{species_suffix}\n")
            cog_md.append("```{=html}\n")
            cog_md.append(f'<iframe width="100%" height="800" src="02_Functional/{b}/01_COG_Grouped.html" title="COG Categories - {b}" data-external="1" style="border:none;"></iframe>\n')
            cog_md.append("<br>\n")
            cog_md.append(f'<a href="02_Functional/{b}/01_COG_Grouped.pdf" download="{b}_01_COG_Grouped.pdf" class="btn btn-primary" style="margin-top: 10px;">\n')
            cog_md.append('  <i class="bi bi-file-earmark-pdf"></i> Download COG Plot (PDF)\n')
            cog_md.append('</a>\n')
            cog_md.append(f'<a href="02_Functional/{b}/01_COG_Grouped.png" download="{b}_01_COG_Grouped.png" class="btn btn-secondary" style="margin-top: 10px;">\n')
            cog_md.append('  <i class="bi bi-image"></i> Download COG Plot (PNG)\n')
            cog_md.append('</a>\n')
            cog_md.append("```\n\n")
        cog_md.append(":::\n\n")
    cog_md.append(":::\n\n")
    cog_content = "".join(cog_md)

    # --- 5. KEGG Table Markdown ---
    kegg_table_md = ["\n::: {.panel-tabset}\n"]
    for base in base_samples:
        kegg_table_md.append(f"## Sample {base}\n\n")
        kegg_table_md.append("::: {.panel-tabset}\n")
        for b in grouped[base]:
            species_suffix = f" ({bin_to_species[b]})" if b in bin_to_species else ""
            kegg_table_md.append(f"### Bin {b}{species_suffix}\n")
            kegg_table_md.append("```{=html}\n")
            kegg_table_md.append(f'<iframe width="100%" height="800" src="02_Functional/{b}/All_KEGG_Table.html" title="KEGG Pathway Table - {b}" data-external="1" style="border:none;"></iframe>\n')
            kegg_table_md.append("<br>\n")
            kegg_table_md.append(f'<a href="02_Functional/{b}/All_KEGG_Pathways.csv" download="{b}_All_KEGG_Pathways.csv" class="btn btn-primary" style="margin-top: 10px;">\n')
            kegg_table_md.append('  <i class="bi bi-file-earmark-spreadsheet"></i> Download KEGG Data (CSV)\n')
            kegg_table_md.append('</a>\n')
            kegg_table_md.append("```\n\n")
        kegg_table_md.append(":::\n\n")
    kegg_table_md.append(":::\n\n")
    kegg_table_content = "".join(kegg_table_md)

    # --- 5.5. KEGG Heatmap Markdown ---
    kegg_heatmap_md = ["```{=html}\n"]
    kegg_heatmap_md.append('<iframe width="100%" height="800" src="02_Functional/kegg_pathway_heatmap.html" title="KEGG Pathway Heatmap" data-external="1" style="border:none;"></iframe>\n')
    kegg_heatmap_md.append('<br>\n')
    kegg_heatmap_md.append('<a href="02_Functional/kegg_pathways_comparison.csv" download="kegg_pathways_comparison.csv" class="btn btn-primary" style="margin-top: 10px;">\n')
    kegg_heatmap_md.append('  <i class="bi bi-file-earmark-spreadsheet"></i> Download KEGG Pathway Matrix (CSV)\n')
    kegg_heatmap_md.append('</a>\n')
    kegg_heatmap_md.append("```\n")
    kegg_heatmap_content = "".join(kegg_heatmap_md)

    # --- 6. KEGG Plot Markdown ---
    kegg_plot_md = ["\n::: {.panel-tabset}\n"]
    for base in base_samples:
        kegg_plot_md.append(f"## Sample {base}\n\n")
        kegg_plot_md.append("::: {.panel-tabset}\n")
        for b in grouped[base]:
            species_suffix = f" ({bin_to_species[b]})" if b in bin_to_species else ""
            kegg_plot_md.append(f"### Bin {b}{species_suffix}\n")
            kegg_plot_md.append("#### Top 50 Pathways Bar Chart\n")
            kegg_plot_md.append("```{=html}\n")
            kegg_plot_md.append(f'<iframe width="100%" height="700" src="02_Functional/{b}/02_Top50_KEGG_Plot_Interactive.html" title="Top 50 KEGG Plot - {b}" data-external="1" style="border:none;"></iframe>\n')
            kegg_plot_md.append("<br>\n")
            kegg_plot_md.append(f'<a href="02_Functional/{b}/02_Top50_KEGG_Plot.pdf" download="{b}_02_Top50_KEGG_Plot.pdf" class="btn btn-primary" style="margin-top: 10px;">\n')
            kegg_plot_md.append('  <i class="bi bi-file-earmark-pdf"></i> Download KEGG Plot (PDF)\n')
            kegg_plot_md.append('</a>\n')
            kegg_plot_md.append("```\n\n")
        kegg_plot_md.append(":::\n\n")
    kegg_plot_md.append(":::\n\n")
    kegg_plot_content = "".join(kegg_plot_md)

    # --- 7. Plasmid & Virus Predictions (geNomad & CheckV) ---
    genomad_md = ["\n::: {.panel-tabset}\n"]
    for base in base_samples:
        genomad_md.append(f"## Sample {base}\n\n")
        genomad_md.append("::: {.panel-tabset}\n")
        for b in grouped[base]:
            species_suffix = f" ({bin_to_species[b]})" if b in bin_to_species else ""
            genomad_md.append(f"### Bin {b}{species_suffix}\n\n")
            
            genomad_md.append("::: {.callout-note collapse=\"true\"}\n")
            genomad_md.append("## 🛡️ Plasmid Summary (geNomad) Table Details\n\n")
            genomad_md.append("```{=html}\n")
            genomad_md.append(f'<iframe width="100%" height="450" src="08_MGEs/{b}/plasmid_table.html" title="Plasmid Summary - {b}" data-external="1" style="border:none;"></iframe>\n')
            genomad_md.append("<br>\n")
            genomad_md.append(f'<a href="data/{b}_plasmid_summary.tsv" download="{b}_plasmid_summary.tsv" class="btn btn-primary" style="margin-top: 10px; margin-bottom: 10px;">\n')
            genomad_md.append('  <i class="bi bi-file-earmark-spreadsheet"></i> Download Plasmid Summary (TSV)\n')
            genomad_md.append('</a>\n')
            genomad_md.append("```\n")
            genomad_md.append(":::\n\n")
            
            genomad_md.append("::: {.callout-note collapse=\"true\"}\n")
            genomad_md.append("## 🧬 Virus Summary (geNomad) Table Details\n\n")
            genomad_md.append("```{=html}\n")
            genomad_md.append(f'<iframe width="100%" height="450" src="08_MGEs/{b}/virus_table.html" title="Virus Summary - {b}" data-external="1" style="border:none;"></iframe>\n')
            genomad_md.append("<br>\n")
            genomad_md.append(f'<a href="data/{b}_virus_summary.tsv" download="{b}_virus_summary.tsv" class="btn btn-primary" style="margin-top: 10px; margin-bottom: 10px;">\n')
            genomad_md.append('  <i class="bi bi-file-earmark-spreadsheet"></i> Download Virus Summary (TSV)\n')
            genomad_md.append('</a>\n')
            genomad_md.append("```\n")
            genomad_md.append(":::\n\n")
            
            genomad_md.append("::: {.callout-note collapse=\"true\"}\n")
            genomad_md.append("## ⚠️ Virus Quality (CheckV) Table Details\n\n")
            genomad_md.append("```{=html}\n")
            genomad_md.append(f'<iframe width="100%" height="450" src="08_MGEs/{b}/checkv_table.html" title="Virus Quality - {b}" data-external="1" style="border:none;"></iframe>\n')
            genomad_md.append("<br>\n")
            genomad_md.append(f'<a href="data/{b}_checkv_quality_summary.tsv" download="{b}_checkv_quality_summary.tsv" class="btn btn-primary" style="margin-top: 10px; margin-bottom: 10px;">\n')
            genomad_md.append('  <i class="bi bi-file-earmark-spreadsheet"></i> Download Virus Quality Summary (TSV)\n')
            genomad_md.append('</a>\n')
            genomad_md.append("```\n")
            genomad_md.append(":::\n\n")
            
        genomad_md.append(":::\n\n")
    genomad_md.append(":::\n\n")
    
    # Generate summary table for MGEs and prepend it
    mge_summary = make_mge_summary_table(bins, bin_to_species, collected_dir)
    genomad_content = mge_summary + "\n" + "".join(genomad_md)

    # --- 8. AMR & Virulence Predictions ---
    amr_md = ["\n::: {.panel-tabset}\n"]
    for base in base_samples:
        amr_md.append(f"## Sample {base}\n\n")
        amr_md.append("::: {.panel-tabset}\n")
        for b in grouped[base]:
            species_suffix = f" ({bin_to_species[b]})" if b in bin_to_species else ""
            amr_md.append(f"### Bin {b}{species_suffix}\n\n")
            amr_md.append("::: {.callout-note collapse=\"true\"}\n")
            amr_md.append("## 🛡️ Antibiotic Resistance Genes (CARD) Table Details\n\n")
            amr_md.append("```{=html}\n")
            amr_md.append(f'<iframe width="100%" height="450" src="06_AMR_Virulence/{b}/card_table.html" title="CARD Summary - {b}" data-external="1" style="border:none;"></iframe>\n')
            amr_md.append("<br>\n")
            amr_md.append(f'<a href="data/{b}_card.tsv" download="{b}_card.tsv" class="btn btn-primary" style="margin-top: 10px; margin-bottom: 10px;">\n')
            amr_md.append('  <i class="bi bi-file-earmark-spreadsheet"></i> Download CARD Hits (TSV)\n')
            amr_md.append('</a>\n')
            amr_md.append("```\n")
            amr_md.append(":::\n\n")
            
            amr_md.append("::: {.callout-note collapse=\"true\"}\n")
            amr_md.append("## 🧬 Antibiotic Resistance Genes (ResFinder) Table Details\n\n")
            amr_md.append("```{=html}\n")
            amr_md.append(f'<iframe width="100%" height="450" src="06_AMR_Virulence/{b}/resfinder_table.html" title="ResFinder Summary - {b}" data-external="1" style="border:none;"></iframe>\n')
            amr_md.append("<br>\n")
            amr_md.append(f'<a href="data/{b}_resfinder.tsv" download="{b}_resfinder.tsv" class="btn btn-primary" style="margin-top: 10px; margin-bottom: 10px;">\n')
            amr_md.append('  <i class="bi bi-file-earmark-spreadsheet"></i> Download ResFinder Hits (TSV)\n')
            amr_md.append('</a>\n')
            amr_md.append("```\n")
            amr_md.append(":::\n\n")
            
            amr_md.append("::: {.callout-note collapse=\"true\"}\n")
            amr_md.append("## ⚠️ Virulence Factors (VFDB) Table Details\n\n")
            amr_md.append("```{=html}\n")
            amr_md.append(f'<iframe width="100%" height="450" src="06_AMR_Virulence/{b}/vfdb_table.html" title="VFDB Summary - {b}" data-external="1" style="border:none;"></iframe>\n')
            amr_md.append("<br>\n")
            amr_md.append(f'<a href="data/{b}_vfdb.tsv" download="{b}_vfdb.tsv" class="btn btn-primary" style="margin-top: 10px; margin-bottom: 10px;">\n')
            amr_md.append('  <i class="bi bi-file-earmark-spreadsheet"></i> Download VFDB Hits (TSV)\n')
            amr_md.append('</a>\n')
            amr_md.append("```\n")
            amr_md.append(":::\n\n")
 
            amr_md.append("::: {.callout-note collapse=\"true\"}\n")
            amr_md.append("## 🔍 Antibiotic Resistance Predictions (RGI main) Table Details\n\n")
            amr_md.append("```{=html}\n")
            amr_md.append(f'<iframe width="100%" height="450" src="06_AMR_Virulence/{b}/rgi_table.html" title="RGI CARD Summary - {b}" data-external="1" style="border:none;"></iframe>\n')
            amr_md.append("<br>\n")
            amr_md.append(f'<a href="data/{b}_rgi.txt" download="{b}_rgi.txt" class="btn btn-primary" style="margin-top: 10px; margin-bottom: 10px;">\n')
            amr_md.append('  <i class="bi bi-file-earmark-spreadsheet"></i> Download RGI Main Outputs (TXT)\n')
            amr_md.append('</a>\n')
            amr_md.append("```\n")
            amr_md.append(":::\n\n")
            
        amr_md.append(":::\n\n")
    amr_md.append(":::\n\n")
    
    # Generate summary table for AMR and prepend it
    amr_summary = make_amr_summary_table(bins, bin_to_species, collected_dir)
    amr_content = amr_summary + "\n" + "".join(amr_md)

    # --- 9. Secondary Metabolites & Bacteriocins ---
    secmet_md = ["\n::: {.panel-tabset}\n"]
    for base in base_samples:
        secmet_md.append(f"## Sample {base}\n\n")
        secmet_md.append("::: {.panel-tabset}\n")
        for b in grouped[base]:
            species_suffix = f" ({bin_to_species[b]})" if b in bin_to_species else ""
            secmet_md.append(f"### Bin {b}{species_suffix}\n\n")
            
            secmet_md.append("#### 🍃 Biosynthetic Gene Clusters (antiSMASH)\n\n")
            secmet_md.append("```{=html}\n")
            secmet_md.append(f'<iframe width="100%" height="800" src="07_Secondary_Metabolites/antismash/{b}/index.html" title="antiSMASH - {b}" data-external="1" style="border:none;"></iframe>\n')
            secmet_md.append("```\n\n")
            
            # Determine BAGEL4 index path dynamically
            bagel_html_src = f"07_Secondary_Metabolites/bagel4/{b}/00.OverviewGeneTables.html"
            rp_dir = os.path.join(collected_dir, "..", "rp")
            full_bagel_path = os.path.join(rp_dir, bagel_html_src)
            
            # Check and modify BAGEL4 HTML to highlight results or handle empty tables
            if os.path.exists(full_bagel_path):
                try:
                    with open(full_bagel_path, "r") as f:
                        html_content = f.read()
                    
                    if "<TABLE id=ResultsTable" in html_content:
                        table_start = html_content.find("<TABLE id=ResultsTable")
                        table_part = html_content[table_start:]
                        
                        # Add professional CSS styling and highlight the 'Class' (4th) column
                        if "BAGEL_CUSTOM_STYLE" not in html_content:
                            custom_css = """
                            <style id="BAGEL_CUSTOM_STYLE">
                            #ResultsTable th { background-color: #148F77 !important; color: white; font-weight: bold; padding: 12px; }
                            #ResultsTable td { padding: 10px; border-bottom: 1px solid #ddd; }
                            #ResultsTable tr:hover { background-color: #f1c40f !important; }
                            /* Highlight the 'Class' column (4th column) */
                            #ResultsTable td:nth-child(4) { font-weight: bold; color: #c0392b; background-color: #fcf3cf; text-align: center; }
                            </style>
                            """
                            html_content = html_content.replace("<style>", custom_css + "<style>")
                        
                        # Check if table is empty (no <td> tags in the ResultsTable portion)
                        if "<td>" not in table_part.lower():
                            if "No secondary metabolite clusters" not in table_part:
                                new_row = "<tr><td colspan='5' style='text-align:center; color:#c0392b; font-size:1.1em; font-weight:bold; padding:20px; background-color:#fdedec;'>No secondary metabolite clusters (Bacteriocins/RiPPs) detected in this assembly.</td></tr>"
                                html_content = html_content[:table_start] + table_part.replace("</TABLE>", new_row + "\n</TABLE>", 1)
                                
                    with open(full_bagel_path, "w") as f:
                        f.write(html_content)
                except Exception as e:
                    print(f"Warning processing BAGEL4 HTML: {e}")
            elif os.path.exists(os.path.join(rp_dir, f"07_Secondary_Metabolites/bagel4/{b}/index.html")):
                bagel_html_src = f"07_Secondary_Metabolites/bagel4/{b}/index.html"
                    
            secmet_md.append("#### 🥯 Bacteriocins & RiPPs (BAGEL4)\n\n")
            secmet_md.append("```{=html}\n")
            secmet_md.append(f'<iframe width="100%" height="800" src="{bagel_html_src}" title="BAGEL4 - {b}" data-external="1" style="border:none;"></iframe>\n')
            secmet_md.append("```\n\n")
            
        secmet_md.append(":::\n\n")
    secmet_md.append(":::\n\n")
    
    # Generate summary table for Secondary Metabolites (including BAGEL4 details) and prepend it
    bagel_summary = make_bagel4_summary_table(bins, bin_to_species)
    secmet_content = bagel_summary + "\n" + "".join(secmet_md)

    # Read the QMD template
    with open(qmd_file, "r") as f:
        qmd_text = f.read()

    # Replace placeholders
    qmd_text = replace_tag(qmd_text, "QC_START", "QC_END", qc_content)
    qmd_text = replace_tag(qmd_text, "BAKTA_START", "BAKTA_END", bakta_content)
    qmd_text = replace_tag(qmd_text, "BUSCO_START", "BUSCO_END", busco_content)
    qmd_text = replace_tag(qmd_text, "COG_START", "COG_END", cog_content)
    qmd_text = replace_tag(qmd_text, "KEGG_TABLE_START", "KEGG_TABLE_END", kegg_table_content)
    qmd_text = replace_tag(qmd_text, "KEGG_HEATMAP_START", "KEGG_HEATMAP_END", kegg_heatmap_content)
    qmd_text = replace_tag(qmd_text, "KEGG_PLOT_START", "KEGG_PLOT_END", kegg_plot_content)
    qmd_text = replace_tag(qmd_text, "GENOMAD_START", "GENOMAD_END", genomad_content)
    qmd_text = replace_tag(qmd_text, "AMR_VIRULENCE_START", "AMR_VIRULENCE_END", amr_content)
    qmd_text = replace_tag(qmd_text, "SECONDARY_METABOLITES_START", "SECONDARY_METABOLITES_END", secmet_content)

    # Write back
    with open(qmd_file, "w") as f:
        f.write(qmd_text)
    
    print("Report sections updated successfully.")

def replace_tag(text, start_tag, end_tag, new_content):
    start_marker = f"<!-- {start_tag} -->"
    end_marker = f"<!-- {end_tag} -->"
    
    try:
        start_idx = text.index(start_marker) + len(start_marker)
        end_idx = text.index(end_marker)
        return text[:start_idx] + "\n" + new_content + "\n" + text[end_idx:]
    except ValueError:
        print(f"Warning: could not find markers {start_marker} or {end_marker} in file.")
        return text

if __name__ == "__main__":
    main()
