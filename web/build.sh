#!/bin/sh
# Bundle Skylight Isle (web edition) into one self-contained HTML file: dist/skylight-isle.html.
# Libraries live in web/vendor (three, rapier3d-compat, esbuild) and are linked via web/node_modules.
set -e
cd "$(dirname "$0")"
mkdir -p dist
vendor/_esbuild_linux-x64/package/bin/esbuild src/main.js --bundle --format=iife --minify --target=es2020 \
  --legal-comments=none --log-level=warning --outfile=dist/bundle.js
python3 - <<'EOF'
import base64
html = open('index.html').read()
font = lambda w: base64.b64encode(open(f'assets/NotoSans-{w}.woff', 'rb').read()).decode()
js = open('dist/bundle.js').read().replace('</script', '<\\/script')
html = html.replace('__FONT_REGULAR__', font('Regular')).replace('__FONT_BOLD__', font('Bold'))
html = html.replace('__SCRIPT__', js)
open('dist/skylight-isle.html', 'w').write(html)
EOF
rm dist/bundle.js
ls -la dist/skylight-isle.html
