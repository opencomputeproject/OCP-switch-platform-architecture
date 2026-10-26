# OSPA Specification PDF Builder

`build-pdf.sh` generates the OSPA specification PDF from Markdown, laid out per the
2024 OCP Base Specification Template (v1.6):

- OCP template font (Arial, or the metric-compatible Liberation Sans)
- Centered title page without header, footer, or page number
- Running header ("Open Compute Project • <title>") and footer
  ("Date: <effective date>" and "Page N")
- Template heading styles and page margins
- Table of Contents with page numbers
- Figure captions ("Figure N: ...") from the image alt text
- Tables with a full grid (every cell bordered) and a bold header row

## Prerequisites

- [pandoc](https://pandoc.org/) (tested with 2.14)
- XeLaTeX (TeX Live or MacTeX), including the `fancyhdr`, `float`, and `caption` packages
- `fontconfig` (`fc-list`), used to detect installed fonts
- Python 3, used to post-process tables
- Arial or Liberation Sans font (see [Fonts](#fonts))

On Fedora/CentOS:

```
sudo dnf install pandoc texlive-xetex texlive-fancyhdr texlive-float texlive-caption liberation-sans-fonts
```

On Debian/Ubuntu:

```
sudo apt install pandoc texlive-xetex texlive-latex-extra fonts-liberation
```

On macOS:

```
brew install pandoc
brew install --cask mactex-no-gui
```

## Usage

Run from anywhere in the repository:

```
tools/pdf/build-pdf.sh [input.md] [output.pdf]
```

| Argument     | Default                             |
|--------------|-------------------------------------|
| `input.md`   | `spec/main/OCP_OSPA_Spec.md`        |
| `output.pdf` | `build/<input name>_<revision>.pdf` |

`<revision>` is read from the version line (`X.Y.Z`) on the spec's title page, so
the default output for version 0.9.1 is `build/OCP_OSPA_Spec_0.9.1.pdf`. An
explicit `output.pdf` is used exactly as given.

Examples:

```
# Build the spec to build/OCP_OSPA_Spec_<revision>.pdf
tools/pdf/build-pdf.sh

# Build to a custom location
tools/pdf/build-pdf.sh spec/main/OCP_OSPA_Spec.md /tmp/OCP_OSPA_Spec_0.9.1.pdf

# Build a release artifact (releases/v<YYYYMM>/OCP_OSPA_Spec_<revision>.pdf)
tools/pdf/build-pdf.sh spec/main/OCP_OSPA_Spec.md spec/releases/v202610/OCP_OSPA_Spec_0.9.1.pdf
```

The pandoc/XeLaTeX log is written next to the PDF (e.g. `build/OCP_OSPA_Spec_0.9.1.log`).
The `build/` directory is ignored by git. The script warns if any text runs past
the page margin, which usually means a table column is too narrow (see
[Markdown Conventions](#markdown-conventions)).

## Fonts

The script uses the first installed font from this list:

1. Arial (the OCP template font)
2. Liberation Sans (metric-compatible with Arial)
3. Calibri
4. Carlito (metric-compatible with Calibri)
5. DejaVu Sans

The OCP review accepts Calibri when the template font is unavailable, so the
script prints a note for Calibri/Carlito and a warning for DejaVu Sans. To force
a specific font, set `OSPA_PDF_FONT`:

```
OSPA_PDF_FONT="Liberation Sans" tools/pdf/build-pdf.sh
```

The script also warns if the selected font lacks any character used in the spec.

## Markdown Conventions

The layout relies on the following structure in the spec Markdown:

- Everything before the `## Table of Contents` heading forms the title page. The
  first heading is the document title (also shown in the page header), a line
  `X.Y.Z` is the version (used in the output file name), and a line starting
  with `Effective` supplies the date shown in the page footer.
- The Markdown Table of Contents (up to the next level-1 heading) is kept for
  GitHub rendering but replaced in the PDF by a generated ToC with page numbers.
- Section numbers are written in the heading text (e.g. `## 8.1. ...`), and the
  heading level must match the numbering depth (`#` for `8.`, `##` for `8.1.`,
  `###` for `8.1.1.`), since the ToC is built from heading levels.
- Image paths are resolved relative to the input file's directory.
- An image alone in its paragraph with alt text becomes a numbered figure, with
  the alt text as its caption: `![USB Topology](images/image-09.png)` renders as
  "Figure N: USB Topology". Leave the alt text empty for images without a
  caption (e.g. the logo on the title page).
- Internal links use GitHub-style heading anchors, so they work both on GitHub
  and in the PDF. GitHub lowercases the heading, drops punctuation, and turns
  each space into `-`, so `6.1. BMC & Host Connectivity` becomes
  `#61-bmc--host-connectivity` (note the double dash where `&` was removed).
- Pipe-table column widths in the PDF are proportional to the width of each
  column's `---` separator. If a cell overflows in the PDF, widen that column's
  separator; GitHub rendering is unaffected.
- Keep the Markdown free of LaTeX markup (e.g. `\newpage`) so it renders cleanly
  on GitHub. Put PDF-only layout rules in `ocp-spec.lua` or `ocp-header.tex`.

## Files

| File             | Purpose                                                               |
|------------------|-----------------------------------------------------------------------|
| `build-pdf.sh`   | Entry point: checks tools, selects the font, runs pandoc              |
| `ocp-spec.lua`   | Pandoc filter: builds the title page and replaces the Markdown ToC    |
| `ocp-header.tex` | LaTeX preamble: header/footer, heading styles, ToC depth              |
| `ocp-tables.py`  | Post-processes pandoc's LaTeX to give every table a full grid         |

To change the header/footer text, heading styles, or margins, edit `ocp-header.tex`.
