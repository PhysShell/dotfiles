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

## Submodule release helper

Use fail-fast release helper for `modules/git-aliases-extra`:

```powershell
.\tools\release-submodule.ps1 -Version 0.1.5
```

What it does:
- runs strict preflight checks before any write/push action;
- optionally runs submodule tests (enabled by default);
- commits submodule changes, creates/pushes `v<version>` tag;
- stages + commits updated submodule pointer in root repo and pushes it.

Useful options:
- skip tests: `-SkipTests`
- custom remotes: `-SubmoduleRemote upstream -RootRemote origin`
- custom commit messages:
  - `-SubmoduleCommitMessage "..."`
  - `-RootCommitMessage "..."`

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

## VSCode utils (vscode_stuff directory)

1. copy_xpath.ps1 - copies XPath for XML element under cursor
    - Example:
    ```xml
    <Root>
        <P1>
            <P2>
                <P3>
                    <TargetElementName id="x">hello</TargetElementName>
                </P3>
            </P2>
        </P1>
    </Root>
    ```
    - Suppose cursor is on TargetElementName
    - Gives Root->P1->P2->P3->TargetElementName
    - See copy_xpath.ps1 for example of setting up tasks.json & keybindings.json
    - P.S although there's some extensions that already provide described functionality I didn't want to use extensions for that specific purpose alone

## Userscripts (userscripts directory)

Tampermonkey scripts. To install one, open its raw URL in the browser; Tampermonkey shows the install page and later pulls updates from the same URL when `@version` is bumped.

1. [github-hide-starred.user.js](https://raw.githubusercontent.com/PhysShell/dotfiles/main/userscripts/github-hide-starred.user.js) - on other people's GitHub profiles hides repositories already in your stars (Stars and Repositories tabs, star lists, pinned) and goes to the next page when the whole page is hidden

## Edge tab recovery (edge-restore directory)

Brings back Edge windows and tabs after a power loss or crash when Edge opens with a single empty tab. Needs Python 3 on `PATH`; works with the `Default` Edge profile.

- `Restore-EdgeTabs.ps1` - reopens every window of the last session that was written before the running Edge started, each window with its tabs in order. `-List` only prints them, `-SessionFile <path>` picks a specific file (a live `Sessions\Session_*` or a backup).
- `Backup-EdgeSessions.ps1` - copies the current session file to `%LOCALAPPDATA%\EdgeSessionBackups\<timestamp>\`, skips unchanged files, keeps the last 48 copies.
- `Install-EdgeSessionBackup.ps1` - registers the `EdgeSessionBackup` scheduled task that runs the backup at logon and every 10 minutes without a console window. `-Uninstall` removes it.

```powershell
.\edge-restore\Install-EdgeSessionBackup.ps1
.\edge-restore\Restore-EdgeTabs.ps1 -List
.\edge-restore\Restore-EdgeTabs.ps1
```

Only the current page of each tab is restored, not its back/forward history.

## License

WTFPL. See `LICENSE`.
