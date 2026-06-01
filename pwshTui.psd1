@{
    RootModule           = 'pwshTui.psm1'
    ModuleVersion        = '0.10.0'
    GUID                 = 'd2b8e3a1-7c9d-4e5f-8b2a-1c3d4e5f6e7f'
    Author               = 'Stan Clemance'
    CompanyName          = 'Unknown'
    Copyright            = '(c) 2026 Stan Clemance. All rights reserved.'
    Description          = 'PowerShell 7.4+ TUI library: paginated selectors with fuzzy search and multi-select, nested menus, date / time / timezone pickers, masked / validated / password / Yes-No input, animated spinners, and box rendering. Pure PowerShell, no compiled dependencies.'
    PowerShellVersion    = '7.4'
    FunctionsToExport    = @('Get-PaginatedSelection', 'Read-MaskedInput', 'Read-Password', 'Read-ValidatedInput', 'Read-Number', 'Read-Confirmation', 'Read-Choice', 'Read-Date', 'Read-Time', 'Read-Timezone', 'Read-Phone', 'Read-Email', 'Read-IPv4', 'Read-CIDR', 'Read-URL', 'Show-Spinner', 'Write-Spinner', 'Invoke-NestedMenu', 'Write-TuiBox', 'Measure-FuzzyMatch')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData = @{
        PSData = @{
            Tags         = @('TUI', 'Console', 'Menu', 'FuzzySearch', 'Selector', 'Input', 'Linux', 'Mac', 'Windows', 'CrossPlatform')
            ProjectUri   = 'https://github.com/sclemance/pwshTui'
            ReleaseNotes = @'
0.10.0
- Read-Number: bounded numeric input ([decimal]) with arrow-key
  acceleration. Optional -Prefix / -Suffix decorate the field with
  units ("$", " %", " km/h", " °C"). -Precision 0..6 enables fixed-
  decimal entry; default 0 gives integer behavior. -ThousandsSeparator
  renders and accepts the current culture's grouping separator (en-US
  "10,000,000"; de-DE "10.000.000"). Held Up/Down arrows accelerate
  via a continuous curve: the step grows one order of magnitude per
  second of hold (factor = 10^(holdMs/1000)), which at a ~30Hz
  terminal repeat gives ~30 ticks per decade so the user sees and can
  release at intermediate magnitudes (1, 2, 5, 10, 20, 50, 100, ...).
  Peak step is capped at range / (baseStep * 30) so big ranges still
  reach useful traversal speed; the proximity dampener is linear and
  uses a speed-scaled brake zone (3 * factor * baseStep) so the closing
  rate is geometric (~33% of remaining distance per tick) and braking
  from peak to limit completes in ~20 ticks regardless of range — the
  final max(baseStep, ...) clamp restores single-tick precision so the
  user can stop exactly on a limit. Single taps always move by exactly -Step.
  PageUp/PageDown jump by 10*Step without acceleration. Direct typing
  of digits, '-' (when Min<0), and the culture's decimal point (when
  Precision>0) is gated per-char; other printable chars are silently
  dropped. Pasted content is parsed as a whole number and rejected if
  it does not fit -Precision and [Min,Max]. Internal arithmetic uses
  [decimal] to avoid IEEE-754 drift in display and stepping.

0.9.0
- Templated input wrappers for the most common interactive-input shapes:
  Read-Phone (NA-format masked, wraps Read-MaskedInput), Read-Email,
  Read-IPv4, Read-CIDR, Read-URL (regex-validated, wrap Read-ValidatedInput).
  Each hard-codes the mask/pattern and forwards the relevant subset of the
  underlying widget's parameters. Patterns live in module-private script
  vars ($script:_IPv4Pattern, etc.) so wrappers and demo paths read the
  exact same regex.
- Read-Date: inline Year/Month/Day picker with optional -Calendar grid.
  Tab/Shift+Tab cycles focus across Year → Month → Day → (Calendar grid
  when -Calendar) → Year; Up/Down adjust the focused field (Month wraps
  within year, Day clamps to the month's actual length). Typing a digit
  on Year or Day starts an edit (4-digit Year, 2-digit Day, Enter commits,
  Esc discards); Month is arrow-only. When the calendar grid is focused,
  arrows move the highlighted day by one day / one week (crossing months),
  PgUp/PgDn jump by a month. Dates outside [MinDate, MaxDate] are dimmed
  and act as boundary stops for navigation. Returns [DateTime] (00:00:00
  time) or $null on cancel.
- Read-Time: inline HH:MM picker with optional -ShowSeconds and
  -TwelveHour (adds an AM/PM field with a/p shortcuts). Same selection/
  type mode split as Get-PaginatedSelection — Tab toggles, typing digits
  enters type mode with auto-advance when a field fills (so '1430' lands
  cleanly as 14:30). Returns [TimeSpan] (Days = 0).
- Read-Timezone: thin wrapper over Get-PaginatedSelection -Searchable
  built on [TimeZoneInfo]::GetSystemTimeZones(). Highlights the local
  zone by default; -PreferredTimezones pins a caller-supplied list to
  the top of the results with a leading star marker. Returns
  [TimeZoneInfo].
- Internationalization: new Get-DisplayWidth / Add-DisplayPadding helpers
  measure strings in terminal display columns (East-Asian Wide and
  Fullwidth code points count as 2 cells, ANSI CSI sequences as 0).
  Write-TuiBox uses them so CJK content sizes the box and truncates
  correctly; Read-Date's calendar grid header auto-widens to fit the
  widest day-name in the current locale. Two new translations added:
  ja-JP and zh-CN. Three new localized footer strings (Footer_Field,
  Footer_Adjust, Footer_Edit) across en/fr/de/es/ja/zh.
- Demo localization: demo.ps1 strings live in a separate <culture>/
  demo.Strings.psd1 alongside the library strings. Set-DemoCulture loads
  both files (with en-US fallback for the demo file when a translation is
  missing) and flips Thread.CurrentCulture so DateTimeFormatInfo-driven
  widgets reflect the chosen language. Translations provided for all six
  supported locales (en, fr, de, es, ja, zh).

0.8.0
- Read-Password gains -ShowStrength: live Weak/Fair/Good/Strong
  indicator (color-coded red/yellow/cyan/green) appended to the right
  of the masked input. Score derived from length thresholds (8/12/16)
  + character-class diversity (lower/upper/digit/symbol). Strength is
  scored from a parallel marker-only list ('L'/'U'/'D'/'S' rather than
  the actual chars) maintained in sync with the SecureString — the
  SecureString is never unwrapped to plaintext for scoring. Suppressed
  on the -Confirm second prompt (re-typing has no new info to convey).
- Read-Password gains -StrengthVariable: name (no `$`) of a variable
  in the caller's scope to receive the strength record as a
  [PSCustomObject] with Label / Score / Length / Classes / Color.
  Mirrors -OutVariable / -ElapsedVariable convention. Independent of
  -ShowStrength: one controls on-screen display, the other controls
  programmable capture. Useful for gating downstream policy on score
  (e.g. reject anything below 'Good' from being persisted). Computed
  unconditionally so the cost of -ShowStrength=$false +
  -StrengthVariable is the same as -ShowStrength=$true alone.
- Internal: new private Get-PasswordStrength helper for the scoring;
  Read-Password's $readOne scriptblock now returns a PSCustomObject
  carrying the SecureString and its parallel class list together.

0.7.0
- BREAKING: Write-TuiBox no longer emits the rendered line count to the
  pipeline by default. Pass -PassThru to opt in. Matches the convention
  for Write-* functions whose primary purpose is side effects
  (Add-Member -PassThru, Set-ItemProperty -PassThru). Resolves the demo
  surprise where `Write-TuiBox -Header ... -Body ... -Border` printed a
  stray integer after the box because nothing captured the return.
  Internal callers Get-PaginatedSelection and Invoke-NestedMenu pass
  -PassThru since they use the count for cursor management; standalone
  callers can drop the capture entirely.

0.6.0
- BREAKING: Write-UIBox renamed to Write-TuiBox. Aligns with the
  module's `Tui` namespace (matches Read-* / Show-* / Get-*
  conventions; the standalone `UI` prefix was a leftover from before
  the rename to pwshTui). No backward-compat alias — callers update
  their function name. The function's behavior, parameters (minus the
  removed -AltScreen, see below), and return value are unchanged.
- Removed -AltScreen parameter from Write-TuiBox. The switch was
  declared but never wired up — a vestigial placeholder with doc that
  said "Reserved; the caller controls alt-screen mode." Write-TuiBox is
  a stateless one-shot renderer; alt-screen is a stateful mode toggle
  meaningful only to interactive widgets that own the screen for the
  duration of input (Get-PaginatedSelection / Invoke-NestedMenu still
  have their working -AltScreen). Dropping the dead parameter
  simplifies the API.

0.5.0
- Read-Password: new masked-password prompt returning [SecureString]
  by default ([string] under -AsPlainText). Chars go straight into a
  SecureString from the first keystroke; plaintext never lives in a
  managed buffer. Forward-only typing (Backspace deletes; no cursor
  navigation, matching conventional password UX). -Confirm prompts
  twice and compares via short-lived BSTR unwrap with ZeroFreeBSTR
  cleanup; retries up to -MaxAttempts (default 3). -MinLength /
  -MaxLength enforce bounds. -HideTyping hides chars entirely (not
  even a mask char) to obscure password length.
- Read-Choice: new one-line N-option selector (2-9 options). Arrow
  keys, Tab, Home/End, and digit hotkeys 1-N for navigation. In
  single-select, digit commits immediately (Y/N-style shortcut); in
  -MultiSelect, Space toggles and Enter returns the array of selected
  labels. Uses the shared radio glyphs (●/○ Unicode, [x]/[ ] ASCII)
  for multi-select. Focus shown by cyan bg in color mode, '> ' prefix
  in -NoColor mode (stable column alignment).
- Bracketed-paste protection on text input: Read-Password,
  Read-MaskedInput, and Read-ValidatedInput now enable bracketed paste
  (\e[?2004h) on entry and parse the [200~ ... [201~ sentinels around
  pasted content. Pasted text is validated as a unit instead of
  streaming through the per-keystroke Enter handler. Any control
  character in the paste body rejects the whole paste with a visible
  warning rather than silently mangling the value. Trailing \r/\n is
  treated as the user's Enter press. Critical for Read-Password
  -Confirm, where identically-mangled pastes would otherwise "match"
  each other and lock the user out. Older terminals that don't
  recognize the sequences silently fall back to per-character handling.
- Show-Spinner -ElapsedVariable: stopwatch now always runs (previously
  conditional on -ShowTimer). New -ElapsedVariable <name> parameter
  writes the total elapsed [TimeSpan] to a variable in the caller's
  scope after exit, mirroring -OutVariable / -ErrorVariable style.
  Lets callers compose their own "done in 2.3s" line; the spinner row
  is still erased on exit in VT mode. Module-scope-aware via
  $PSCmdlet.SessionState.PSVariable.Set so it crosses the module
  boundary correctly.
- Internal: Read-KeyOrPaste private helper centralizes bracketed-paste
  protocol parsing (CSI sequence consumption, [200~/[201~ sentinel
  detection, embedded-ESC handling, trailing-newline stripping,
  control-char flagging). Each input function applies its own
  sanitation policy on the structured event the helper returns.

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
