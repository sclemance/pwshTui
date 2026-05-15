@{
    RootModule           = 'pwshTui.psm1'
    ModuleVersion        = '0.4.0'
    GUID                 = 'd2b8e3a1-7c9d-4e5f-8b2a-1c3d4e5f6e7f'
    Author               = 'Stan Clemance'
    CompanyName          = 'Unknown'
    Copyright            = '(c) 2026 Stan Clemance. All rights reserved.'
    Description          = 'PowerShell 7.4+ TUI library: paginated selectors with fuzzy search and multi-select, nested menus, masked / validated / Yes-No input, animated spinners, and box rendering. Pure PowerShell, no compiled dependencies.'
    PowerShellVersion    = '7.4'
    FunctionsToExport    = @('Get-PaginatedSelection', 'Read-MaskedInput', 'Read-ValidatedInput', 'Read-Confirmation', 'Show-Spinner', 'Invoke-NestedMenu', 'Write-UIBox', 'Measure-FuzzyMatch')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData = @{
        PSData = @{
            Tags         = @('TUI', 'Console', 'Menu', 'FuzzySearch', 'Selector', 'Input', 'Linux', 'Mac', 'Windows', 'CrossPlatform')
            ProjectUri   = 'https://github.com/sclemance/pwshTui'
            ReleaseNotes = @'
0.4.0
- Footer + visual cleanup: dropped the "Type to search / Backspace to
  delete" hint line; standardized word-pair labels on '=' (e.g.
  Enter=Select Esc=Cancel); removed colons after arrows; dropped "or
  1-N:" from the nested-menu footer (numeric jump still works).
- Radio-button glyphs for MultiSelect: Unicode `●` / `○` replace the
  `[x]` / `[ ]` markers in Unicode mode (ASCII fallback unchanged), with
  a 2-space gap after the glyph for cleaner row density.
- Two new spinner styles: `Circles` (`○◔◑◕●◕◑◔`, filling-wave at
  ~110ms) and `Pulse` (`· • ● •`, breathing at ~200ms).
- Ctrl+C produces a clean break: [Console]::TreatControlCAsInput = $true
  catches the keypress immediately (previously deferred until next key)
  and rethrows PipelineStoppedException. The finally block runs first
  (cursor restored, alt-screen exited, TreatControlCAsInput restored),
  then PowerShell handles the exception as a normal Ctrl+C — no stack
  trace, clean prompt. Esc remains the soft cancel ($null).
- Localization via Import-LocalizedData: UI strings load from
  <culture>/pwshTui.Strings.psd1 at module import based on $PSUICulture;
  PowerShell walks the culture hierarchy automatically. Ships en-US
  (fallback, also hardcoded as defaults), fr-FR, es-ES, de-DE. Add new
  locales by dropping a same-shaped .psd1 in <culture>/.
- demo.ps1: "Toggle Render Mode" entry threads -Ascii through every
  interactive call so both modes can be previewed live; "Change
  Language" submenu cycles through the four bundled locales (non-
  persistent — module re-import on next demo run resets to
  $PSUICulture).

0.3.0
- Read-Confirmation: dedicated Yes/No prompt. Single-key Y/N for an
  immediate answer; Left/Right/Tab to move highlight; Enter to confirm;
  Esc returns $null. -Default Yes|No controls the initial highlight.
- Get-PaginatedSelection -MultiSelect: Space toggles selection (ASCII
  [x]/[ ] marker), Enter returns an array of toggled items in original
  input order, Esc returns $null. Selection state persists across
  -Searchable filter changes. In -Searchable -MultiSelect, Space
  preempts buffer extension (matches fzf -m behavior).
- Show-Spinner: animated spinner wrapping a scriptblock. Background
  runspace renders the glyph; scriptblock runs on the foreground thread
  in its defining scope, so closures over caller-local variables work
  without -ArgumentList or $using:. Four glyph styles (Braille default,
  Ascii, HalfBlocks, Dots). Optional -ShowTimer appends a live elapsed
  counter with format narrowing per scale: (3.2s) / (2m 34s) / (1h 23m).
- Module-wide virtual-terminal detection cached at import. Interactive
  functions fail fast with a clear, host-named error in non-VT contexts
  (Azure Automation, Windows PowerShell ISE, redirected output) where
  [Console]::ReadKey can't work. Show-Spinner falls back to plain
  bracket log lines in the same contexts so spinner-wrapped scripts
  still run cleanly under automation.
- demo.ps1: refactored to a menu-driven tour. Pick any demo from a
  nested-menu tree; re-run as needed. Covers every exported function.

0.2.0
- Renamed from pwshui to pwshTui (breaking: import name moved).
- Measure-FuzzyMatch rewritten as a pure-PowerShell ensemble: Jaro-Winkler
  replaces Levenshtein, Auto mode uses intent-biased Max of Subsequence + JW
  driven by length-ratio and vowel-sparseness signals.
- Word-aware normalization: structural separators (- _ . / : \) and
  camelCase/PascalCase boundaries split into spaces so word structure is
  visible to all algorithms. Compact fast-path preserves identifier-style
  queries without separators.
- Get-PaginatedSelection: new -SearchThreshold parameter (default 100),
  incremental filtering on buffer extension, unified printable-character
  search key gate.
- Write-UIBox: ANSI-aware truncation preserves inline escape sequences when
  content exceeds the box width.
- Set-StrictMode -Version Latest enabled module-wide.
- Comment-based help on all exported functions; Pester test suite (39 tests).
'@
        }
    }
}
