# ArcticGRO publications

Source for the ArcticGRO publications page: a searchable list of papers that
use data from the Arctic Great Rivers Observatory.

- **`publications.csv`** is the only file you edit.
- A GitHub Action looks up each DOI in [OpenAlex](https://openalex.org), checks
  the list, builds the page and publishes it on GitHub Pages.
- On the 1st of each month another Action searches for new papers that cite or
  mention ArcticGRO and opens an issue listing them for review.

## Adding a publication

Edit `publications.csv` on GitHub (open the file, click the pencil icon, add a
line, commit). The page updates a few minutes later.

| Column | What to enter |
|---|---|
| `doi` | The DOI, e.g. `10.1038/s41561-026-01960-z` (without `https://doi.org/`) |
| `type` | `Primary`, `Secondary` or `Tertiary` |
| `year` | Publication year. Optional when there is a DOI (taken from the publisher's record) |
| `foundational` | `yes` to list it under Foundational publications |
| `citation` | The citation as it should appear. Optional when there is a DOI: left empty, it is written from the publisher's record |
| `url` | A link for entries without a DOI (report, PDF) |
| `note` | Internal notes; not shown on the page |

You can also edit it in Positron, VS Code or Excel. In Excel, save with
**File > Save As > CSV UTF-8 (Comma delimited)**; other CSV options turn
accented letters, curly quotes and dashes into symbols like `‚Äú`.

A row with only a DOI and a type is enough:

```
10.1029/2025jg009999,Tertiary,,,,,
```

### Publications without a DOI

Reports, book chapters and older papers sometimes have no DOI. Fill in
`year`, `citation` and, if there is one, `url`, and leave `doi` empty:

```
,Secondary,2011,,"Overduin, P.P., ... (2011). State of the Arctic Coast 2010 ...",https://csdms.colorado.edu/w/images/State_of_the_arctic_report2010.pdf,
```

These rows are shown exactly as typed, with the link. Without a DOI they get no
open-access link or citation count, and the monthly search cannot find them
(and cannot mistake them for new papers either). If a DOI appears later, add
it to the row.

## Checks

The build stops, and the page is not changed, if a row has an unknown type, a
malformed DOI, a DOI listed twice, or no year/citation where one is needed. The
error message names the row; the GitHub Actions log shows it.

Warnings do not stop the build. The main one is a year in `publications.csv`
that differs from the publisher's record (often online-first vs print year).

## Preview on your computer

```r
install.packages(c("httr2", "jsonlite"))
source("R/fetch_metadata.R")   # optional: DOI lookups (needs internet)
source("R/build_site.R")       # writes _site/index.html
browseURL("_site/index.html")
```

## One-time setup

1. Push this folder to a public repository, e.g. `whrc/arcticgro-publications`.
2. **Settings > Pages > Build and deployment > Source: GitHub Actions.**
3. Optional: **Settings > Secrets and variables > Actions > Variables**:
   `OPENALEX_EMAIL` = a contact email (OpenAlex answers faster for identified users).
4. **Actions > Build publications page > Run workflow.** The page appears at
   `https://whrc.github.io/arcticgro-publications/`.

## On the WordPress site

Link to the GitHub Pages address, and/or embed it in the Publications page:

```html
<iframe src="https://whrc.github.io/arcticgro-publications/"
        style="width:100%; height:1800px; border:0;" title="ArcticGRO publications"></iframe>
```

Search engines index the list under the GitHub Pages address, not under
arcticgreatrivers.org. Linking to it directly from the site helps people find it.

## Files

```
publications.csv            the list (edit this)
metadata/openalex.csv       DOI lookups, updated by the Action (don't edit)
R/fetch_metadata.R          DOI lookups in OpenAlex
R/build_site.R              checks and builds _site/index.html
R/find_new.R                monthly search for new papers
R/utils.R                   shared helpers
site/template.html          page layout, styles and interactivity
.github/workflows/          build + monthly search
```
