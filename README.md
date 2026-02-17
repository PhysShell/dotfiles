# dotfiles

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

## Pre-commit hook

Install local git hook:

```powershell
.\tools\install-hooks.ps1
```

The hook runs `tools/ci.ps1` before every commit.

## What CI checks

- `PSScriptAnalyzer` linting with `PSScriptAnalyzerSettings.psd1`
- `Pester` tests in `tests\`
- GitHub Actions matrix on:
  - Windows PowerShell 5.1
  - PowerShell 7
