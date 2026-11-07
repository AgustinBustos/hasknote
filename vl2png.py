# Render a Vega-Lite JSON spec: vl2png.py in.vl.json out.png|out.html
import json, sys
import vl_convert

spec = json.load(open(sys.argv[1]))
spec.setdefault("background", "white")
out = sys.argv[2]
if out.endswith(".html"):
    open(out, "w").write(vl_convert.vegalite_to_html(spec))
else:
    open(out, "wb").write(vl_convert.vegalite_to_png(spec, scale=2))
