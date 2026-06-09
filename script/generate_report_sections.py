#!/usr/bin/env python3
import os
import sys
import glob

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

    # --- 1. QC Markdown ---
    qc_md = ["::: {.panel-tabset}\n"]
    for base in base_samples:
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
    bakta_md = ["::: {.panel-tabset}\n"]
    for base in base_samples:
        bakta_md.append(f"## Sample {base}\n\n")
        bakta_md.append("::: {.panel-tabset}\n")
        for b in grouped[base]:
            bakta_md.append(f"### Bin {b}\n")
            bakta_md.append("```{=html}\n")
            bakta_md.append(f'<iframe width="100%" height="600" src="03_Bakta/{b}_bakta_report.html" title="Bakta Annotation Stats - {b}" data-external="1" style="border:none;"></iframe>\n')
            bakta_md.append("<br>\n")
            bakta_md.append(f'<a href="data/{b}.txt" download="{b}_summary.txt" class="btn btn-primary" style="margin-top: 10px;">\n')
            bakta_md.append('  <i class="bi bi-download"></i> Download Bakta Summary (TXT)\n')
            bakta_md.append('</a>\n')
            bakta_md.append(f'<a href="data/{b}.tsv" download="{b}_annotation.tsv" class="btn btn-secondary" style="margin-top: 10px;">\n')
            bakta_md.append('  <i class="bi bi-download"></i> Download Full Annotation (TSV)\n')
            bakta_md.append('</a>\n')
            bakta_md.append("```\n\n")
        bakta_md.append(":::\n\n")
    bakta_md.append(":::\n")
    bakta_content = "".join(bakta_md)

    # --- 3. BUSCO Markdown ---
    busco_md = ["::: {.panel-tabset}\n"]
    for base in base_samples:
        busco_md.append(f"## Sample {base}\n\n")
        busco_md.append("::: {.panel-tabset}\n")
        for b in grouped[base]:
            busco_md.append(f"### Bin {b}\n")
            busco_md.append("```{=html}\n")
            busco_md.append(f'<iframe width="100%" height="650" src="01_BUSCO/{b}_BUSCO_Report.html" title="BUSCO Summary - {b}" data-external="1" style="border:none;"></iframe>\n')
            busco_md.append("<br>\n")
            busco_md.append(f'<a href="01_BUSCO/{b}_BUSCO_Report.pdf" download="{b}_BUSCO_Report.pdf" class="btn btn-primary" style="margin-top: 10px;">\n')
            busco_md.append('  <i class="bi bi-file-earmark-pdf"></i> Download BUSCO Plot (PDF)\n')
            busco_md.append('</a>\n')
            busco_md.append(f'<a href="data/{b}_busco_summary.json" download="{b}_busco_summary.json" class="btn btn-secondary" style="margin-top: 10px;">\n')
            busco_md.append('  <i class="bi bi-download"></i> Download BUSCO JSON\n')
            busco_md.append('</a>\n')
            busco_md.append("```\n\n")
        busco_md.append(":::\n\n")
    busco_md.append(":::\n")
    busco_content = "".join(busco_md)

    # --- 4. COG Markdown ---
    cog_md = ["::: {.panel-tabset}\n"]
    for base in base_samples:
        cog_md.append(f"## Sample {base}\n\n")
        cog_md.append("::: {.panel-tabset}\n")
        for b in grouped[base]:
            cog_md.append(f"### Bin {b}\n")
            cog_md.append("```{=html}\n")
            cog_md.append(f'<iframe width="100%" height="650" src="02_Functional/{b}/01_COG_Grouped.html" title="COG Categories - {b}" data-external="1" style="border:none;"></iframe>\n')
            cog_md.append("<br>\n")
            cog_md.append(f'<a href="02_Functional/{b}/01_COG_Grouped.pdf" download="{b}_01_COG_Grouped.pdf" class="btn btn-primary" style="margin-top: 10px;">\n')
            cog_md.append('  <i class="bi bi-file-earmark-pdf"></i> Download COG Plot (PDF)\n')
            cog_md.append('</a>\n')
            cog_md.append(f'<a href="02_Functional/{b}/01_COG_Grouped.png" download="{b}_01_COG_Grouped.png" class="btn btn-secondary" style="margin-top: 10px;">\n')
            cog_md.append('  <i class="bi bi-image"></i> Download COG Plot (PNG)\n')
            cog_md.append('</a>\n')
            cog_md.append("```\n\n")
        cog_md.append(":::\n\n")
    cog_md.append(":::\n")
    cog_content = "".join(cog_md)

    # --- 5. KEGG Table Markdown ---
    kegg_table_md = ["::: {.panel-tabset}\n"]
    for base in base_samples:
        kegg_table_md.append(f"## Sample {base}\n\n")
        kegg_table_md.append("::: {.panel-tabset}\n")
        for b in grouped[base]:
            kegg_table_md.append(f"### Bin {b}\n")
            kegg_table_md.append("```{=html}\n")
            kegg_table_md.append(f'<iframe width="100%" height="550" src="02_Functional/{b}/All_KEGG_Table.html" title="KEGG Pathway Table - {b}" data-external="1" style="border:none;"></iframe>\n')
            kegg_table_md.append("<br>\n")
            kegg_table_md.append(f'<a href="02_Functional/{b}/All_KEGG_Pathways.csv" download="{b}_All_KEGG_Pathways.csv" class="btn btn-primary" style="margin-top: 10px;">\n')
            kegg_table_md.append('  <i class="bi bi-file-earmark-spreadsheet"></i> Download KEGG Data (CSV)\n')
            kegg_table_md.append('</a>\n')
            kegg_table_md.append("```\n\n")
        kegg_table_md.append(":::\n\n")
    kegg_table_md.append(":::\n")
    kegg_table_content = "".join(kegg_table_md)

    # --- 6. KEGG Plot Markdown ---
    kegg_plot_md = ["::: {.panel-tabset}\n"]
    for base in base_samples:
        kegg_plot_md.append(f"## Sample {base}\n\n")
        kegg_plot_md.append("::: {.panel-tabset}\n")
        for b in grouped[base]:
            kegg_plot_md.append(f"### Bin {b}\n")
            kegg_plot_md.append("```{=html}\n")
            kegg_plot_md.append(f'<iframe width="100%" height="700" src="02_Functional/{b}/02_Top50_KEGG_Plot_Interactive.html" title="Top 50 KEGG Plot - {b}" data-external="1" style="border:none;"></iframe>\n')
            kegg_plot_md.append("<br>\n")
            kegg_plot_md.append(f'<a href="02_Functional/{b}/02_Top50_KEGG_Plot.pdf" download="{b}_02_Top50_KEGG_Plot.pdf" class="btn btn-primary" style="margin-top: 10px;">\n')
            kegg_plot_md.append('  <i class="bi bi-file-earmark-pdf"></i> Download KEGG Plot (PDF)\n')
            kegg_plot_md.append('</a>\n')
            kegg_plot_md.append("```\n\n")
        kegg_plot_md.append(":::\n\n")
    kegg_plot_md.append(":::\n")
    kegg_plot_content = "".join(kegg_plot_md)

    # Read the QMD template
    with open(qmd_file, "r") as f:
        qmd_text = f.read()

    # Replace placeholders
    qmd_text = replace_tag(qmd_text, "QC_START", "QC_END", qc_content)
    qmd_text = replace_tag(qmd_text, "BAKTA_START", "BAKTA_END", bakta_content)
    qmd_text = replace_tag(qmd_text, "BUSCO_START", "BUSCO_END", busco_content)
    qmd_text = replace_tag(qmd_text, "COG_START", "COG_END", cog_content)
    qmd_text = replace_tag(qmd_text, "KEGG_TABLE_START", "KEGG_TABLE_END", kegg_table_content)
    qmd_text = replace_tag(qmd_text, "KEGG_PLOT_START", "KEGG_PLOT_END", kegg_plot_content)

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
