# Guidelines

Disjoint's best-practice guidelines for agents and contributors.

## Using these guidelines

Copy this workflow into `.github/workflows/guidelines.yml` in your repo. It runs daily, pulls the latest versions of the guideline files you've picked, and commits them to your repo.

```yaml
name: Sync Disjoint guidelines

on:
  schedule:
    - cron: "17 6 * * *" # daily; use whatever time you prefer
  workflow_dispatch:

permissions:
  contents: write

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: disjointinc/guidelines@v1
        with:
          # Optional. Defaults to every top-level .md file in this repo except
          # README.md (currently: AGENTS.md, CLAUDE.md, CONTRIBUTORS.md).
          files: AGENTS.md, CLAUDE.md, CONTRIBUTORS.md
      - name: Commit any changes
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add -A
          if ! git diff --cached --quiet; then
            git commit -m "chore: sync Disjoint guidelines"
            git push
          fi
```

### Inputs

| Input  | Default                    | Description                                                                                   |
| ------ | -------------------------- | --------------------------------------------------------------------------------------------- |
| files  | all guideline files        | Comma-separated list of files to sync. Any top-level `.md` file in this repo except `README.md`. |
| ref    | `main`                     | Branch, tag, or SHA of this repo to sync from.                                                |
| repo   | `disjointinc/guidelines`   | Source repo, if you want to sync from a fork.                                                 |

### How syncing works

Each synced file is wrapped in a managed block:

```
<!-- disjoint-guidelines:begin -->
--------------------------------------------------
| Disjoint Guidelines, (c) Disjoint, Inc. 2026   |
| See disjoint.com/guidelines for more info.     |
| ...                                            |
--------------------------------------------------

<the guideline>

<!-- disjoint-guidelines:end -->
```

- If the file doesn't exist in your repo, it's created.
- If it exists and contains the block, only the inside of the block is overwritten.
- If it exists without the block, the block is appended to the end of the file.

Your own content outside the block is never touched, so feel free to add repo-specific guidelines before or after it.

### Without the published action

Prefer not to depend on the marketplace action? Run the sync script directly in your workflow:

```yaml
- name: Sync Disjoint guidelines
  run: |
    curl -fsSL https://raw.githubusercontent.com/disjointinc/guidelines/main/sync-guidelines.sh -o sync-guidelines.sh
    bash sync-guidelines.sh --files "AGENTS.md, CLAUDE.md"
```

## Contributing

Contributions are welcome and encouraged! We're dogfooding; see CONTRIBUTORS.md for guidelines.

## Releasing (for maintainers)

The repo is published to the GitHub Actions marketplace via `action.yml`. Cut a GitHub release to publish it, and keep the major tag current so consumers on `@v1` get fixes: `git tag -fa v1 -m v1 && git push -f origin v1`.
