# Wiki source for Ubuntu-CAC

The markdown files in this directory are the source for the [GitHub wiki](https://github.com/dainjaruss/Ubuntu-CAC/wiki).

## Publish the wiki

1. **Initialize the wiki on GitHub** (one-time, if not already done):
   - Open https://github.com/dainjaruss/Ubuntu-CAC
   - Click **Wiki** → **Create the first page**
   - Use any title (e.g. "Home") and save. This creates the wiki repo.

2. **Deploy from this repo:**
   ```bash
   cd /path/to/Ubuntu-CAC   # or CaC
   ./scripts/deploy-wiki.sh
   ```
   The script clones the wiki repo, copies `wiki/*.md` into it, commits, and pushes.

To edit the wiki later, either change the files in `wiki/` and run `deploy-wiki.sh` again, or edit pages directly on GitHub.
