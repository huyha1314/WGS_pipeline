#!/usr/bin/env Rscript

required_pkgs <- c("optparse", "DT", "htmlwidgets", "htmltools")
for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg, repos = "http://cran.us.r-project.org")
}

library(optparse)
library(DT)
library(htmlwidgets)
library(htmltools)

option_list = list(
  make_option(c("-i", "--input"), type="character", default=NULL, 
              help="Input TSV file path", metavar="FILE"),
  make_option(c("-o", "--output"), type="character", default=NULL, 
              help="Output HTML file path", metavar="FILE"),
  make_option(c("-t", "--title"), type="character", default="Table", 
              help="Table Title", metavar="TEXT")
)

opt_parser = OptionParser(option_list=option_list)
opt = parse_args(opt_parser)

if (is.null(opt$input) || is.null(opt$output)) {
  print_help(opt_parser)
  stop("Error: Input file (-i) and output file (-o) must be provided.", call.=FALSE)
}

# Check if file exists and is not empty
if (!file.exists(opt$input) || file.info(opt$input)$size == 0) {
  dir.create(dirname(opt$output), recursive = TRUE, showWarnings = FALSE)
  write(paste0("<p style='font-family: sans-serif; color: #7f8c8d;'>No data available for ", opt$title, "</p>"), opt$output)
  quit(status = 0)
}

df <- tryCatch({
  read.delim(opt$input, header=TRUE, sep="\t", stringsAsFactors=FALSE, check.names=FALSE)
}, error = function(e) {
  NULL
})

if (is.null(df) || nrow(df) == 0) {
  dir.create(dirname(opt$output), recursive = TRUE, showWarnings = FALSE)
  write(paste0("<p style='font-family: sans-serif; color: #7f8c8d;'>No data available for ", opt$title, "</p>"), opt$output)
  quit(status = 0)
}

# Replace NA with "-"
df[is.na(df)] <- "-"

# Build DT table
table_widget <- datatable(
  df,
  rownames = FALSE,
  extensions = 'Buttons',
  options = list(
    dom = 'Bfrtip',
    buttons = list(
      'copy',
      list(
        extend = 'csv',
        filename = gsub(" ", "_", opt$title)
      ),
      list(
        extend = 'excel',
        filename = gsub(" ", "_", opt$title)
      ),
      list(
        extend = 'pdf',
        filename = gsub(" ", "_", opt$title)
      )
    ),
    pageLength = 10,
    paging = TRUE,
    searching = TRUE,
    info = TRUE,
    scrollX = TRUE,
    autoWidth = FALSE,
    initComplete = JS(
      "function(settings, json) {",
      "  $(this.api().table().header()).css({",
      "    'background-color': '#148F77',",
      "    'color': '#ffffff',",
      "    'font-family': 'Arial, sans-serif',",
      "    'font-size': '13px',",
      "    'font-weight': 'bold'",
      "  });",
      "}"
    )
  ),
  class = 'cell-border stripe hover'
)

# Highlight completeness if present in CheckV
if ("completeness" %in% colnames(df)) {
  # Clean up percentage signs if they exist and convert to numeric
  comp_clean <- as.numeric(gsub("%", "", as.character(df$completeness)))
  if (!all(is.na(comp_clean))) {
    table_widget <- table_widget %>% formatStyle(
      'completeness',
      backgroundColor = styleInterval(c(50, 90), c('#f8d7da', '#fff3cd', '#d4edda')),
      color = styleInterval(c(50, 90), c('#721c24', '#856404', '#155724')),
      fontWeight = 'bold'
    )
  }
}

dir.create(dirname(opt$output), recursive = TRUE, showWarnings = FALSE)
saveWidget(table_widget, opt$output, selfcontained = TRUE)
cat("Saved DT table to:", opt$output, "\n")
