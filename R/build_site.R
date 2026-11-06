# build_site.R
# Checks publications.csv and builds the publications web page in _site/.
#
# Usage (from the repository root):  Rscript R/build_site.R
# Then open _site/index.html in a browser to preview.
#
# Uses base R and jsonlite only.

source("R/utils.R")
suppressPackageStartupMessages(library(jsonlite))

TYPES <- c("Primary", "Secondary", "Tertiary")

pubs <- read_csv_utf8("publications.csv")
pubs[] <- lapply(pubs, trimws)
pubs$doi <- tolower(sub("^https?://(dx\\.)?doi\\.org/", "", pubs$doi))

meta_file <- "metadata/openalex.csv"
meta <- if (file.exists(meta_file))
  read_csv_utf8(meta_file) else
  data.frame(doi = character(), oa_year = character(), oa_url = character(),
             cited_by = character(), auto_citation = character())
m <- meta[match(pubs$doi, meta$doi), ]

# ---- checks ------------------------------------------------------------------------
errors <- character(); warnings <- character()
row_label <- function(i) sprintf("row %d (%s)", i + 1, substr(
  if (nzchar(pubs$citation[i])) pubs$citation[i] else pubs$doi[i], 1, 60))

for (i in seq_len(nrow(pubs))) {
  has_doi <- nzchar(pubs$doi[i])
  if (!pubs$type[i] %in% TYPES)
    errors <- c(errors, sprintf("%s: type must be Primary, Secondary or Tertiary", row_label(i)))
  if (has_doi && !grepl("^10\\.\\d{4,9}/\\S+$", pubs$doi[i]))
    errors <- c(errors, sprintf("%s: DOI '%s' does not look valid", row_label(i), pubs$doi[i]))
  if (!has_doi && !nzchar(pubs$citation[i]))
    errors <- c(errors, sprintf("%s: a row without a DOI needs a citation", row_label(i)))
  if (!has_doi && !grepl("^\\d{4}$", pubs$year[i]))
    errors <- c(errors, sprintf("%s: a row without a DOI needs a 4-digit year", row_label(i)))
  if (has_doi && !nzchar(pubs$citation[i]) && !nzchar(m$auto_citation[i] %||% ""))
    warnings <- c(warnings, sprintf("%s: no citation yet; it will appear after the DOI lookup runs", row_label(i)))
  oy <- m$oa_year[i]
  if (has_doi && !is.na(oy) && nzchar(oy) && grepl("^\\d{4}$", pubs$year[i]) && oy != pubs$year[i])
    warnings <- c(warnings, sprintf("%s: year %s, publisher record says %s", row_label(i), pubs$year[i], oy))
}
dup <- pubs$doi[nzchar(pubs$doi) & duplicated(pubs$doi)]
for (d in unique(dup)) errors <- c(errors, sprintf("DOI %s is listed more than once", d))

if (length(warnings)) cat(sprintf("WARNINGS (%d):\n%s\n\n", length(warnings), paste0("  ", warnings, collapse = "\n")))
if (length(errors)) {
  cat(sprintf("ERRORS (%d) - fix publications.csv:\n%s\n", length(errors), paste0("  ", errors, collapse = "\n")))
  quit(status = 1)
}

# ---- assemble the records ------------------------------------------------------------
pick <- function(a, b) ifelse(!is.na(a) & nzchar(a), a, ifelse(is.na(b), "", b))
recs <- data.frame(
  doi      = pubs$doi,
  type     = pubs$type,
  year     = as.integer(pick(pubs$year, m$oa_year)),
  foundational = tolower(pubs$foundational) %in% c("yes", "true", "1", "x"),
  citation = pick(pubs$citation, m$auto_citation),
  url      = pubs$url,
  oa_url   = ifelse(is.na(m$oa_url), "", m$oa_url),
  cited_by = suppressWarnings(as.integer(m$cited_by)),
  stringsAsFactors = FALSE)
recs <- recs[nzchar(recs$citation), ]
recs <- recs[order(-recs$year, tolower(recs$citation)), ]

info <- list(
  updated = format(Sys.Date(), "%d %B %Y"),
  n = nrow(recs),
  has_citations = any(!is.na(recs$cited_by)),
  has_oa = any(nzchar(recs$oa_url)))

json <- toJSON(list(info = info, pubs = recs), auto_unbox = TRUE, na = "null", dataframe = "rows")
json <- gsub("</", "<\\/", json, fixed = TRUE)

tpl <- paste(readLines("site/template.html", encoding = "UTF-8", warn = FALSE), collapse = "\n")
html <- sub("/*__DATA__*/", json, tpl, fixed = TRUE)

dir.create("_site", showWarnings = FALSE)
writeLines(enc2utf8(html), "_site/index.html", useBytes = TRUE)

# full list for download
out <- recs[, c("type", "year", "citation", "doi", "url")]
out$foundational <- ifelse(recs$foundational, "yes", "")
write_csv_utf8(out, "_site/arcticgro_publications.csv")

cat(sprintf("Built _site/index.html: %d publications (%s)\n", nrow(recs),
            paste(sprintf("%s %d", TYPES, as.integer(table(factor(recs$type, TYPES)))), collapse = ", ")))
