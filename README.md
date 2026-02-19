# dotfiles

## Breaking Changes (2026-02-19)

- Renamed submodule path: `modules/GitAliases.Extras` -> `modules/git-aliases-extra`
- Renamed migration script: `tools/migrate-gitaliases-extras.ps1` -> `tools/migrate-git-aliases-extra.ps1`
- Existing local git hooks may still point to the old path and fail

Migration steps:

```powershell
git submodule sync --recursive
git submodule update --init --recursive
.\tools\install-hooks.ps1
```

## Profile installation

Put this in `$PROFILE.CurrentUserAllHosts`:

```powershell
# Microsoft.PowerShell_profile.ps1 (CurrentUserAllHosts)
$dot = Join-Path $HOME 'dotfiles\profile.ps1'
if (Test-Path $dot) { . $dot }
```

## Quality checks

Run both lint and tests:

```powershell
.\tools\ci.ps1
```

Run only lint:

```powershell
.\tools\ci.ps1 -LintOnly
```

Run only tests:

```powershell
.\tools\ci.ps1 -TestOnly
```

## Commit hooks

Install local git hooks:

```powershell
.\tools\install-hooks.ps1
```

Installed hooks:
- `pre-commit` (lightweight no-op)
- `commit-msg` (runs `tools/ci.ps1`)
- hook logic is sourced from `modules/git-aliases-extra/tools/hooks/*` to avoid duplication

Checks are skipped when:
- commit message contains `[skip precommit hook]` or `[skip pch]`
- there are no working tree changes (for example, `git commit --allow-empty ...`)

## Extract git-aliases-extra

Recommended approach: keep this as dotfiles repo and move `modules/git-aliases-extra` to its own repository, then consume it via git submodule at the same path.

Safe migration flow:

1. Run a dry run:

```powershell
.\tools\migrate-git-aliases-extra.ps1 -SubmoduleUrl 'git@github.com:<you>/git-aliases-extra.git' -SubmoduleBranch main -PushSplit
```

2. Apply the migration:

```powershell
.\tools\migrate-git-aliases-extra.ps1 -SubmoduleUrl 'git@github.com:<you>/git-aliases-extra.git' -SubmoduleBranch main -PushSplit -Apply
```

3. Commit resulting changes in this repo (`.gitmodules` + submodule pointer).

Notes:
- `bootstrap.ps1` now initializes submodules automatically if `.gitmodules` exists.
- `profile.ps1` warns with the exact `git submodule update --init --recursive` command if submodules were not initialized.

P.S. You can also install just [git-aliases-extra](https://github.com/PhysShell/git-aliases-extra) without dotfiles as standalone powershell package

## What CI checks

- `PSScriptAnalyzer` linting with `PSScriptAnalyzerSettings.psd1`
- `Pester` tests in `tests\` plus `modules\git-aliases-extra\tests\`
- GitHub Actions matrix on:
  - Windows PowerShell 5.1
  - PowerShell 7

## License

WTFPL. See `LICENSE`.
