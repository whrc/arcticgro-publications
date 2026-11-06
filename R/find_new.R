# find_new.R
# Monthly search for NEW papers that may belong on the publications list.
# Nothing is added automatically: the results go into candidates.md, and the
# GitHub Action opens an issue with them for a person to review.
#
# Two searches in OpenAlex, limited to papers published in the last DAYS days:
#   1. papers that cite ArcticGRO's Primary publications
#   2. papers whose title, abstract or full text mention "ArcticGRO" or
#      "Arctic Great Rivers Observatory"
# Papers already in publications.csv are left out.
#
# Many papers cite ArcticGRO work only in passing, which the list does not
# include (see the Tertiary definition), so every candidate needs a look.
#
# Usage:  Rscript R/find_new.R        (DAYS defaults to 45)

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
})
source("R/utils.R")

OPENALEX <- Sys.getenv("OPENALEX_BASE_URL", "https://api.openalex.org")
EMAIL    <- Sys.getenv("OPENALEX_EMAIL", "")
DAYS     <- as.integer(Sys.getenv("DAYS", "45"))
since    <- format(Sys.Date() - DAYS)

pubs <- read_csv_utf8("publications.csv")
known <- tolower(pubs$doi[nzchar(pubs$doi)])
meta <- if (file.exists("metadata/openalex.csv")) read_csv_utf8("metadata/openalex.csv") else NULL
if (is.null(meta)) stop("metadata/openalex.csv not found: run R/fetch_metadata.R first")
primary_ids <- meta$openalex_id[match(tolower(pubs$doi[pubs$type == "Primary" & nzchar(pubs$doi)]), meta$doi)]
primary_ids <- unique(primary_ids[!is.na(primary_ids) & nzchar(primary_ids)])

query <- function(params) {
  out <- list(); cursor <- "*"
  for (page in 1:10) {
    req <- request(paste0(OPENALEX, "/works")) |>
      req_url_query(!!!params, `per-page` = 200, cursor = cursor,
                    select = "id,doi,title,publication_year,publication_date,primary_location,referenced_works") |>
      req_user_agent("ArcticGRO publications page (https://arcticgreatrivers.org)") |>
      req_timeout(60) |> req_retry(max_tries = 3)
    if (nzchar(EMAIL)) req <- req |> req_url_query(mailto = EMAIL)
    resp <- req |> req_perform() |> resp_body_json(simplifyVector = FALSE)
    out <- c(out, resp$results)
    cursor <- resp$meta$next_cursor %||% ""
    if (!nzchar(cursor) || !length(resp$results)) break
  }
  out
}

works <- list(); reason <- list()
# 1. citing Primary papers (OpenAlex accepts up to 50 ids per filter)
for (ids in split(primary_ids, ceiling(seq_along(primary_ids) / 50))) {
  res <- query(list(filter = sprintf("cites:%s,from_publication_date:%s", paste(ids, collapse = "|"), since)))
  for (w in res) {
    n <- sum(sub("^https://openalex.org/", "", unlist(w$referenced_works)) %in% primary_ids)
    if (is.null(works[[w$id]])) works[[w$id]] <- w
    reason[[w$id]] <- c(reason[[w$id]], sprintf("cites %d ArcticGRO primary paper%s", n, if (n == 1) "" else "s"))
  }
}
# 2. mentions ArcticGRO by name
for (term in c("\"Arctic Great Rivers Observatory\"", "ArcticGRO")) {
  res <- query(list(search = term, filter = sprintf("from_publication_date:%s", since)))
  for (w in res) { if (is.null(works[[w$id]])) works[[w$id]] <- w; reason[[w$id]] <- c(reason[[w$id]], "mentions ArcticGRO") }
}

rows <- lapply(names(works), function(id) {
  w <- works[[id]]
  doi <- tolower(sub("^https?://(dx\\.)?doi\\.org/", "", w$doi %||% ""))
  data.frame(doi = doi, title = w$title %||% "", journal = w$primary_location$source$display_name %||% "",
             date = w$publication_date %||% "", reason = paste(unique(reason[[id]]), collapse = "; "),
             mentions = any(grepl("mentions", reason[[id]])),
             n_cited = max(c(0, as.integer(sub("cites (\\d+).*", "\\1", grep("^cites", reason[[id]], value = TRUE))))),
             stringsAsFactors = FALSE)
})
cand <- if (length(rows)) do.call(rbind, rows) else data.frame()
if (nrow(cand)) {
  cand <- cand[!(nzchar(cand$doi) & cand$doi %in% known), ]
  cand <- cand[order(-cand$mentions, -cand$n_cited, cand$date), ]
}

lines <- c(sprintf("Possible new publications (published since %s), found %s.", since, format(Sys.Date())),
           "",
           "Add the ones that belong on the list to `publications.csv` (DOI + type; the citation is filled in automatically), then close this issue.",
           "")
if (nrow(cand)) {
  lines <- c(lines, "| Title | Journal | Published | DOI | Why it was found |", "| --- | --- | --- | --- | --- |",
             sprintf("| %s | %s | %s | %s | %s |", gsub("\\|", "/", cand$title), gsub("\\|", "/", cand$journal),
                     cand$date, ifelse(nzchar(cand$doi), sprintf("[%s](https://doi.org/%s)", cand$doi, cand$doi), ""),
                     cand$reason))
}
writeLines(enc2utf8(lines), "candidates.md", useBytes = TRUE)
cat(sprintf("%d candidate(s) written to candidates.md\n", nrow(cand)))
if (nzchar(Sys.getenv("GITHUB_OUTPUT")))
  cat(sprintf("count=%d\n", nrow(cand)), file = Sys.getenv("GITHUB_OUTPUT"), append = TRUE)
