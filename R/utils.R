# utils.R - small helpers shared by the scripts.

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

# Write a data frame as UTF-8 CSV regardless of the computer's language settings
write_csv_utf8 <- function(df, path) {
  q <- function(x) { x <- enc2utf8(as.character(x)); x[is.na(x)] <- ""; paste0('"', gsub('"', '""', x, fixed = TRUE), '"') }
  lines <- c(paste(q(names(df)), collapse = ","),
             if (nrow(df)) do.call(paste, c(lapply(df, q), sep = ",")))
  con <- file(path, "wb"); on.exit(close(con))
  writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), "\n")), con)
}

# Read a CSV as UTF-8 text columns, keeping empty strings as ""
read_csv_utf8 <- function(path) {
  # fileEncoding "UTF-8-BOM" reads files with or without the marker Excel adds
  df <- read.csv(path, colClasses = "character", na.strings = character(0),
                 fileEncoding = "UTF-8-BOM", check.names = FALSE)
  df[] <- lapply(df, function(x) { Encoding(x) <- "UTF-8"; x })
  df
}

# Make sure R handles text as UTF-8 (names with accents, en dashes)
if (!isTRUE(l10n_info()$`UTF-8`)) {
  for (loc in c("C.UTF-8", "en_US.UTF-8", "UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
  }
}
