# Vendored files

Served by Lembas itself: the Content-Security-Policy only allows its own scripts and styles, and pages work without
any CDN. `script/vendor` downloads them again and checks them. Never edit these files.

| File | Version | From | SHA-256 | License |
|---|---|---|---|---|
| `alpinejs-csp-3.17.5/cdn.min.js` | Alpine.js CSP build 3.17.5 | https://cdn.jsdelivr.net/npm/@alpinejs/csp@3.17.5/dist/cdn.min.js | `48c170c92032e527cbae71b8ce75cf1f96ca06fa869a6120ef0fe438d8e92c36` | MIT |
| `bootstrap-5.3.8/bootstrap.min.css` | Bootstrap 5.3.8, the CSS only | https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/css/bootstrap.min.css | `d85327d99c7a3ee1f9b5d0500d1370acea3ad2db39c163c2f51f232baedbdede` | MIT |

The CSP build of Alpine.js needs no `unsafe-eval`, at the price of simpler expressions in the templates: no property
assignment, no arrow functions, no globals. The logic lives in `public/js/app.js`. Bootstrap's JavaScript is left out:
it sets style attributes, which the policy refuses, and Alpine.js does what the pages need.
