#!/usr/bin/env python3
"""Give every table in pandoc's LaTeX output a full grid, as in the OCP template.

Pandoc renders tables in booktabs style: three horizontal rules and no vertical
rules, which makes dense tables hard to read. This rewrites each longtable in
place so that every cell has a border:

  * the column spec gets a vertical rule before, between, and after the
    columns, and relative column widths are reduced to make room for them;
  * \\toprule and \\midrule become \\hline, every body row is followed by
    \\hline, and \\bottomrule is dropped (the last row's \\hline replaces it);
  * header cells are set in bold, as in the template.

pandoc 2.14's Lua API cannot render a table to LaTeX (pandoc.write is
missing), so this runs on the generated .tex file instead.

Usage: ocp-tables.py file.tex   (the file is rewritten in place)
"""

import re
import sys


def matching_brace(s, i):
    """Index just past the brace group that opens at s[i] == '{'."""
    depth = 0
    for j in range(i, len(s)):
        if s[j] == "{":
            depth += 1
        elif s[j] == "}":
            depth -= 1
            if depth == 0:
                return j + 1
    raise ValueError("unbalanced braces in column spec")


def split_columns(spec):
    """Split a pandoc column spec such as '@{}>{..}p{..}l@{}' into columns."""
    spec = spec.strip()
    if spec.startswith("@{}"):
        spec = spec[3:]
    if spec.endswith("@{}"):
        spec = spec[:-3]
    cols, i = [], 0
    while i < len(spec):
        if spec[i].isspace():
            i += 1
        elif spec[i] == ">":
            # >{prefix}p{width}
            j = matching_brace(spec, i + 1)
            k = matching_brace(spec, j + 1)
            cols.append(spec[i:k])
            i = k
        elif spec[i] in "lcr":
            cols.append(spec[i])
            i += 1
        elif spec[i] in "pmb":
            k = matching_brace(spec, i + 1)
            cols.append(spec[i:k])
            i = k
        else:
            raise ValueError(f"unexpected column spec at: {spec[i:i + 20]!r}")
    return cols


def grid_spec(spec):
    cols = split_columns(spec)
    n = len(cols)

    # Pandoc sizes relative-width columns as (\columnwidth - K\tabcolsep) *
    # fraction, with K = 2(n-1) because the outer padding is removed by @{}.
    # The grid restores the outer padding and adds n+1 rules.
    def widen(m):
        k = int(m.group(1)) + 2
        return rf"(\columnwidth - {k}\tabcolsep - {n + 1}\arrayrulewidth)"

    cols = [re.sub(r"\(\\columnwidth - (\d+)\\tabcolsep\)", widen, c) for c in cols]
    return "|" + "|".join(cols) + "|"


def grid_table(body):
    """Rewrite one longtable body (everything after the column spec)."""
    head, sep, rest = body.partition("\\endhead")
    if not sep:
        # No header row: every row is a body row.
        head, rest = "", body

    # Bold header cells (pandoc wraps each in a minipage).
    head = head.replace(
        "\\begin{minipage}[b]{\\linewidth}\\raggedright",
        "\\begin{minipage}[b]{\\linewidth}\\raggedright\\bfseries",
    )
    head = head.replace("\\toprule", "\\hline").replace("\\midrule", "\\hline")

    rest = rest.replace("\\toprule", "\\hline")
    rest = rest.replace("\\bottomrule\n", "").replace("\\bottomrule", "")
    # Each row ends with "\\" at the end of a line; close it with a rule.
    rest = re.sub(r"\\\\[ \t]*$", r"\\\\ \\hline", rest, flags=re.M)
    return head + sep + rest


def process(tex):
    out, pos = [], 0
    begin = "\\begin{longtable}[]"
    while True:
        i = tex.find(begin, pos)
        if i < 0:
            out.append(tex[pos:])
            break
        spec_start = i + len(begin)
        spec_end = matching_brace(tex, spec_start)
        end = tex.index("\\end{longtable}", spec_end)
        out.append(tex[pos:spec_start])
        out.append("{" + grid_spec(tex[spec_start + 1:spec_end - 1]) + "}")
        out.append(grid_table(tex[spec_end:end]))
        pos = end
    return "".join(out)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    with open(path, encoding="utf-8") as f:
        tex = f.read()
    with open(path, "w", encoding="utf-8") as f:
        f.write(process(tex))


if __name__ == "__main__":
    main()
