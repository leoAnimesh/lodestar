# Website and custom domain

The landing page is the static folder [`site/`](../site) (plain HTML and CSS, no build step).
[`.github/workflows/pages.yml`](../.github/workflows/pages.yml) uploads it to GitHub Pages on every
push to `main` that touches `site/`. Pages is set to **Source: GitHub Actions**, and the site is
live at <https://leoanimesh.github.io/lodestar/>.

To preview it locally: `python3 -m http.server -d site 8000`, then open <http://localhost:8000>.

## Images

| File | Made from |
| --- | --- |
| `docs/icon.png`, `site/icon.png` (1024 px), `site/icon-512.png` | `Lodestar --render-icon <dir>` (same renderer as the .icns): `icon_512x512@2x.png` and `icon_512x512.png` |
| `site/favicon-32.png`, `site/apple-touch-icon.png` (180 px, opaque) | The 1024 px icon cropped to the tile (832 px centre crop), then scaled |
| `site/assets/hero.webp`, `hero.jpg` | `docs/hero.jpg` at 1600 px |
| `site/assets/{launcher,clipboard,emoji}.webp` | `docs/screenshots/*.png` at 1000 px |
| `site/assets/social-preview.jpg` | Copy of `docs/social-preview.jpg` |

If the icon changes, re-render with `swift build && .build/debug/Lodestar --render-icon /tmp/iconset`
and replace these files.

## Adding a custom domain

Example below uses `lodestar.app`; use whatever you buy. Do these in order.

### 1. Add the domain on GitHub first

This makes GitHub claim the domain for this repository before DNS points at it.

```sh
gh api -X PUT repos/leoAnimesh/lodestar/pages -f cname=lodestar.app
```

Or: repository **Settings › Pages › Custom domain**. Optionally verify the domain for your account
(GitHub **Settings › Pages › Add a domain**) so nobody else's repository can take it over.

**About the `CNAME` file:** with a GitHub Actions deployment (what this repo uses), GitHub ignores a
`CNAME` file; the setting above is what counts. If you want one in the repository anyway, for
documentation or for a later switch to branch deploys, it goes at **`site/CNAME`** and contains just
the domain on one line:

```
lodestar.app
```

### 2. DNS records at your registrar

Apex domain (`lodestar.app`):

| Type | Name | Value |
| --- | --- | --- |
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |
| AAAA | @ | 2606:50c0:8000::153 |
| AAAA | @ | 2606:50c0:8001::153 |
| AAAA | @ | 2606:50c0:8002::153 |
| AAAA | @ | 2606:50c0:8003::153 |
| CNAME | www | leoanimesh.github.io |

A subdomain only (for example `lodestar.example.com`): one `CNAME` record from `lodestar` to
`leoanimesh.github.io`. Don't use wildcard records.

Check with `dig +short lodestar.app` and `dig +short www.lodestar.app`. DNS can take up to a day.

### 3. Enforce HTTPS

Once GitHub has issued the certificate (Settings › Pages shows it, usually within an hour):

```sh
gh api -X PUT repos/leoAnimesh/lodestar/pages -F https_enforced=true
```

### 4. Update the URLs

Replace `https://leoanimesh.github.io/lodestar/` with `https://lodestar.app/` in:

- `site/index.html`: `canonical`, `og:url`, `og:image`, `twitter:image` and every URL in the JSON-LD
  block (`grep -n leoanimesh.github.io site/index.html`)
- `site/robots.txt` (the `Sitemap:` line) and `site/sitemap.xml` (`<loc>`)
- The repository homepage: `gh repo edit leoAnimesh/lodestar --homepage https://lodestar.app`
- The website link near the top of `README.md`, and `homepage` in `Casks/lodestar.rb` if you like
- Any directory listings (openalternative.co, open-source-mac-os-apps, ...) that link to the old URL

The old `leoanimesh.github.io/lodestar/` address keeps working and redirects to the custom domain.

```sh
grep -rn "leoanimesh.github.io/lodestar" site README.md Casks
```
