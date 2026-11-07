# hasknote-compile

Compiles a hasknote notebook (`.hs` with `---HS` / `---HF` cells) into a typeset,
self-contained **HTML** page (interactive Plotly charts) and an A4 **PDF** (vector charts).

```sh
./hasknote-compile urep.hs                       # -> urep.html + urep.pdf next to the notebook
./hasknote-compile urep.hs -o /tmp/out --title "Problem Set 3" --author "Agustín"
./hasknote-compile urep.hs --html-only           # or --pdf-only
```

Optional: `ln -s "$PWD/hasknote-compile" ~/.local/bin/` (the script finds `hasknote.css` through the symlink).

Options: `--date TEXT` (default today, `''` omits), `--hide-code`, `--no-prose`,
`--no-panels`, `--keep-plot-style`, `--inline-plotly` (offline HTML, +3.5 MB),
`--budget MS` (chromium virtual-time budget, default 20000).

## Notebook conventions

- `----HS# Title` starts a numbered section (`HS##` subsection, `HS###` ...); a table of contents appears when there are any.
- Leading `--` comment lines of a cell are shown as prose above the code (supports `` `code` ``, `*em*`, `**bold**`, `$math$` via KaTeX). Comments that look like code stay in the code block.
- `[html] path` (Plotly pages from `PlotlyExpress.hs`) and `[plot] path.vl.json` (Vega-Lite) markers become figures; markers wrapped over two lines are rejoined. Consecutive charts of one cell form a panel figure (a), (b), ...; the plot title becomes the caption (fallback: the cell's first prose line). Missing chart files render as "Chart not available".

## How it works

- Plotly traces/layout are parsed out of each page's `Plotly.newPlot(...)` call and inlined as JSON; plotly.js 2.35.2 loads from jsDelivr. The academic template (white, boxed axes, Paul Tol muted colours, EB Garamond) replaces the chart's own template unless `--keep-plot-style`.
- Fonts (EB Garamond, JetBrains Mono) are downloaded once from Google Fonts and embedded as base64; they and plotly.js are cached in `~/.cache/hasknote/compile/`.
- The PDF is the same page in print mode, printed with headless `chromium --print-to-pdf`. Charts are drawn after the fonts load, at a fixed print width with `staticPlot`, so Plotly's SVG becomes vector paths and text (`pdfimages -list` shows no images).

## Limitations

- Output lines that the terminal hard-wrapped in the notebook stay wrapped.
- Vega-Lite and KaTeX load from a CDN, so the PDF needs network access for them.
- Page breaks avoid splitting figures and code blocks, which can leave white space at the bottom of a page.
