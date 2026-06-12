import os

# Define the target categories and their gene queries (lowercased for matching)
targets = {
    "Purine Transport": ["pbux", "pbug", "nupc", "nupg", "xanq", "puck", "codb", "uraa", "uact"],
    "Purine Salvage": ["apt", "hpt", "xpt", "gpt", "deod", "add", "guac", "pura", "purb", "purc", "purd", "pure", "purf", "purg", "purh", "puri", "purk", "purl", "purm"],
    "Xanthine/Hypoxanthine Metabolism": ["xdha", "xdhb", "xdhc", "xdhd", "pucl", "pucm", "puch"],
    "Uric Acid Degradation": ["uox", "uro", "uricase", "alla", "allb", "allc", "alld", "alle", "puca", "pucb", "pucc", "pucd", "puce", "alls"],
    "Purine/Allantoin Regulators": ["purr", "allr", "pucr", "xptr"],
    "Oxidative Stress/XO Inhibition": ["soda", "sodb", "kata", "kate", "trxa", "trxb", "gor", "gshr", "ahpc", "nox"],
    "LAB Adhesion/EPS": ["mub", "mapa", "srta", "epsa", "epsb", "epsc", "epsd", "epse"],
    "Probiotic Traits": ["bsh", "groel", "dnak", "clp"],
    "Hemolysis/Toxins": ["hbla", "hblb", "hblc", "hbld", "nhea", "nheb", "nhec", "cytk", "entfm", "hly", "plcr", "cyla", "cylb", "cylm", "esp", "asa1", "agg", "gele"]
}

samples = ["243", "27_maxbin.002", "85_maxbin.001", "85_maxbin.002", "TC3"]
annotation_dir = "results/annotation"

results = {sample: {cat: [] for cat in targets} for sample in samples}

for sample in samples:
    tsv_path = os.path.join(annotation_dir, sample, f"{sample}.tsv")
    if not os.path.exists(tsv_path):
        continue
        
    try:
        with open(tsv_path, 'r') as f:
            for line in f:
                if line.startswith('#'):
                    continue
                parts = line.strip().split('\t')
                if len(parts) >= 7:
                    gene_name = parts[6].lower()
                    if gene_name:
                        for cat, gene_list in targets.items():
                            for target_gene in gene_list:
                                if gene_name == target_gene or (len(target_gene) >= 3 and target_gene in gene_name.split('_')):
                                    if parts[6] not in results[sample][cat]:
                                        results[sample][cat].append(parts[6])
    except Exception as e:
        print(f"Error processing {sample}: {e}")

# Generate Markdown and CSV
import csv

md = []
md.append("\n# Targeted Trait Analysis (Purine Metabolism, Uricase & Probiotic Safety)\n")
md.append("This section evaluates the specific presence of genes requested in the project requirements, including purine metabolism, uric acid degradation, oxidative stress resistance, LAB adhesion, and biosafety (hemolysins) across the recovered assemblies based on structural annotations.\n")

md.append("### Gene Presence Matrix\n")
header = "| Functional Group | " + " | ".join(samples) + " |"
md.append(header)
md.append("|" + "|".join(["---"] * (len(samples) + 1)) + "|")

csv_data = [["Functional Group"] + samples]

for cat in targets.keys():
    row_data = [f"**{cat}**"]
    csv_row = [cat]
    for sample in samples:
        found_genes = results[sample][cat]
        if found_genes:
            row_data.append(", ".join(found_genes))
            csv_row.append(", ".join(found_genes))
        else:
            row_data.append("-")
            csv_row.append("-")
    md.append("| " + " | ".join(row_data) + " |")
    csv_data.append(csv_row)

md.append("\n\n")
md.append("```{=html}\n")
md.append('<br>\n<a href="02_Functional/targeted_genes.csv" download="targeted_genes.csv" class="btn btn-primary" style="margin-top: 10px;">\n')
md.append('  <i class="bi bi-file-earmark-spreadsheet"></i> Download Targeted Gene Matrix (CSV)\n</a>\n')
md.append("```\n")

with open("scratch/targeted_genes_report.md", "w") as f:
    f.write("\n".join(md))

# Write CSV to Functional folder
os.makedirs("02_Functional", exist_ok=True)
with open("02_Functional/targeted_genes.csv", "w", newline='') as f:
    writer = csv.writer(f)
    writer.writerows(csv_data)

# Append to 14.rp_purine_project.qmd
with open("14.rp_purine_project.qmd", "a") as f:
    f.write("\n".join(md) + "\n")

print("Success!")
