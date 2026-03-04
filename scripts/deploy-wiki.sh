#!/usr/bin/env bash
# Deploy wiki content from wiki/ to the GitHub wiki repo.
# Prerequisite: On GitHub, open the repo → Wiki → create the first page (e.g. "Home")
# to initialize the wiki. Then run this script from the repository root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WIKI_SOURCE="${REPO_ROOT}/wiki"
WIKI_CLONE="${REPO_ROOT}/.wiki-clone"

cd "${REPO_ROOT}"

if [[ ! -d "${WIKI_SOURCE}" ]]; then
  echo "Error: wiki source directory not found: ${WIKI_SOURCE}" >&2
  exit 1
fi

echo "Cloning wiki repository..."
if [[ -d "${WIKI_CLONE}" ]]; then
  rm -rf "${WIKI_CLONE}"
fi
if ! git clone https://github.com/dainjaruss/Ubuntu-CAC.wiki.git "${WIKI_CLONE}"; then
  echo "Clone failed. If the wiki is not initialized yet:" >&2
  echo "  1. Open https://github.com/dainjaruss/Ubuntu-CAC" >&2
  echo "  2. Click Wiki → Create the first page (e.g. title 'Home') and Save" >&2
  echo "  3. Run this script again." >&2
  exit 1
fi

echo "Copying wiki pages..."
cp -v "${WIKI_SOURCE}"/*.md "${WIKI_CLONE}/"
if [[ -d "${WIKI_SOURCE}/images" ]]; then
  echo "Copying wiki images..."
  mkdir -p "${WIKI_CLONE}/images"
  for f in "${WIKI_SOURCE}"/images/*; do
    [[ -e "$f" ]] && cp -v "$f" "${WIKI_CLONE}/images/"
  done
fi

cd "${WIKI_CLONE}"
git add -A
if git diff --staged --quiet; then
  echo "No wiki changes to commit."
else
  git commit -m "Update wiki from wiki/ in main repo"
  git push origin master
  echo "Wiki pushed successfully."
fi

rm -rf "${WIKI_CLONE}"
echo "Done."
