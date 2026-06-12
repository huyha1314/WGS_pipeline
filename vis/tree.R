#!/usr/bin/env Rscript

# Load required libraries silently
suppressPackageStartupMessages({
  library(optparse)
  library(ape)
  library(phytools)
  library(ggtree)
  library(ggplot2)
})

# Setup command-line arguments
option_list = list(
  make_option(c("-i", "--input"), type="character", default=NULL,
              help="Input Newick tree file", metavar="FILE"),
  make_option(c("-o", "--output"), type="character", default="final_tree_plot",
              help="Output file prefix (without extension)", metavar="STRING"),
  make_option(c("-r", "--root"), type="character", default=NULL,
              help="Exact name of the outgroup tip to root the tree.", metavar="STRING"),
  make_option(c("-g", "--gtdbtk"), type="character", default=NULL,
              help="Path to GTDB-Tk classification summary file (tab-separated)", metavar="FILE")
)

opt_parser = OptionParser(option_list=option_list)
opt = parse_args(opt_parser)

if (is.null(opt$input)){
  print_help(opt_parser)
  stop("FATAL ERROR: Input tree file must be supplied (-i).", call.=FALSE)
}

cat("=== 1. Loading Tree ===\n")
tree <- read.tree(opt$input)

cat("=== 2. Rooting Tree ===\n")
if (!is.null(opt$root)) {
    if (opt$root %in% tree$tip.label) {
        cat("Rooting tree using outgroup:", opt$root, "\n")
        tree <- root(tree, outgroup = opt$root, resolve.root = TRUE)
    } else {
        stop(paste("FATAL ERROR: Outgroup '", opt$root, "' not found! Check spelling.", sep=""))
    }
} else {
    cat("No outgroup provided. Performing midpoint rooting...\n")
    tree <- midpoint.root(tree)
}

cat("=== 3. Generating Plot ===\n")

# Identify bins
collected_dir <- file.path(dirname(dirname(opt$input)), "collected_assemblies")
bin_names <- c()
if (dir.exists(collected_dir)) {
    bin_files <- list.files(collected_dir, pattern="\\.fasta$")
    bin_names <- gsub("\\.fasta$", "", bin_files)
    bin_names <- bin_names[!grepl("_original", bin_names)]
}

# Rename tips using GTDB-Tk classifications if available
highlight_labels <- bin_names
if (!is.null(opt$gtdbtk) && file.exists(opt$gtdbtk)) {
    cat("=== Mapping GTDB-Tk species names to tree tips ===\n")
    gtdb_df <- read.delim(opt$gtdbtk, sep="\t", header=TRUE, stringsAsFactors=FALSE)
    
    extract_species <- function(classification_str) {
      parts <- strsplit(classification_str, ";")[[1]]
      species_part <- parts[grep("^s__", parts)]
      if (length(species_part) > 0) {
        species_name <- gsub("^s__", "", species_part)
        if (species_name != "" && species_name != "unclassified") {
          return(species_name)
        }
      }
      genus_part <- parts[grep("^g__", parts)]
      if (length(genus_part) > 0) {
        genus_name <- gsub("^g__", "", genus_part)
        return(paste0(genus_name, " sp."))
      }
      return("Unclassified Bacteria")
    }
    
    for (i in seq_along(tree$tip.label)) {
        tip <- tree$tip.label[i]
        matched_row <- gtdb_df[gtdb_df$user_genome == tip, ]
        if (nrow(matched_row) > 0) {
            species_name <- extract_species(matched_row$classification[1])
            new_label <- paste0(tip, " (", species_name, ")")
            cat(" -> Renaming tip:", tip, "->", new_label, "\n")
            tree$tip.label[i] <- new_label
            if (tip %in% bin_names) {
                highlight_labels <- c(highlight_labels, new_label)
            }
        }
    }
}

# Calculate max distance to dynamically extend x-axis
max_dist <- max(node.depth.edgelength(tree))

# Build the beautiful static tree
p <- ggtree(tree, size=0.8) +
  geom_tiplab(size=4, align=TRUE, linesize=0.5, offset=0.005) +
  geom_nodelab(size=3.5, hjust=-0.2, vjust=-0.5, color="navyblue") +
  theme_tree2() + 
  # INCREASED MULTIPLIER: Changed from 1.5 to 3.5 to fit long NCBI names
  xlim(0, max_dist * 3.5) 

# Highlight our bins in red
if (length(highlight_labels) > 0) {
    cat("Highlighting our bins in red:", paste(highlight_labels, collapse=", "), "\n")
    p <- p + geom_tippoint(aes(subset=(label %in% highlight_labels)), size=4, color="red")
}

cat("=== 4. Saving Outputs ===\n")

# Save as Publication-Ready PDF
pdf_out <- paste0(opt$output, ".pdf")
# INCREASED WIDTH: Changed width from 12 to 16 for a wider landscape canvas
ggsave(pdf_out, plot = p, width = 16, height = 8, units = "in", dpi = 300)
cat(" -> Saved PDF:", pdf_out, "\n")

# Save as High-Res PNG 
png_out <- paste0(opt$output, ".png")
# INCREASED WIDTH: Match the PDF width here too
ggsave(png_out, plot = p, width = 16, height = 8, units = "in", dpi = 300, bg = "white")
cat(" -> Saved PNG:", png_out, "\n")