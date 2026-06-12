#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(optparse)
  library(tidyverse)
  library(plotly)
  library(htmlwidgets)
})

option_list <- list(
  make_option(c("-i", "--indir"), type = "character", default = NULL,
              help = "Input directory containing sample folders with All_KEGG_Pathways.csv", metavar = "DIR"),
  make_option(c("-o", "--out"), type = "character", default = NULL,
              help = "Output path for the HTML heatmap", metavar = "FILE")
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

if (is.null(opt$indir) || is.null(opt$out)) {
  print_help(opt_parser)
  stop("Error: Input directory and output file must be specified.", call. = FALSE)
}

# Find all All_KEGG_Pathways.csv files recursively
csv_files <- list.files(opt$indir, pattern = "All_KEGG_Pathways.csv", recursive = TRUE, full.names = TRUE)

if (length(csv_files) == 0) {
  # Write a placeholder HTML file if no KEGG data found
  dir.create(dirname(opt$out), recursive = TRUE, showWarnings = FALSE)
  write("<p style='font-family: sans-serif; color: #7f8c8d; text-align: center;'>No KEGG pathway data found to generate heatmap.</p>", opt$out)
  quit(status = 0)
}

# Read and combine data
combined_data <- list()
for (f in csv_files) {
  # Extract sample name from path
  # e.g., .../02_Functional/243/All_KEGG_Pathways.csv -> sample = 243
  parts <- str_split(f, "/")[[1]]
  sample_name <- parts[length(parts) - 1]
  
  df <- tryCatch({
    read.csv(f, stringsAsFactors = FALSE)
  }, error = function(e) {
    NULL
  })
  
  if (!is.null(df) && nrow(df) > 0) {
    df$Sample <- sample_name
    combined_data[[sample_name]] <- df
  }
}

if (length(combined_data) == 0) {
  write("<p style='font-family: sans-serif; color: #7f8c8d; text-align: center;'>No valid KEGG pathway data found to generate heatmap.</p>", opt$out)
  quit(status = 0)
}

big_df <- bind_rows(combined_data)

# Select top 50 pathways by sum of counts across all samples
top_pathways <- big_df %>%
  group_by(Pathway_Name) %>%
  summarize(Total_Count = sum(Count, na.rm = TRUE)) %>%
  slice_max(Total_Count, n = 50) %>%
  pull(Pathway_Name)

# Filter big_df to include only top 50 pathways
filtered_df <- big_df %>%
  filter(Pathway_Name %in% top_pathways)

# Pivot to wide format
heatmap_matrix <- filtered_df %>%
  select(Pathway_Name, Sample, Count) %>%
  pivot_wider(names_from = Sample, values_from = Count, values_fill = 0) %>%
  column_to_rownames("Pathway_Name")

# Convert to matrix
mat <- as.matrix(heatmap_matrix)

# Create custom hovertext
hovertext <- matrix("", nrow = nrow(mat), ncol = ncol(mat))
for (i in 1:nrow(mat)) {
  for (j in 1:ncol(mat)) {
    hovertext[i, j] <- paste(
      "Pathway: ", rownames(mat)[i], "<br>",
      "Sample/Bin: ", colnames(mat)[j], "<br>",
      "Gene Count: ", mat[i, j],
      sep = ""
    )
  }
}

# Generate Plotly heatmap
p <- plot_ly(
  x = colnames(mat),
  y = rownames(mat),
  z = mat,
  type = "heatmap",
  colorscale = "Viridis",
  text = hovertext,
  hoverinfo = "text"
) %>% layout(
  title = list(
    text = "<b>Functional Pathway Comparison (Top 50 KEGG Pathways)</b>",
    font = list(family = "Arial, sans-serif", size = 16, color = "#2C3E50")
  ),
  xaxis = list(
    title = "<b>Genome Bins</b>",
    titlefont = list(family = "Arial, sans-serif", size = 12, color = "#2C3E50"),
    tickfont = list(family = "Arial, sans-serif", size = 10, color = "#2C3E50")
  ),
  yaxis = list(
    title = "",
    automargin = TRUE,
    tickfont = list(family = "Arial, sans-serif", size = 9, color = "#2C3E50")
  ),
  margin = list(l = 280, r = 20, t = 60, b = 60)
)

# Save the widget
dir.create(dirname(opt$out), recursive = TRUE, showWarnings = FALSE)
saveWidget(p, opt$out, selfcontained = TRUE)
cat("Successfully saved KEGG heatmap to:", opt$out, "\n")

# Save CSV for downloading
csv_out <- file.path(dirname(opt$out), "kegg_pathways_comparison.csv")
write.csv(heatmap_matrix, csv_out, row.names = TRUE)
cat("Saved KEGG matrix to:", csv_out, "\n")
