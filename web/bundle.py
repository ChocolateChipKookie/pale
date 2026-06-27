#!/usr/bin/env python3
"""Inline the web sources into one self-contained index.html and brotli it.

css/js/worker/favicon are inlined; the wasm is gzipped + base64'd and inflated
in the worker via DecompressionStream. With --enforce, index.html.br is checked
against the budget (only meaningful for a --release=small wasm).

usage: bundle.py INDEX STYLE MAIN WORKER WASM FAVICON OUT_HTML OUT_BR BUDGET [--enforce]
"""
import base64
import gzip
import re
import sys

import brotli


def replace_once(haystack: str, needle: str, replacement: str) -> str:
    if haystack.count(needle) != 1:
        sys.exit(f"bundle: expected exactly one occurrence of {needle!r}")
    return haystack.replace(needle, replacement)


def main() -> None:
    args = sys.argv[1:]
    enforce = "--enforce" in args
    args = [a for a in args if a != "--enforce"]
    (index_p, style_p, main_p, worker_p, wasm_p, favicon_p,
     out_html_p, out_br_p, budget_s) = args
    budget = int(budget_s)

    index = open(index_p, encoding="utf-8").read()
    style = open(style_p, encoding="utf-8").read()
    main_js = open(main_p, encoding="utf-8").read()
    worker = open(worker_p, encoding="utf-8").read()
    wasm = open(wasm_p, "rb").read()
    favicon_b64 = base64.b64encode(open(favicon_p, "rb").read()).decode()

    # wasm -> gzip -> base64. mtime=0 keeps the output reproducible.
    wasm_b64 = base64.b64encode(gzip.compress(wasm, 9, mtime=0)).decode()

    # Worker: inflate the embedded wasm at runtime instead of fetching it.
    worker = replace_once(
        worker,
        "const module = await WebAssembly.instantiateStreaming(fetch(location), {",
        "const gz = Uint8Array.from(atob(WASM_B64), (c) => c.charCodeAt(0));\n"
        "  const bytes = await new Response(\n"
        "    new Blob([gz]).stream().pipeThrough(new DecompressionStream(\"gzip\")),\n"
        "  ).arrayBuffer();\n"
        "  const module = await WebAssembly.instantiate(bytes, {",
    )
    worker = f'const WASM_B64 = "{wasm_b64}";\n' + worker

    # main.js: build the worker from a Blob URL holding the embedded source.
    main_js = replace_once(
        main_js,
        'const worker = new Worker("pale-worker.js");',
        "const worker = new Worker(\n"
        "  URL.createObjectURL(new Blob([WORKER_SRC], { type: \"text/javascript\" })),\n"
        ");",
    )
    # json-encode the worker source into a valid JS string literal.
    import json
    main_js = "const WORKER_SRC = " + json.dumps(worker) + ";\n" + main_js

    # index.html: inline the favicon, the stylesheet and the script.
    html = replace_once(
        index,
        'href="favicon.png"',
        f'href="data:image/png;base64,{favicon_b64}"',
    )
    html = replace_once(
        html,
        '<link rel="stylesheet" href="style.css">',
        "<style>\n" + style + "\n  </style>",
    )
    # Guard against a stray </script> in the inlined JS closing the block early.
    main_inline = re.sub(r"</(script)", r"<\\/\1", main_js, flags=re.IGNORECASE)
    html = replace_once(
        html,
        '<script src="main.js"></script>',
        "<script>\n" + main_inline + "\n</script>",
    )

    data = html.encode("utf-8")
    open(out_html_p, "wb").write(data)

    br = brotli.compress(data, quality=11)
    open(out_br_p, "wb").write(br)

    headroom = budget - len(br)
    print(f"bundle: index.html {len(data):,} B raw | "
          f"index.html.br {len(br):,} B brotli | budget {budget:,} B | "
          f"headroom {headroom:,} B")
    if enforce and len(br) > budget:
        sys.exit(f"bundle: FAIL brotli size {len(br)} B exceeds budget {budget} B")


if __name__ == "__main__":
    main()
