#!/usr/bin/env Rscript

# Ensure required plotting packages are installed
required_pkgs <- c("optparse", "ggplot2", "plotly", "DT", "htmlwidgets", "dplyr", "RColorBrewer")
for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg, repos = "http://cran.us.r-project.org")
}

library(optparse)
library(ggplot2)
library(plotly)
library(DT)
library(htmlwidgets)
library(dplyr)
library(RColorBrewer)

option_list = list(
  make_option(c("-i", "--input_dir"), type="character", default=NULL, 
              help="Directory containing Kraken2 report files", metavar="DIR"),
  make_option(c("-o", "--out_dir"), type="character", default=NULL, 
              help="Output directory for reports", metavar="DIR")
)

opt_parser = OptionParser(option_list=option_list)
opt = parse_args(opt_parser)

if (is.null(opt$input_dir) || is.null(opt$out_dir)) {
  print_help(opt_parser)
  stop("Error: Input directory (-i) and output directory (-o) must be provided.", call.=FALSE)
}

input_dir <- opt$input_dir
out_dir <- opt$out_dir

# Find all .report files recursively in the input directory
report_files <- list.files(input_dir, pattern = "\\.report(\\.txt)?$", full.names = TRUE, recursive = TRUE)

# Parse a single Kraken2 report
parse_kraken_report <- function(filepath) {
  lines <- readLines(filepath)
  data <- strsplit(lines, "\t")
  data <- data[sapply(data, length) >= 6]
  if (length(data) == 0) return(NULL)
  
  df <- data.frame(
    percentage = as.numeric(sapply(data, function(x) x[1])),
    clade_reads = as.numeric(sapply(data, function(x) x[2])),
    taxon_reads = as.numeric(sapply(data, function(x) x[3])),
    rank = trimws(sapply(data, function(x) x[4])),
    tax_id = trimws(sapply(data, function(x) x[5])),
    name = trimws(sapply(data, function(x) x[6])),
    stringsAsFactors = FALSE
  )
  return(df)
}

# Aggregate all reports
all_data <- list()
for (f in report_files) {
  filename <- basename(f)
  sample_name <- gsub("_kraken2\\.report(\\..*)?$", "", filename)
  sample_name <- gsub("\\.report(\\..*)?$", "", sample_name)
  sample_name <- gsub("\\.txt$", "", sample_name)
  
  cat("Parsing report for sample:", sample_name, "\n")
  df <- parse_kraken_report(f)
  if (!is.null(df)) {
    # Keep species (S) and unclassified (U)
    df_filtered <- df[df$rank == "S" | df$rank == "U", ]
    if (nrow(df_filtered) > 0) {
      df_filtered$sample <- sample_name
      all_data[[sample_name]] <- df_filtered
    }
  }
}

if (length(all_data) == 0) {
  cat("No valid Kraken2 report data found. Writing empty placeholder files.\n")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  write("<h3>No Kraken2 classification data available for these samples.</h3>", file.path(out_dir, "kraken2_abundance_plot.html"))
  write("<h3>No Kraken2 classification data available for these samples.</h3>", file.path(out_dir, "kraken2_abundance_table.html"))
  quit(status = 0)
}

# Combine into single data frame
combined_df <- bind_rows(all_data)

# Ensure "unclassified" reads are named nicely
combined_df$name[combined_df$rank == "U"] <- "Unclassified"

# Find top 20 species based on average abundance across all samples
species_abundance <- combined_df %>%
  filter(name != "Unclassified") %>%
  group_by(name) %>%
  summarise(mean_pct = mean(percentage)) %>%
  arrange(desc(mean_pct))

top_species <- head(species_abundance$name, 20)

# Group others into "Other"
combined_df <- combined_df %>%
  mutate(name_grouped = ifelse(name %in% top_species | name == "Unclassified", name, "Other"))

# Sum percentages for grouped species per sample
plot_df <- combined_df %>%
  group_by(sample, name_grouped) %>%
  summarise(percentage = sum(percentage), clade_reads = sum(clade_reads), .groups = 'drop')

# Normalize percentages to sum to 100% per sample
plot_df <- plot_df %>%
  group_by(sample) %>%
  mutate(percentage = (percentage / sum(percentage)) * 100) %>%
  ungroup()

# Set factor levels to control ordering in plot legend
legend_order <- c("Unclassified", top_species, "Other")
legend_order <- unique(legend_order[legend_order %in% plot_df$name_grouped])
plot_df$name_grouped <- factor(plot_df$name_grouped, levels = legend_order)

# Generate a high-quality palette
num_colors <- length(legend_order)
color_palette <- c(
  "#7f7f7f", # Grey for Unclassified
  colorRampPalette(brewer.pal(12, "Set3"))(num_colors - 2),
  "#d3d3d3"  # Light grey for Other
)

# Create the stacked ggplot barplot
gg <- ggplot(plot_df, aes(x = sample, y = percentage, fill = name_grouped, 
                           text = paste("Sample:", sample,
                                        "<br>Taxon:", name_grouped,
                                        "<br>Abundance:", sprintf("%.2f%%", percentage),
                                        "<br>Reads:", format(clade_reads, big.mark=",")))) +
  geom_bar(stat = "identity", position = "stack", width = 0.6) +
  scale_fill_manual(values = color_palette, name = "Taxon") +
  theme_minimal(base_size = 12) +
  labs(
    title = "Kraken2 Taxonomic Abundance Profile (Top 20 Species)",
    x = "Sample",
    y = "Relative Abundance (%)"
  ) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    panel.grid.major.x = element_blank(),
    legend.position = "right"
  )

# Convert to interactive Plotly object
interactive_plot <- ggplotly(gg, tooltip = "text") %>%
  layout(
    legend = list(orientation = "v", x = 1.05, y = 1),
    margin = list(b = 80, l = 60, t = 50, r = 150)
  )

# Create DT interactive table showing detailed abundance per sample
table_df <- combined_df %>%
  select(Taxon = name, TaxID = tax_id, Sample = sample, Percentage = percentage, Reads = clade_reads) %>%
  arrange(Sample, desc(Percentage))

html_table <- datatable(
  table_df, 
  options = list(pageLength = 15, scrollX = TRUE), 
  filter = 'top',
  colnames = c('Taxon', 'TaxID', 'Sample', 'Percentage (%)', 'Reads Count'),
  caption = htmltools::tags$caption(style = 'font-weight: bold; font-size: 1.2em;', 'Kraken2 Taxonomic Classification Details')
) %>%
  formatPercentage('Percentage', 2) %>%
  formatRound('Reads', 0)

# Save output widgets
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
saveWidget(interactive_plot, file.path(out_dir, "kraken2_abundance_plot.html"), selfcontained = TRUE)
saveWidget(html_table, file.path(out_dir, "kraken2_abundance_table.html"), selfcontained = TRUE)

cat("Kraken2 visualizations saved successfully to:", out_dir, "\n")
