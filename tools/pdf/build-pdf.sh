#!/usr/bin/env bash
#
# Build the OSPA specification PDF from Markdown, following the 2024 OCP Base
# Specification Template (v1.6): template font, running header/footer, a ToC
# with page numbers, and no header/footer on the title page.
#
# Usage: tools/pdf/build-pdf.sh [input.md] [output.pdf]
#   defaults: spec/main/OCP_OSPA_Spec.md -> build/OCP_OSPA_Spec_<revision>.pdf
#   where <revision> comes from the version line ("X.Y.Z") on the title page.
#   An explicit output.pdf is used as given.
#
# Requires pandoc and xelatex. Set OSPA_PDF_FONT to override the font.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

input="${1:-${repo_root}/spec/main/OCP_OSPA_Spec.md}"
if [[ ! -f "${input}" ]]; then
    echo "error: input file not found: ${input}" >&2
    exit 1
fi

# The title page carries the version as a line of its own, "X.Y.Z" (the
# template's <Version>.<Revision>.<Errata>); "Revision X.Y.Z" is also accepted.
revision="$(sed -n -E 's/^(Revision[[:space:]]+)?([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*$/\2/p' "${input}" | head -n 1)"
if [[ -n "${revision}" ]]; then
    default_name="$(basename "${input%.md}")_${revision}.pdf"
else
    echo "warning: no 'X.Y.Z' version line found in ${input}; output name has no version" >&2
    default_name="$(basename "${input%.md}").pdf"
fi
output="${2:-${repo_root}/build/${default_name}}"

for tool in pandoc xelatex python3; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "error: ${tool} is required but not installed" >&2
        exit 1
    fi
done

# The OCP template font is Arial; Liberation Sans is metric-compatible with it.
# OCP review accepts Calibri (or the metric-compatible Carlito) when the
# template font is unavailable. DejaVu Sans is a last resort.
pick_font() {
    local font
    for font in "Arial" "Liberation Sans" "Calibri" "Carlito" "DejaVu Sans"; do
        if fc-list : family 2>/dev/null | tr ',' '\n' | grep -qx "${font}"; then
            echo "${font}"
            return
        fi
    done
}

font="${OSPA_PDF_FONT:-$(pick_font)}"
if [[ -z "${font}" ]]; then
    echo "error: no suitable font found; install Arial or Liberation Sans, or set OSPA_PDF_FONT" >&2
    exit 1
fi
case "${font}" in
    "Arial"|"Liberation Sans") ;;
    "Calibri"|"Carlito")
        echo "note: Arial/Liberation Sans not found; using '${font}' (accepted by OCP review, but not the template font)" >&2 ;;
    *)
        echo "warning: Arial/Liberation Sans not found; using '${font}', which does not match the OCP template" >&2 ;;
esac

# Monospace font for inline code, matching the main font family where possible.
monofont=""
for candidate in "Liberation Mono" "DejaVu Sans Mono"; do
    if fc-list : family 2>/dev/null | tr ',' '\n' | grep -qx "${candidate}"; then
        monofont="${candidate}"
        break
    fi
done
monofont_opt=()
[[ -n "${monofont}" ]] && monofont_opt=(--variable=monofont:"${monofont}")

mkdir -p "$(dirname "${output}")"
log="${output%.pdf}.log"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
tex="${work}/spec.tex"

# Reader choice:
#   * gfm_auto_identifiers gives headings GitHub-style ids (e.g.
#     #61-bmc--host-connectivity), so links written for GitHub also resolve in
#     the PDF. Pandoc's default ids strip leading section numbers.
#   * The markdown reader is used instead of -f gfm because pandoc's gfm reader
#     does not wrap table cells, which pushes wide tables off the page. The
#     markdown reader sizes pipe-table columns from the separator row widths.
# Pandoc writes LaTeX rather than the PDF directly, so ocp-tables.py can give
# every table a full grid before xelatex runs.
pandoc "${input}" \
    --from=markdown+gfm_auto_identifiers \
    --to=latex \
    --standalone \
    --lua-filter="${script_dir}/ocp-spec.lua" \
    --include-in-header="${script_dir}/ocp-header.tex" \
    --variable=papersize:letter \
    --variable=fontsize:11pt \
    --variable=mainfont:"${font}" \
    "${monofont_opt[@]}" \
    --variable=colorlinks:true \
    --variable=linkcolor:ocpblue \
    --variable=urlcolor:ocpblue \
    --variable=toccolor:black \
    --output="${tex}" >"${log}" 2>&1 || {
        echo "error: pandoc failed; see ${log}" >&2
        exit 1
    }

python3 "${script_dir}/ocp-tables.py" "${tex}" >>"${log}" 2>&1 || {
    echo "error: table post-processing failed; see ${log}" >&2
    exit 1
}

# Run xelatex from the input's directory so relative image paths resolve.
# Rerun until the ToC, page references, and longtable widths are stable.
for pass in 1 2 3 4; do
    if ! (cd "$(dirname "${input}")" &&
          xelatex -interaction=nonstopmode -halt-on-error \
              -output-directory="${work}" "${tex}") >"${work}/xelatex.out" 2>&1; then
        cat "${work}/spec.log" >>"${log}" 2>/dev/null || cat "${work}/xelatex.out" >>"${log}"
        echo "error: xelatex failed; see ${log}" >&2
        exit 1
    fi
    grep -q -E "Rerun to get|Label\(s\) may have changed|Table widths have changed" "${work}/spec.log" || break
done
cat "${work}/spec.log" >>"${log}"
cp "${work}/spec.pdf" "${output}"

if grep -q "Missing character" "${log}"; then
    echo "warning: font '${font}' lacks some characters used in the spec:" >&2
    grep "Missing character" "${log}" | sort -u >&2
fi

if grep -q "Overfull \\\\hbox" "${log}"; then
    echo "warning: some lines run past the page margin (e.g. a narrow table column); see 'Overfull \\hbox' in ${log}" >&2
fi

echo "wrote ${output} (font: ${font})"
