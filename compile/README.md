# hasknote-compile

Turns a hasknote notebook (`.hs` with `---HS` / `---HF` code cells and `---MS` / `---MF`
markdown cells) into

- `name.html`: a self-contained, interactive page (Plotly charts, embedded fonts, KaTeX);
- `name.tex` + `name-figures/`: a clean LaTeX source with vector chart PDFs;
- `name.pdf`: the result of compiling that `.tex` with pdfLaTeX.

```sh
hasknote-compile urep.hs                    # html + tex + figures + pdf next to the notebook
hasknote-compile urep.hs -o /tmp/out --title "Problem Set 3" --subtitle "Hansen (1985)" --author "Agustín"
hasknote-compile urep.hs --html-only        # just the HTML
hasknote-compile urep.hs --tex-only         # .tex + figures, no LaTeX run
hasknote-compile urep.hs --pdf-only         # .tex + figures + PDF (no HTML)
hasknote-compile --md-snippet in.md -o out.png [--width 760]   # Neovim preview (below)
```

Rebuild the PDF by hand after editing the `.tex` (from its directory):

```sh
pdflatex urep.tex && pdflatex urep.tex      # two runs: contents and references
```

Other options: `--short-title` (PDF running header), `--date` (default today, `''` omits),
`--hide-code`, `--no-prose`, `--no-panels`, `--keep-plot-style`, `--inline-plotly`
(offline HTML, +3.5 MB), `--budget MS` (Chromium virtual-time budget).
`~/.local/bin/hasknote-compile` may be a symlink; assets resolve next to the real script.

## Notebook conventions

- `----HS# Title` / `HS##` / `HS###` start numbered sections. Markdown headings in MS cells
  (`#`, `##`, `###`) are the same thing: one numbering and one table of contents, in document
  order (the contents appear when there are at least two headings).
- MS cells are CommonMark (lists, emphasis, links, block quotes, tables, fenced code) plus
  `$…$` / `$$…$$` math. Everything between `MF` and the next `HS`/`MS` (editor preview lines
  such as `[img] …`) is ignored.
- Title block: `--title` or a `-- title: …` comment at the top of the first cell (also
  `-- subtitle:`, `-- author:`, `-- date:`); otherwise the humanized file name.
- Leading `--` comments of a code cell become prose (short ones become small-caps run-in
  headings); comments that look like code stay in the code.
- A cell with only `:set` / `:add` / `:module` / `import` lines is "setup": collapsed
  (`<details>`) in the HTML and a one-line note in the PDF.
- Outputs are parsed and typeset: hmatrix matrices and tuples of matrices as bracketed
  matrices (4 significant digits, |x| < 1e-12 shown as 0), number lists as row vectors,
  `("Name",(x,y),(z,w))` lines as a booktabs table, GHCi noise (`Ok, n modules loaded.`,
  `[1 of 8] Compiling …`) dropped, lines hard-wrapped by the terminal rejoined. The HTML keeps
  the raw text behind a "raw" toggle and in hover titles. Anything unparsable stays verbatim.
- `[html] path` (Plotly pages, relative paths resolve against the notebook) and
  `[plot] path.vl.json` markers become figures; a cell's consecutive charts form a panel
  figure (a), (b)…; the plot title becomes the caption (fallback: the cell's first prose
  line). Missing files render as "Chart not available".

## How it works

- **HTML**: Latin Modern (LM Roman 10/12/17 and Caps) for the text and FiraCode Nerd Font for
  the code, both subset to WOFF2 and embedded as base64. Plotly traces/layout are inlined;
  plotly.js 2.35.2 loads from jsDelivr. The chart template is replaced with the page's
  academic one (white, boxed axes, Paul Tol muted colours, LaTeX serif) unless `--keep-plot-style`.
- **PDF**: `name.tex` uses `lmodern`, amsmath, booktabs, fancyvrb (Pygments colours identical
  to the HTML; long lines wrapped in Python with a hanging indent), subcaption, fancyhdr
  (running short title and page numbers), hyperref. Each chart is drawn once in headless
  Chromium, exported with `Plotly.toImage(…, {format: "svg"})` and converted with
  `rsvg-convert -f pdf`, so figures are vector with Latin Modern text.
- **Why pdfLaTeX, not LuaLaTeX**: this TeX Live has no `luaotfload`, so `fontspec` cannot
  load fonts under LuaLaTeX (and XeLaTeX has no format). The code font is converted once
  with `otftotfm` into `~/texmf` (TFM/VF/encoding, `T1hnfira.fd`, a map file; the TrueType
  file is embedded as is). Without it the `.tex` falls back to Latin Modern Mono.
- No Type 3 fonts: the Latin Modern OTFs used by the HTML and the chart SVGs are converted
  once to TrueType outlines (CFF fonts are embedded as Type 3 by Chromium/Skia, which
  zathura/evince/pdf.js render poorly).
- Caches (`~/.cache/hasknote/compile/`): Latin Modern from GUST (`lm/`, `lm-ttf/`), WOFF2
  subsets, KaTeX 0.16.11, plotly.js, a `fonts.conf` used only by `rsvg-convert`.

## Markdown snippet renderer (Neovim preview)

`hasknote-compile --md-snippet IN.md -o OUT.png [--width 760]` renders a markdown fragment
with the document's prose styling (Latin Modern, KaTeX, white background) at device scale
factor 2, crops it to the content plus 16 px, prints the output path and exits 0. It takes
about 1 s and works offline after the first run (fonts and KaTeX are cached).

## Limitations

- Figures in the PDF are LaTeX floats (`[htbp]`); they stay near their cell but can move to
  the next page.
- Plain characters outside Latin-1 in code are approximated in the PDF (→ λ × … are mapped).
- Vega-Lite charts need network access (CDN) when compiled.
