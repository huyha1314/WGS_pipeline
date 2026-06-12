import os
import pandas as pd

# Define the target categories and their gene queries (lowercased for matching)
targets = {
    "Purine Transport": ["pbux", "pbug", "nupc", "nupg", "xanq", "puck", "codb", "uraa", "uact"],
    "Purine Salvage": ["apt", "hpt", "xpt", "gpt", "deod", "add", "guac", "pura", "purb", "purc", "purd", "pure", "purf", "purg", "purh", "puri", "purk", "purl", "purm"],
    "Xanthine/Hypoxanthine": ["xdha", "xdhb", "xdhc", "xdhd", "pucl", "pucm", "puch"],
    "Uric Acid Degradation": ["uox", "uro", "uricase", "alla", "allb", "allc", "alld", "alle", "puca", "pucb", "pucc", "pucd", "puce", "alls"],
    "Purine Regulators": ["purr", "allr", "pucr", "xptr"],
    "Oxidative Stress": ["soda", "sodb", "kata", "kate", "trxa", "trxb", "gor", "gshr", "ahpc", "nox"],
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
        # Bakta TSV usually has headers starting with #
        df = pd.read_csv(tsv_path, sep='\t', comment='#', names=['SequenceId', 'Type', 'Start', 'Stop', 'Strand', 'LocusTag', 'Gene', 'Product', 'DbXrefs'])
        
        # Drop rows without gene names
        df_genes = df.dropna(subset=['Gene'])
        
        for idx, row in df_genes.iterrows():
            gene_name = str(row['Gene']).lower()
            product_name = str(row['Product']).lower()
            
            for cat, gene_list in targets.items():
                for target_gene in gene_list:
                    # Match exact gene name or if target gene name is heavily mentioned in product
                    if gene_name == target_gene or (len(target_gene) >= 3 and target_gene in gene_name.split('_')):
                        if row['Gene'] not in results[sample][cat]:
                            results[sample][cat].append(row['Gene'])
                            
    except Exception as e:
        print(f"Error processing {sample}: {e}")

# Generate Markdown
md = []
md.append("\n# Targeted Trait Analysis (Purine Metabolism & Probiotic Safety)\n")
md.append("This section evaluates the specific presence of genes related to purine metabolism, uric acid degradation, oxidative stress resistance, and biosafety (hemolysins) across the recovered assemblies based on structural annotations.\n")

# Transpose for table: Columns = Samples, Rows = Categories
md.append("### Gene Presence Matrix\n")
header = "| Functional Group | " + " | ".join(samples) + " |"
md.append(header)
md.append("|" + "|".join(["---"] * (len(samples) + 1)) + "|")

for cat in targets.keys():
    row_data = [f"**{cat}**"]
    for sample in samples:
        found_genes = results[sample][cat]
        if found_genes:
            row_data.append(", ".join(found_genes))
        else:
            row_data.append("-")
    md.append("| " + " | ".join(row_data) + " |")

md.append("\n\n")

with open("scratch/targeted_genes_report.md", "w") as f:
    f.write("\n".join(md))

print("Gene search complete. Markdown generated at scratch/targeted_genes_report.md")
