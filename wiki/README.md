# Wiki source for Ubuntu-CAC

The markdown files in this directory are the source for the [GitHub wiki](https://github.com/dainjaruss/Ubuntu-CAC/wiki).

## Adding screenshots

Screenshots are **linked to specific steps** in the wiki. Use the detailed capture guide so you know exactly what to run and what to capture.

1. Open **[Screenshot-Guide.md](Screenshot-Guide)** (in the wiki folder or on the wiki after deploy). It lists every screenshot with:
   - **Exact filename** to save (e.g. `quick-start-cac-setup-menu.png`)
   - **Wiki page and step** where it appears
   - **What to run** (command or menu/UI path) to get to that step
   - **When to capture** and **what should be visible** in the shot
2. For each screenshot: run the action described, capture the screen, and save the file in **`wiki/images/`** with the exact filename from the guide.
3. Run `./scripts/deploy-wiki.sh` from the repo root to push pages and images to the GitHub wiki.

The wiki markdown already embeds `![...](images/filename.png)` at the right steps; you only add the image files with the correct names.

## Publish the wiki

1. **Initialize the wiki on GitHub** (one-time, if not already done):
   - Open [`https://github.com/dainjaruss/Ubuntu-CAC`](https://github.com/dainjaruss/Ubuntu-CAC)
   - Click **Wiki** → **Create the first page**
   - Use any title (e.g. "Home") and save. This creates the wiki repo.

2. **Deploy from this repo:**

   ```bash
   cd /path/to/Ubuntu-CAC   # or CaC
   ./scripts/deploy-wiki.sh
   ```

   The script clones the wiki repo, copies `wiki/*.md` into it, commits, and pushes.

To edit the wiki later, either change the files in `wiki/` and run `deploy-wiki.sh` again, or edit pages directly on GitHub.
