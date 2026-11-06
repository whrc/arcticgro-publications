# fetch_metadata.R
# Looks up every DOI in publications.csv in OpenAlex (https://openalex.org) and
# saves the results in metadata/openalex.csv. The site uses them for:
#   - open-access links and citation counts
#   - a formatted citation for new rows where the "citation" column is empty
#   - checking that the year in publications.csv matches the publisher's record
#
# Rows without a DOI are skipped: they are shown exactly as typed in
# publications.csv.
#
# If OpenAlex cannot be reached, the existing metadata/openalex.csv is kept, so
# the site can still be built.
#
# Usage (from the repository root):  Rscript R/fetch_metadata.R
# Optional: set OPENALEX_EMAIL to your email (OpenAlex's "polite pool", faster).

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
})
source("R/utils.R")

OPENALEX <- Sys.getenv("OPENALEX_BASE_URL", "https://api.openalex.org")
EMAIL    <- Sys.getenv("OPENALEX_EMAIL", "")
OUT      <- "metadata/openalex.csv"

pubs <- read_csv_utf8("publications.csv")
dois <- unique(tolower(trimws(pubs$doi[nzchar(trimws(pubs$doi))])))
cat(sprintf("%d DOIs to look up\n", length(dois)))

# "Robert Max Holmes" -> "Holmes, R. M."
apa_name <- function(full) {
  parts <- strsplit(trimws(full), "\\s+")[[1]]
  if (length(parts) < 2) return(full)
  last <- parts[length(parts)]
  initials <- paste0(substr(parts[-length(parts)], 1, 1), ".", collapse = " ")
  sprintf("%s, %s", last, initials)
}

auto_citation <- function(w) {
  au <- vapply(w$authorships %||% list(), function(a) apa_name(a$author$display_name %||% ""), "")
  au <- au[nzchar(au)]
  authors <- if (length(au) == 0) "" else if (length(au) == 1) au else
    if (length(au) <= 20) paste0(paste(au[-length(au)], collapse = ", "), ", & ", au[length(au)]) else
      paste0(paste(au[1:19], collapse = ", "), ", … ", au[length(au)])
  b <- w$biblio %||% list()
  src <- w$primary_location$source$display_name %||% ""
  vol <- b$volume %||% ""; iss <- b$issue %||% ""
  pages <- if (nzchar(b$first_page %||% "")) paste0(b$first_page, if (nzchar(b$last_page %||% "") && b$last_page != b$first_page) paste0("–", b$last_page) else "") else ""
  where <- paste0(src, if (nzchar(vol)) paste0(", ", vol) else "", if (nzchar(iss)) paste0("(", iss, ")") else "",
                  if (nzchar(pages)) paste0(", ", pages) else "")
  title <- sub("\\.$", "", w$title %||% "")
  out <- sprintf("%s (%s). %s.", authors, w$publication_year %||% "n.d.", title)
  if (nzchar(where)) out <- paste0(out, " ", where, ".")
  trimws(out)
}

fetch_batch <- function(batch) {
  filter <- paste0("doi:", paste(batch, collapse = "|"))
  req <- request(paste0(OPENALEX, "/works")) |>
    req_url_query(filter = filter, `per-page` = 50,
                  select = "id,doi,title,publication_year,authorships,biblio,primary_location,open_access,cited_by_count") |>
    req_user_agent("ArcticGRO publications page (https://arcticgreatrivers.org)") |>
    req_timeout(60) |> req_retry(max_tries = 3)
  if (nzchar(EMAIL)) req <- req |> req_url_query(mailto = EMAIL)
  resp <- req |> req_perform() |> resp_body_json(simplifyVector = FALSE)
  lapply(resp$results, function(w) data.frame(
    doi        = tolower(sub("^https?://(dx\\.)?doi\\.org/", "", w$doi %||% "")),
    openalex_id = sub("^https://openalex.org/", "", w$id %||% ""),
    oa_year    = as.character(w$publication_year %||% ""),
    oa_title   = w$title %||% "",
    oa_url     = if (isTRUE(w$open_access$is_oa)) w$open_access$oa_url %||% "" else "",
    cited_by   = as.character(w$cited_by_count %||% ""),
    auto_citation = auto_citation(w),
    fetched    = format(Sys.Date()),
    stringsAsFactors = FALSE))
}

result <- tryCatch({
  batches <- split(dois, ceiling(seq_along(dois) / 50))
  rows <- list()
  for (i in seq_along(batches)) {
    rows <- c(rows, fetch_batch(batches[[i]]))
    cat(sprintf("  batch %d/%d done\n", i, length(batches)))
    Sys.sleep(0.2)
  }
  do.call(rbind, rows)
}, error = function(e) {
  message("OpenAlex lookup failed: ", conditionMessage(e))
  NULL
})

if (is.null(result) || !nrow(result)) {
  cat("Keeping the existing", OUT, "\n")
  quit(status = 0)
}

missing <- setdiff(dois, result$doi)
if (length(missing))
  cat(sprintf("Not found in OpenAlex (%d): %s\n", length(missing), paste(missing, collapse = ", ")))
dir.create(dirname(OUT), showWarnings = FALSE)
result <- result[order(result$doi), ]
write_csv_utf8(result, OUT)
cat(sprintf("Saved %s (%d records)\n", OUT, nrow(result)))
