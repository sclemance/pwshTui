# pwshTui

A portable, flexible suite of PowerShell 7.4+ functions designed to provide a clean and consistent console user experience across Linux, Windows, and macOS. 

This library focuses on fast, flicker-free rendering using ANSI escape sequences and provides robust fallbacks for non-color terminals.

## Functions

- [`Get-PaginatedSelection`](#get-paginatedselection) - A powerful interactive selector for arrays or complex objects
- [`Read-MaskedInput`](#read-maskedinput) - Formatted input prompt that enforces structure for fixed-length data (phone, MAC)
- [`Read-ValidatedInput`](#read-validatedinput) - Free-form input field with live regex validation
- [`Read-Number`](#read-number) - Bounded numeric input ([decimal]) with arrow-key acceleration, optional `-Prefix`/`-Suffix` for units, `-ThousandsSeparator` for grouped display, and optional `-Bar` for live progress-bar visualization
- [`Read-Confirmation`](#read-confirmation) - Dedicated Yes/No prompt with single-key or arrow-key navigation
- [`Read-Password`](#read-password) - Masked password prompt that returns a `SecureString` by default
- [`Read-Choice`](#read-choice) - One-line N-option selector with optional multi-select
- [`Read-Date`](#read-date) - Inline Year/Month/Day picker with optional calendar grid
- [`Read-Time`](#read-time) - Inline `HH:MM[:SS] [AM/PM]` time picker
- [`Read-Timezone`](#read-timezone) - Time-zone picker built on `[TimeZoneInfo]::GetSystemTimeZones()`
- [`Read-Phone`](#templated-input-wrappers) - Masked North-American phone input, wraps `Read-MaskedInput`
- [`Read-Email`](#templated-input-wrappers) - Regex-validated email input, wraps `Read-ValidatedInput`
- [`Read-IPv4`](#templated-input-wrappers) - Regex-validated IPv4 address, wraps `Read-ValidatedInput`
- [`Read-CIDR`](#templated-input-wrappers) - Regex-validated IPv4 CIDR notation, wraps `Read-ValidatedInput`
- [`Read-URL`](#templated-input-wrappers) - Regex-validated URL, wraps `Read-ValidatedInput`
- [`Read-Percentage`](#numeric-input-wrappers) - Percentage prompt (0..100) with optional `-Bar` for live progress visualization, wraps `Read-Number`
- [`Read-Temperature`](#numeric-input-wrappers) - Temperature prompt with locale-derived unit default (°C / °F / K), wraps `Read-Number`
- [`Read-Currency`](#numeric-input-wrappers) - Currency-amount prompt with locale-derived symbol and precision (ISO 4217), wraps `Read-Number`
- [`Read-Measurement`](#read-measurement) - Mixed-unit measurement input driven by `units/<family>.psd1` data files (length, etc.), with live conversion display, built on `Read-Number -BufferParser`
- [`Invoke-NestedMenu`](#invoke-nestedmenu) - Hierarchical menu for non-paginated, deep-tree navigation
- [`Write-TuiBox`](#write-tuibox) - The underlying layout engine, also available for standalone use
- [`Measure-FuzzyMatch`](#measure-fuzzymatch) - Utility for fuzzy relevance scoring (powers paginated search)
- [`Show-Spinner`](#show-spinner) - Run a scriptblock with a live animated spinner
- [`Write-Spinner`](#write-spinner) - Emit a log line that persists above an active spinner

---

### `Get-PaginatedSelection`
A powerful interactive selector for arrays or complex objects.

**Features:**
- Keyboard navigation (Up/Down for selection, Left/Right for pagination).
- Smooth rendering using ANSI escape sequences (minimizes flickering).
- Support for wrapping between pages and within pages (`-Wrap`).
- Object-aware: use `-DisplayProperty` to specify which property of an object to display in the menu.
- Clean display logic that prevents artifacts on the screen when navigating between pages of varying lengths.
- **Automatic Truncation:** Long lines are automatically truncated to fit the terminal width, preventing layout breakage and cursor sync issues.
- **Live Search Filtering:** When `-Searchable` is enabled, input is split into two modes — selection (arrows/Enter/Esc, plus `Space` to toggle in `-MultiSelect`) and search (typing feeds the fuzzy-match filter buffer). `Tab` toggles between them; typing any printable character from selection mode also enters search mode. From search mode, `Enter`/`Esc`/`Tab`/arrow keys return to selection mode with the first matching row highlighted — they don't confirm or cancel, press the same key again from selection mode to do that. The dimmed highlight bar makes the active mode visible at a glance.
- **Multi-Select Mode:** When `-MultiSelect` is enabled, `Space` toggles the current row's selection (with a `●`/`○` radio glyph in Unicode mode, `[x]`/`[ ]` in ASCII), and `Enter` returns an array of toggled items in original input order. Selection state persists across search filter changes. `-MinSelections` / `-MaxSelections` cap how many items the user can confirm — out-of-range Enter is silently blocked; toggle-on at the limit is also blocked.

**Parameters:**
- `-Items`: (Required) The array of items to select from.
- `-PageSize`: The number of items to show per page (Default: `10`).
- `-Title`: The header text for the menu (Default: `"Select an item:"`).
- `-DisplayProperty`: If passing objects, the name of the property to display in the list.
- `-Wrap`: (Switch) Enables wrapping from the bottom to the top of a page, and from the last page to the first page.
- `-NoColor`: (Switch) Disables ANSI color highlighting, relying entirely on the `> ` pointer.
- `-InitialIndex`: The 0-based index of the item to select by default. This will automatically calculate and display the correct page.
- `-Searchable`: (Switch) Enables live fuzzy-search filtering. Activates the selection/search mode split described above.
- `-SearchAlgorithm`: Specifies the algorithm used for filtering (`Auto`, `Subsequence`, `JaroWinkler`, `Legacy`). Default: `Auto`.
- `-MultiSelect`: (Switch) Enables multi-selection. `Space` toggles the current row; `Enter` returns an array of selected items (possibly empty) in original input order. `Esc` still returns `$null`, so callers can distinguish cancel (`$null`) from "confirmed nothing" (`@()`).
- `-MinSelections` / `-MaxSelections`: (`-MultiSelect` only) Minimum / maximum number of items that can be confirmed. Both clamp to the item count if higher. Min defaults to 0; Max defaults to the item count.
- `-PreSelected`: (`-MultiSelect` only) Items to pre-check on open. Match by identity (reference equality for objects, value equality for strings) — pass the same item references you got from `-Items`. Items not in `-Items` are silently dropped; capped at `-MaxSelections` if set. Use it for "edit my current selections" flows where the menu opens with the user's existing choices already checked.
- `-Ascii`: (Switch) Swap Unicode glyphs (`←→↑↓`, box-drawing chars) for ASCII fallbacks. See [Rendering Modes](#rendering-modes).

**Shortcuts:**
- `↑` / `↓`: Move selection within the current page (selection mode).
- `←` / `→`: Navigate between pages (selection mode).
- `Enter`: Confirm selection.
- `Esc`: Cancel selection (returns `$null`).
- `Tab`: (When `-Searchable` is used) Toggle between selection mode and search mode.
- `Space`: (When `-MultiSelect` is used) Toggle the current row's selection (selection mode only).
- `Backspace` / printable keys: (search mode, when `-Searchable` is used) Edit the search query.

**Example:**
```powershell
Import-Module ./pwshTui.psd1

$processes = Get-Process | Sort-Object Name
# Start on the 25th process in the list
$selected = Get-PaginatedSelection -Items $processes -PageSize 15 -InitialIndex 24 -Title "Select a Process" -DisplayProperty "ProcessName" -Wrap
if ($selected) {
    Write-Host "You chose: $($selected.ProcessName) (PID: $($selected.Id))"
}
```

---

### `Read-MaskedInput`
A formatted input prompt that enforces structure and restricts keystrokes as the user types. Ideal for fixed-length data like phone numbers or MAC addresses.

**Features:**
- Supports custom masks indicating expected character types.
- Discards invalid keystrokes dynamically (e.g., ignoring letters when a digit is expected).
- Live syntax highlighting indicating the current input slot, hiding the real terminal cursor to prevent visual glitches.
- Returns the cleanly formatted string by default, or the raw input if requested.
- **Paste safety:** uses bracketed-paste mode so pasted content is delivered as one unit; chars run through the same per-slot validation as typed input (so `555-1234` pasted into a phone mask just works — dashes filtered). Any control character in the body rejects the whole paste with a visible warning rather than silently mangling the value.

**Mask Syntax:**
- `#`: Requires a Digit (0-9)
- `a`: Requires a Letter (A-Z)
- `X` or `x`: Requires a Hexadecimal character (A-F, 0-9). `X` forces uppercase, `x` forces lowercase.
- `*`: Allows any visible character

**Parameters:**
- `-Mask`: (Required) The format string (e.g., `(###) ###-####` or `XX:XX:XX:XX:XX:XX`).
- `-Prompt`: The text displayed before the input field (Default: `"Enter value:"`).
- `-Placeholder`: The character used to denote empty slots (Default: `_`).
- `-AllowIncomplete`: (Switch) Allows the user to press `Enter` before filling every slot in the mask.
- `-ReturnRaw`: (Switch) Returns only the typed characters without the static mask characters.
- `-NoColor`: (Switch) Disable ANSI styling. Active cursor slot becomes `[X]`-bracketed instead of color-highlighted. See [Rendering Modes](#rendering-modes).

**Shortcuts:**
- `Left` / `Right`: Move cursor left or right.
- `Home` / `End`: Move cursor to the beginning or end.
- `Backspace`: Deletes the character before the cursor.
- `Delete`: Deletes the character at the cursor.
- `Enter`: Confirms the input (if the mask is fully satisfied, or if `-AllowIncomplete` is used).
- `Esc`: Cancels the input entirely (returns `$null`).

**Example:**
```powershell
Import-Module ./pwshTui.psd1

# Phone Number
$phone = Read-MaskedInput -Mask "(###) ###-####" -Prompt "Enter Phone Number:" -Placeholder "_"

# MAC Address
$mac = Read-MaskedInput -Mask "XX:XX:XX:XX:XX:XX" -Prompt "Enter MAC Address:" -Placeholder "0"
```

---

### `Read-ValidatedInput`
A free-form input field with live Regex validation. Ideal for variable-length but strictly formatted data like Email addresses or IPs.

**Features:**
- Prevents the user from pressing Enter until the input perfectly matches a provided Regular Expression.
- The input text dynamically turns **Green** when valid and **Red** when invalid as you type.
- **Paste safety:** uses bracketed-paste mode so pasted content is delivered as one unit and the existing live regex validation runs on the post-paste buffer. Any control character in the paste body rejects the whole paste with a visible warning. A trailing `\r`/`\n` in the paste is treated as Enter and auto-submits if the buffer matches the pattern.

**Parameters:**
- `-Prompt`: (Required) The text displayed before the input field.
- `-Pattern`: (Required) The Regular Expression string used to validate the input.
- `-AllowEmpty`: (Switch) Allows the user to press Enter on an empty string (returns `$null`).
- `-NoColor`: (Switch) Disable ANSI styling. Cursor becomes `[X]`-bracketed and validity is signaled by a trailing `[OK]`/`[??]` marker instead of red/green coloring. See [Rendering Modes](#rendering-modes).

**Shortcuts:**
- `Left` / `Right`: Move cursor left or right.
- `Home` / `End`: Move cursor to the beginning or end.
- `Backspace`: Deletes the character before the cursor.
- `Delete`: Deletes the character at the cursor.
- `Enter`: Confirms the input (only if it matches the pattern or is empty with `-AllowEmpty`).
- `Esc`: Cancels the input entirely (returns `$null`).

**Example:**
```powershell
Import-Module ./pwshTui.psd1

# IPv4 Address
$ipv4Regex = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
$ip = Read-ValidatedInput -Prompt "Enter IP:" -Pattern $ipv4Regex

# Email Address
$emailRegex = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
$email = Read-ValidatedInput -Prompt "Enter Email:" -Pattern $emailRegex
```

---

### `Read-Number`
A bounded numeric input field for integers or fixed-precision decimals, with arrow-key acceleration, optional unit decoration, and thousands-separator display.

**Features:**
- Live **green** / **red** coloring based on whether the current buffer parses as a number inside `[Min, Max]` at the configured precision.
- **Hold-to-accelerate arrows:** holding `Up` or `Down` grows the step by one order of magnitude per second of hold (`factor = 10^(holdMs/1000)`). At a ~30Hz terminal repeat that's ~30 ticks per decade, so the user actually sees and can release at intermediate step magnitudes (1, 2, 5, 10, 20, 50, ...). Peak step is capped at `range / (BaseStep * 30)` so big ranges still reach useful traversal speed.
- **Speed-scaled brake near limits:** as you approach `Min` or `Max`, a linear dampener with a brake zone of `3 * factor * BaseStep` closes ~33% of the remaining distance per tick — the brake completes in ~20 ticks regardless of how large the range is. Single-tick precision is restored in the last few units.
- **Decimal-clean arithmetic:** internal math uses `[decimal]` end-to-end (not `[double]`), so display and stepping stay exact under `-Precision` and `-ThousandsSeparator`.
- **Unit decoration:** `-Prefix` and `-Suffix` wrap the numeric value with literal strings (`"$"`, `" %"`, `" km/h"`, `" °C"`). The widget renders them but does not measure CJK width — wide-character suffixes are passed through literally.
- **Culture-aware separators:** `-ThousandsSeparator` renders the value using the current culture's grouping (en-US `1,234,567`, de-DE `1.234.567`) and accepts the grouping character during typed input. The decimal mark also follows the current culture.
- **SI-prefix shorthand:** a trailing `k` / `M` / `G` / `T` multiplies the parsed value by `10³` / `10⁶` / `10⁹` / `10¹²` — `1.5M` reads as 1,500,000, `0.5G` as 500,000,000. Case-sensitive (lowercase `k` for kilo per SI; uppercase `K` is NOT accepted to avoid the Kelvin/kibibyte clash). Multi-character byte/bit suffixes (`MB`, `Gb`, etc.) are NOT supported in this release — they'd introduce decimal-vs-binary ambiguity. Range and precision are enforced against the multiplied value, so `1.5k` with `-Max 1000` is rejected as out-of-range; `1.5k` with `-Precision 0` is accepted because `1500` is integer-valued.
- **Paste safety:** bracketed-paste mode delivers pasted content as one unit. Pasted text is parsed as a single number and rejected wholesale (with a visible warning) if it doesn't fit `-Precision` and `[Min, Max]` — matches `Read-ValidatedInput`'s reject-paste convention.
- **`-Bar` visualization:** an optional live progress bar between the prompt and the numeric value, showing where the current value sits between `-Min` and `-Max` (e.g. `Port: [██████░░░░░░░░░░░░░░] 8080`). Works for any bounded range, not just percentages. `-BarWidth` controls width (default 20); `-Ascii` forces `#`/`-` glyphs.
- **`-Decorator` hook:** an optional scriptblock called once per render with the current parsed value; whatever string it returns is written between the prompt and the prefix. The framework's `-Bar` is built on top of this; the hook is exposed publicly so callers can render any value-driven decoration (signal bars, level meters, sparklines, ad-hoc status). When both `-Bar` and `-Decorator` are passed, `-Bar` wins.

**Parameters:**
- `-Prompt`: (Required) The text displayed before the input field.
- `-Min`: (Required) Minimum allowed value (inclusive). `[decimal]`.
- `-Max`: (Required) Maximum allowed value (inclusive). `[decimal]`.
- `-Default`: Initial value. Defaults to `0` if `0` is in `[Min, Max]`, otherwise `Min`.
- `-Step`: The base arrow-key increment (the value the acceleration curve scales). Defaults to `1` when `-Precision 0`; `10^-Precision` otherwise.
- `-Precision`: Decimal places, `0`..`6`. `0` (default) gives integer behavior; typing `.` is rejected.
- `-Prefix`: Literal string shown before the number (e.g. `"$"`). Default: empty.
- `-Suffix`: Literal string shown after the number (e.g. `" %"`, `" km/h"`, `" °C"`). Default: empty.
- `-ThousandsSeparator`: (Switch) Render and accept the current culture's grouping separator.
- `-NoColor`: (Switch) Disable ANSI styling. Cursor becomes `[X]`-bracketed and validity is signaled by a trailing `[OK]`/`[??]` marker instead of red/green coloring. See [Rendering Modes](#rendering-modes).
- `-Decorator`: (`[scriptblock]`) Per-render hook. Invoked with the current parsed value (or last-valid value during transient invalid edits); the returned string is written between the prompt and the prefix. The decorator owns its own ANSI escapes if it wants color.
- `-Bar`: (Switch) Render a live progress bar between the prompt and the numeric value, tracking how far the current value sits between `-Min` and `-Max`. Updates each tick as the value changes. When both `-Bar` and `-Decorator` are passed, `-Bar` wins.
- `-BarWidth`: Bar width in characters, `5`..`80`. Default: `20`. Only meaningful with `-Bar`.
- `-Ascii`: (Switch) Force ASCII bar glyphs (`#`/`-`) instead of Unicode (`█`/`░`). Defaults to `$script:_AsciiMode` (env var `PWSHTUI_ASCII`). Only meaningful with `-Bar`.
- `-BufferParser`: (`[scriptblock]`) Replace the built-in buffer-validation path. Invoked with the current buffer string; must return `@{ Ok; Value; Reason }`. When set, the per-character typing filter relaxes — any non-control printable character is accepted and the parser becomes the sole arbiter of validity (same "type anything, regex decides" model as `Read-ValidatedInput`). `-Min` / `-Max` remain meaningful for arrow-key navigation, `PageUp`/`PageDown` clamping, and the `-Bar` fill ratio, so the parser's returned `Value` must use the same units. Canonical consumer is [`Read-Measurement`](#read-measurement), which uses it to accept mixed-unit input like `12ft 3in`.

**Shortcuts:**
- `Up` / `Down`: Increment / decrement by the (accelerated) step; clamps to `[Min, Max]`. Held arrows accelerate continuously.
- `PageUp` / `PageDown`: Jump by `10 * Step` without acceleration — predictable big-step escape hatch.
- `Left` / `Right`: Move cursor within the buffer.
- `Home` / `End`: Move cursor to the beginning or end of the buffer.
- `Backspace` / `Delete`: Edit the buffer.
- Digit keys: Insert at cursor.
- `-`: Only at buffer position 0 and only when `Min < 0`; otherwise rejected.
- `.` (or the current culture's decimal mark): Only when `-Precision > 0` and only once; otherwise rejected.
- Thousands separator: Only when `-ThousandsSeparator` is on.
- `k` / `M` / `G` / `T` (SI multiplier): Only at end of buffer, only once, only after a digit. Case-sensitive (lowercase `k`).
- Other printable characters: Silently dropped.
- `Enter`: Commit if the buffer parses and is in range.
- `Esc`: Cancel (returns `$null`).

**Example:**
```powershell
Import-Module ./pwshTui.psd1

# Port number
$port = Read-Number -Prompt 'Port:' -Min 1 -Max 65535 -Default 8080

# Volume slider with a live bar (works on any range, not just percentages)
$volume = Read-Number -Prompt 'Volume:' -Min 0 -Max 11 -Default 7 -Bar

# Percentage with a suffix
$pct = Read-Number -Prompt 'Coverage:' -Min 0 -Max 100 -Suffix ' %'

# Currency-like field — two decimals, dollar prefix, grouped display
$amount = Read-Number -Prompt 'Amount:' -Min 0 -Max 1000000000 `
    -Precision 2 -Prefix '$' -ThousandsSeparator
```

---

### `Read-Confirmation`
A dedicated Yes/No prompt with single-key answer or arrow-key navigation.

**Features:**
- Single-key `Y` or `N` for an immediate answer (case-insensitive).
- Arrow / `Tab` navigation between buttons for users who prefer to confirm with `Enter`.
- Configurable default highlight — `-Default No` is the safer choice for destructive prompts.
- Returns `$true` / `$false` for the answer, or `$null` on cancel — so `if (Read-Confirmation ...)` only fires on an explicit Yes.

**Parameters:**
- `-Question`: (Required) The yes/no question displayed before the buttons.
- `-Default`: Which button (`Yes` or `No`) is highlighted on open and chosen if `Enter` is pressed without moving. Default: `No`.
- `-NoColor`: (Switch) Disable ANSI styling. The highlighted option becomes `[Yes]` / `[No]` bracketed instead of color-highlighted. See [Rendering Modes](#rendering-modes).

**Shortcuts:**
- `Y` / `N`: Immediate Yes/No answer (case-insensitive).
- `←` / `→` / `Tab`: Move the highlight between buttons.
- `Enter`: Confirm the currently highlighted button.
- `Esc`: Cancel (returns `$null`, distinguishable from a `No` answer).

**Example:**
```powershell
Import-Module ./pwshTui.psd1

if (Read-Confirmation -Question "Delete the file?" -Default No) {
    Remove-Item ./important.txt
}
```

---

### `Read-Password`
A masked password prompt that returns a `SecureString` by default. Cursor navigation (arrow keys, Home/End) is intentionally disabled, matching conventional password-field UX — only typing and Backspace are accepted.

**Features:**
- Characters go straight into a `SecureString` from the first keystroke — plaintext never lives in a managed `List[char]` or `string` buffer.
- Optional twice-prompt confirmation with constant-time-ish comparison via short-lived BSTR unwrap (BSTRs zeroed in `finally`).
- **Paste safety (bracketed-paste protocol):** pasted content is delivered as one unit, not character-by-character — so an embedded newline in a clipboard value cannot truncate the password mid-stream. If the paste body contains any control characters, the entire paste is rejected with a visible warning rather than silently mangled. With `-Confirm` this prevents the worst failure mode: identically-mangled pastes that "match" each other but don't match the source-of-truth password, locking the user out of whatever they just provisioned.
- Trailing `\r`/`\n` in a paste is treated as the user's Enter press (matches the natural "paste, then submit" UX from password managers).
- `-Confirm` retries on mismatch up to `-MaxAttempts` (default 3); returns `$null` once exhausted.

**Parameters:**
- `-Prompt`: Label shown before the password field. Default: `"Password:"`.
- `-MaskChar`: Character displayed for each typed character. Default: `*`.
- `-HideTyping`: (Switch) Show nothing as the user types — not even a mask char. Hides the password length from observers.
- `-MinLength`: Minimum length before `Enter` is accepted. Default: `1`.
- `-MaxLength`: Maximum length. Additional keystrokes are ignored once reached. `0` (default) means unbounded.
- `-Confirm`: (Switch) Prompt twice and require both entries to match.
- `-ConfirmPrompt`: Label for the confirmation field. Default: `"Confirm password:"`.
- `-MaxAttempts`: Maximum mismatched-confirmation attempts before giving up. Default: `3`.
- `-AsPlainText`: (Switch) Return a `[string]` instead of a `[SecureString]`. The plain text lives in managed memory and may surface in debuggers, crash dumps, or process inspection — prefer the default SecureString when possible.
- `-ShowStrength`: (Switch) Append a live strength indicator (`Weak` / `Fair` / `Good` / `Strong`, color-coded red/yellow/cyan/green) to the right of the masked input. Score is derived from length thresholds (8 / 12 / 16) plus character-class diversity (lower / upper / digit / symbol). Computed from a parallel marker-only class list (`'L'`/`'U'`/`'D'`/`'S'`) — the SecureString is never unwrapped to plaintext for scoring. Suppressed on the `-Confirm` second prompt. Orthogonal to `-StrengthVariable`: this controls on-screen display.
- `-StrengthVariable`: Name (no `$`) of a variable in the caller's scope to receive the final strength record as a `[PSCustomObject]` with `Label` / `Score` / `Length` / `Classes` / `Color`. Mirrors `-OutVariable` / `-ElapsedVariable` convention. Independent of `-ShowStrength`: this controls programmable capture. Useful for gating downstream policy on score (e.g. reject anything below `Good` from being persisted to a password store).
- `-NoColor`: (Switch) Disable ANSI styling.

**Shortcuts:**
- Typing / `Backspace`: append / delete the last character. Cursor navigation is intentionally disabled.
- `Enter`: Submit (if length ≥ `-MinLength`).
- `Esc`: Cancel (returns `$null`).

**Example:**
```powershell
Import-Module ./pwshTui.psd1

# Default: SecureString
$pw = Read-Password -Prompt "Password:" -MinLength 12

# Confirm twice
$pw = Read-Password -Confirm -MinLength 12

# Plain string (less safe but sometimes needed for non-credential string APIs)
$pin = Read-Password -Prompt "PIN:" -HideTyping -MaxLength 6 -AsPlainText

# Live strength indicator + programmable capture
$pw = Read-Password -Prompt "Password:" -ShowStrength -StrengthVariable s -MinLength 8
# After: $s.Label is e.g. 'Strong', $s.Score is 0-6, $s.Classes is 1-4
if ($s.Score -lt 4) { Write-Warning "Password is weaker than recommended ($($s.Label))" }
```

---

### `Read-Choice`
A one-line N-option selector with optional multi-select. Sits between `Read-Confirmation` (always 2 options) and `Get-PaginatedSelection` (long, searchable lists) for the short-inline-pick case.

**Features:**
- 2–9 options on a single line, always numbered (`1.Red  2.Green  3.Blue …`) so digit-key selection is discoverable.
- Arrow keys (`Left`/`Right`/`Tab`) or `Home`/`End` for keyboard navigation.
- Digit `1`–`N` jumps to (and in single-select, commits) the corresponding option.
- `-MultiSelect`: `Space` toggles the focused option's check state; pulls from the module's shared radio glyphs (`●`/`○` Unicode, `[x]`/`[ ]` ASCII). Returns the array of selected labels.
- Focus marker: cyan-bg highlight in color mode; `> ` prefix in `-NoColor` mode so column alignment stays stable as focus moves.

**Parameters:**
- `-Question`: (Required) The question shown before the options.
- `-Options`: (Required) `[string[]]` of 2–9 option labels. Enforced via `ValidateCount(2,9)`.
- `-Default`: Initial focused-option index (0-based). Default: `0`.
- `-MultiSelect`: (Switch) Allow toggling multiple options with `Space`; `Enter` returns an array of selected labels.
- `-PreSelected`: `[int[]]` initial checked indices (0-based) for `-MultiSelect`. Out-of-range indices silently dropped.
- `-NoColor`: (Switch) Disable ANSI styling — focus shown by `> ` prefix instead of cyan highlight.

**Shortcuts:**
- `←` / `→` / `Tab`: Move the focus highlight.
- `1`–`9`: Jump to (and commit, in single-select) the corresponding option.
- `Home` / `End`: Move to first/last option.
- `Space`: (Multi-select only) Toggle the focused option's check state.
- `Enter`: Confirm. Single-select returns the label; multi-select returns the array of selected labels.
- `Esc`: Cancel (returns `$null`).

**Example:**
```powershell
Import-Module ./pwshTui.psd1

# Single-select
$color = Read-Choice -Question "Pick a color:" -Options 'Red','Green','Blue'

# Multi-select with two pre-checked
$toppings = Read-Choice -Question "Toppings:" -Options 'Cheese','Pepperoni','Mushroom','Olives','Onion' -MultiSelect -PreSelected 0,1
# $toppings is e.g. @('Cheese','Mushroom')
```

---

### `Read-Date`
Inline Year/Month/Day picker with optional calendar grid visualization.

**Features:**
- Three fields displayed inline: `2026  May  17`. `Tab` cycles focus through Year → Month → Day (→ Calendar grid when `-Calendar` is set); `Shift+Tab` cycles in reverse. Up/Down adjust the focused value (Month wraps within year; Day clamps to the focused month's actual length, so "Feb 30" can never be a stable state).
- **Year and Day** accept direct digit input: typing a number starts an edit (4-digit Year, 2-digit Day). `Enter` commits the edit, `Esc` discards it, `Tab` commits and advances.
- **Month** is Up/Down only — letters and digits are ignored on the Month field.
- **Calendar mode (`-Calendar`)** renders a culture-aware month grid beneath the fields and becomes its own focus stop in the Tab cycle. When focused, arrow keys move the highlighted day across weeks (and into adjacent months), `PgUp` / `PgDn` jump by a month. Dates outside `[MinDate, MaxDate]` are dimmed and cannot be navigated onto.
- `-MinDate` / `-MaxDate` constrain Up/Down adjustments and calendar-grid navigation — out-of-range moves are silent no-ops, so `Enter` is always confirmable from any reachable state.
- Returns `[DateTime]` with a `00:00:00` time component, or `$null` on cancel.

**Parameters:**
- `-Prompt`: Header text (Default: `"Pick a date:"`).
- `-InitialDate`: `[DateTime]` starting value (Default: today).
- `-MinDate` / `-MaxDate`: `[Nullable[DateTime]]` range constraints. Unset = unconstrained.
- `-Calendar`: (Switch) Render the month grid under the fields and add it to the Tab focus cycle.
- `-NoColor`, `-Ascii`, `-Border`, `-MinWidth`, `-MaxWidth`, `-X`, `-Y`, `-AltScreen`: Standard layout / rendering options. See [Rendering Modes](#rendering-modes) and [Global Layout Parameters](#global-layout-parameters).

**Shortcuts:**
- `Tab` / `Shift+Tab`: Cycle focus across Year, Month, Day, and (when `-Calendar`) the calendar grid.
- `←` / `→`: Move focus within the Year/Month/Day group (shortcut to Tab); when calendar grid is focused, move highlighted day by one.
- `↑` / `↓`: Adjust the focused field; when calendar grid is focused, move highlighted day by one week.
- `PgUp` / `PgDn`: Jump by a month (calendar grid focus only).
- Digits (on Year or Day): Start an edit. `Backspace` trims the buffer.
- `Enter`: Commit the in-progress edit (edit mode), or confirm the date (otherwise).
- `Esc`: Discard the in-progress edit (edit mode), or cancel the picker (otherwise).

**Example:**
```powershell
Import-Module ./pwshTui.psd1

# Inline picker, defaults to today
$dob = Read-Date -Prompt "Date of birth:" -MaxDate (Get-Date)

# Calendar visualization with a constrained range
$schedule = Read-Date -Prompt "Schedule for:" -Calendar `
    -InitialDate (Get-Date).AddDays(7) `
    -MinDate (Get-Date) `
    -MaxDate (Get-Date).AddYears(1)
```

---

### `Read-Time`
Inline `HH:MM[:SS] [AM/PM]` time picker.

**Features:**
- Compact field layout: `14:30` (24-hour) or `02:30 PM` (12-hour, with `-TwelveHour`). Add a seconds field with `-ShowSeconds`.
- Same selection/type mode split as [`Get-PaginatedSelection`](#get-paginatedselection). Selection-mode arrows navigate fields and adjust values; type-mode digits feed the focused field.
- **Auto-advance** when a digit field fills: typing `1430` lands cleanly as `14:30` because the hour field auto-commits and focus shifts to minute mid-type. Typing additional digits past the last field is silently dropped.
- **AM/PM field** accepts `a` and `p` as direct shortcuts (no buffer needed) in both modes; Up/Down in selection mode toggles. Internal time is always stored in 24-hour terms regardless of display mode.
- Returns `[TimeSpan]` (`Days = 0`), or `$null` on cancel.

**Parameters:**
- `-Prompt`: Header text (Default: `"Enter time:"`).
- `-InitialTime`: `[TimeSpan]` starting value (Default: `00:00:00`). Only the H/M/S components are read.
- `-TwelveHour`: (Switch) Display as a 12-hour clock with AM/PM. The returned TimeSpan is still 24-hour.
- `-ShowSeconds`: (Switch) Include a seconds field.
- `-NoColor`, `-Ascii`, `-Border`, `-MinWidth`, `-MaxWidth`, `-X`, `-Y`, `-AltScreen`: Standard layout / rendering options.

**Shortcuts:**
- `←` / `→`: Move focus between fields (selection mode).
- `↑` / `↓`: Adjust the focused field's value (selection mode). On the AM/PM field, either direction toggles.
- `Tab`: Toggle between selection mode and type mode.
- Digits: Enter type mode and feed the focused field (auto-advance when filled).
- `a` / `p` (12-hour mode): Set AM/PM directly without entering type mode.
- `Backspace`: Trim the type buffer (type mode).
- `Enter`: Confirm (selection mode) or commit the type buffer and return to selection mode (type mode).
- `Esc`: Cancel (selection mode) or discard the type buffer and return to selection mode (type mode).

**Example:**
```powershell
Import-Module ./pwshTui.psd1

# 24-hour clock, no seconds
$start = Read-Time -Prompt "Start time:"

# 12-hour clock with seconds, starting at 02:30 PM
$alarm = Read-Time -Prompt "Alarm:" -TwelveHour -ShowSeconds `
    -InitialTime ([TimeSpan]::new(14, 30, 0))
```

---

### `Read-Timezone`
Time-zone picker — thin wrapper over [`Get-PaginatedSelection`](#get-paginatedselection) populated from `[TimeZoneInfo]::GetSystemTimeZones()`.

**Features:**
- Lists every installed system time zone with its `Id` and `DisplayName`.
- Highlights the local zone (`[TimeZoneInfo]::Local`) by default. Override with `-Default <id>`.
- `-PreferredTimezones` pins a caller-supplied list of zone IDs to the top of the results in caller order, marked with a leading `*`. IDs not installed on the current platform are silently skipped — callers don't have to special-case cross-platform differences.
- Inherits paginated-selection's fuzzy search: `Tab` enters search mode, typing filters the list. Returns `[TimeZoneInfo]` or `$null` on cancel.

**Parameters:**
- `-Prompt`: Header text (Default: `"Select a time zone:"`).
- `-Default`: Zone ID to highlight initially (Default: the local zone's ID).
- `-PreferredTimezones`: `[string[]]` of zone IDs to pin to the top.
- `-PageSize`: Items per page (Default: `12`).
- `-NoColor`, `-Ascii`, `-Border`, `-MinWidth`, `-MaxWidth`, `-X`, `-Y`, `-AltScreen`: Pass-through to `Get-PaginatedSelection`.

**Example:**
```powershell
Import-Module ./pwshTui.psd1

# Local zone highlighted, with three common zones pinned to the top
$tz = Read-Timezone -PreferredTimezones 'UTC','America/New_York','Europe/London'

# Pipe straight into TimeZoneInfo APIs
[TimeZoneInfo]::ConvertTime((Get-Date), $tz)
```

---

### Templated input wrappers
Thin opinionated wrappers around [`Read-MaskedInput`](#read-maskedinput) and [`Read-ValidatedInput`](#read-validatedinput) that hard-code the mask or regex for the most common interactive-input shapes. Each forwards the relevant param subset of the underlying widget — for non-default formats (E.164 phone, IPv6 CIDR, custom URL schemes, etc.) use the underlying widget directly with your own mask or pattern.

| Wrapper | Wraps | Format / pattern | Notes |
|---|---|---|---|
| `Read-Phone` | `Read-MaskedInput` | `(###) ###-####` | North American format only. Forwards `-Placeholder`, `-AllowIncomplete`, `-ReturnRaw`, `-NoColor`. |
| `Read-Email` | `Read-ValidatedInput` | `[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}` | Common-practical; not RFC 5322 perfect. Forwards `-AllowEmpty`, `-NoColor`. |
| `Read-IPv4` | `Read-ValidatedInput` | Dotted quad with valid octets (`0`–`255`) | Forwards `-AllowEmpty`, `-NoColor`. |
| `Read-CIDR` | `Read-ValidatedInput` | IPv4 + `/0`–`/32` prefix | IPv4 only. Forwards `-AllowEmpty`, `-NoColor`. |
| `Read-URL` | `Read-ValidatedInput` | `(https?|ftp)://...` (non-whitespace remainder) | "Looks like a URL," not RFC 3986 strict. Forwards `-AllowEmpty`, `-NoColor`. |

All five accept `-Prompt` as the first positional parameter; defaults are `Phone:`, `Email:`, `IPv4 address:`, `CIDR notation:`, `URL:` respectively. Each returns the validated string, or `$null` on cancel.

**Example:**
```powershell
Import-Module ./pwshTui.psd1

$phone = Read-Phone -Prompt 'Customer phone:'
$email = Read-Email -Prompt 'Notification address:' -AllowEmpty
$lan   = Read-CIDR  -Prompt 'LAN range:'
$endpoint = Read-URL -Prompt 'Webhook target:'
```

---

### Numeric input wrappers
Thin opinionated wrappers around [`Read-Number`](#read-number) for the three most common numeric-input shapes. Each derives sensible defaults from the user's region or culture and forwards the relevant param subset of `Read-Number` — for ranges or formats that don't match the wrapper's defaults, use `Read-Number` directly.

| Wrapper | Bounds / format | Locale-derived defaults | Wrapper-specific switches |
|---|---|---|---|
| `Read-Percentage` | `0`..`100`, ` %` suffix | — | `-AsFraction` (returns `value/100`); `-Bar` / `-BarWidth` / `-Ascii` are pass-throughs to [`Read-Number`](#read-number)'s bar |
| `Read-Temperature` | Per-unit terrestrial-weather bounds from `units/temperature.psd1` | `-Unit` from `[RegionInfo]::CurrentRegion`: **Fahrenheit** for US, BS, BZ, KY, PW, FM, MH, LR; **Celsius** elsewhere. Kelvin is opt-in only. | `-Unit Celsius`/`Fahrenheit`/`Kelvin` — per-unit `-Min`/`-Max`/`-Default` can each be overridden independently. Now a thin shim over [`Read-Measurement`](#read-measurement); the per-unit data lives in the family file, not in code. |
| `Read-Currency` | `0`..`999,999,999` default | `-Currency` from `[RegionInfo]::CurrentRegion.ISOCurrencySymbol`. Symbol, decimal places, and prefix/suffix placement derived from the currency's `CultureInfo.NumberFormat` (USD → `$1,234.56`/2dp, EUR under European cultures → `1.234,56 €`/2dp, JPY → `¥1234`/0dp, BHD → 3dp). Unknown ISO codes fall back to literal-prefix + 2dp. | `-Currency <ISO 4217>` — always passes `-ThousandsSeparator`. Captures only; does **not** convert between currencies |

All three accept `-Prompt`, `-Default`, `-Precision`, and `-NoColor` and forward them to `Read-Number`. Each returns a `[decimal]` (or `$null` on cancel) — `Read-Percentage -AsFraction` returns the value divided by 100 (so `75` → `0.75`).

**Bar visualization:** `-Bar` works on any [`Read-Number`](#read-number) range, not just percentages — see its docs for full bar semantics (geometry, glyph selection, color behavior). `Read-Percentage -Bar` is the same feature with `-Min 0 -Max 100` already wired up.

**Example:**
```powershell
Import-Module ./pwshTui.psd1

# Percentage with live bar
$coverage = Read-Percentage -Prompt 'Coverage:' -Default 50 -Bar

# Region-default temperature unit (Celsius outside US/etc., Fahrenheit inside)
$ambient = Read-Temperature -Prompt 'Ambient:'

# Body temperature — override the unit and tighten the bounds
$body = Read-Temperature -Prompt 'Body temp:' -Unit Celsius -Min 30 -Max 45 -Default 37 -Precision 1

# Region-default currency, with two decimals derived from the currency
$price = Read-Currency -Prompt 'Price:' -Default 9.99

# Explicit currency (Japanese yen — no decimals, ¥ prefix)
$jpyPrice = Read-Currency -Prompt 'Price:' -Currency JPY
```

---

### `Read-Measurement`
A mixed-unit numeric input widget. Reads values like `12ft 3in`, `5'11"`, `12.5ft`, or `100cm`, parses them into the family's base unit, and shows a live conversion into the user's preferred unit. The widget itself is unit-agnostic — all measurement knowledge lives in `units/<family>.psd1` data files.

**Architecture — engine + data:**
- The widget, parser, and conversion functions know nothing about feet, meters, or kilograms. They walk whatever the loaded family file gives them.
- Each `units/<family>.psd1` is the single source of truth for that family. Adding a new family means dropping a `.psd1` file — no code change.
- Aliases (`ft`, `in`, `'`, `"`, `°C`, `°F`, …) are recognized *only* because they appear in the loaded family's `Aliases` lists. There is no hardcoded token list.
- `Affine` conversions (e.g. Fahrenheit ↔ Celsius) are first-class via `ToBase = @{ Scale = …; Offset = … }`; pure-ratio conversions (length, mass) use a bare `[decimal]` `ToBase`.
- If the requested family file is missing, the widget falls back silently to plain `Read-Number` behavior — no warnings, no errors.

**Family file schema** (`units/length.psd1`):
```powershell
@{
    Family            = 'Length'
    Base              = 'meter'
    DefaultOutputUnit = @{ Metric = 'meter'; Imperial = 'foot' }
    UnitDefaults      = @{
        meter = @{ Min = 0; Max = 10000; Default = 1 }
        foot  = @{ Min = 0; Max = 32808; Default = 3 }
    }
    Units = @(
        @{ Name = 'meter';      Aliases = @('m','meters');             ToBase = 1.0 }
        @{ Name = 'centimeter'; Aliases = @('cm','centimeters');       ToBase = 0.01 }
        @{ Name = 'foot';       Aliases = @('ft','feet',"'",'′');      ToBase = 0.3048 }
        @{ Name = 'inch';       Aliases = @('in','inches','"','″');    ToBase = 0.0254 }
        # ...
    )
}
```

**Affine convention** (lock once, document everywhere):
- `base_value = (input_value + Offset) * Scale`
- `output    = (base_value / Scale) - Offset`
- A bare numeric `ToBase` is shorthand for `Scale = N; Offset = 0`.

**Parameters:**
- `-Prompt`: (Required) Label shown before the input.
- `-Family`: (Required) Family name. Resolves to `units/<Family>.psd1` (case-insensitive filename match — `-Family Length` finds `length.psd1`).
- `-Min` / `-Max` / `-Default`: Bounds and initial value, expressed in `-OutputUnit`. Required unless `-DefaultsByUnit` is set and the family has a matching `UnitDefaults` entry. Explicit values always win for partial overrides.
- `-OutputUnit`: Unit used for display and the conversion decorator. Defaults to the family's region-derived choice (Metric vs Imperial from `[RegionInfo]::CurrentRegion`).
- `-InputUnit`: Unit assumed for bare numbers without an alias. Defaults to `-OutputUnit` ("I'm typing in the unit I see").
- `-DefaultsByUnit`: (Switch) Pull Min/Max/Default from `UnitDefaults[OutputUnit]` in the family file. Explicit `-Min` / `-Max` / `-Default` still override.
- `-ShowConversion`: (Switch, default on) Render `[≈ value OutputUnit]` between the prompt and the field. Pass `-ShowConversion:$false` to hide.
- `-Precision`, `-Prefix`, `-Suffix`, `-NoColor`, `-Bar`, `-BarWidth`, `-Ascii`: forwarded to [`Read-Number`](#read-number); same semantics.

**Bundled families:**

| Family | Units | Aliases (selected) | Notes |
|--------|-------|-------------------|-------|
| `Length` | meter, centimeter, millimeter, micrometer, decameter, kilometer, inch, foot, yard, mile, nautical-mile, fathom, parsec | `m`, `cm`, `mm`, `µm`, `um`, `dam`, `km`, `in`, `inches`, `"`, `″`, `ft`, `feet`, `'`, `′`, `yd`, `mi`, `NM`, `nmi`, `ftm`, `pc` | Base = meter. Per-region default: Imperial → `foot`, Metric → `meter`. `nautical-mile` = 1852 m exactly (international, ICAO/IMO); `fathom` = 1.8288 m (6 ft). Longest-match-wins resolves `ftm` (fathom) vs `ft` (foot). `parsec` uses the IAU 2015 exact definition (648000/π au ≈ 3.086×10¹⁶ m) — astronomical scale only; pass `-OutputUnit parsec` with custom `-Min`/`-Max` (or `-DefaultsByUnit`) since the meter UnitDefaults' Max=10000 wouldn't fit even a fraction of one. |
| `Temperature` | celsius, fahrenheit, kelvin | `°C`, `C`, `degC`, `°F`, `F`, `degF`, `K` | Base = celsius. Affine `ToBase` for fahrenheit (`Scale=5/9, Offset=-32`) and kelvin (`Scale=1, Offset=-273.15`). Per-region default: Imperial → `fahrenheit`, Metric → `celsius`. Kelvin is opt-in only. This is the family that `Read-Temperature` shims onto. |

**Helpers:**
- `Get-MeasurementFamily` — list bundled families (`.psd1` filenames in `units/`).

**Example:**
```powershell
Import-Module ./pwshTui.psd1

# Region-default unit, default range from units/length.psd1
$distance = Read-Measurement -Prompt 'Distance:' -Family Length -DefaultsByUnit

# Explicit foot range with metric conversion visible:
$height = Read-Measurement -Prompt 'Height:' -Family Length -OutputUnit foot `
    -Min 0 -Max 8 -Default 5.5

# Drop the conversion decorator (numeric-only display):
$thickness = Read-Measurement -Prompt 'Thickness:' -Family Length -OutputUnit millimeter `
    -Min 0 -Max 1000 -Default 12 -ShowConversion:$false
```

**Adding a family:** create `units/<MyFamily>.psd1` matching the schema above. No code change needed — `Read-Measurement -Family MyFamily` resolves it via the loader.

---

### `Invoke-NestedMenu`
A hierarchical menu system designed for non-paginated, deep-tree navigation.

**Features:**
- Accepts a nested array of Objects or Hashtables defining `Label`, `Value`, and `Children`.
- Deep linking: Dynamically displays breadcrumbs (e.g. `Main Menu > System > Power`) as you drill down.
- Provides numeric shortcuts. You can rapidly jump to an option by typing its list number (e.g., `1`, `12`).
- Gracefully handles menus of varying heights by clearing previous artifacts.
- **Automatic Truncation:** Long lines and deep breadcrumbs are automatically truncated to fit the terminal width, preventing layout breakage.

**Parameters:**
- `-MenuTree`: (Required) The structural array of menu options.
- `-Title`: The root text displayed in the breadcrumb header (Default: `"Main Menu"`).
- `-InitialPath`: An array of indices (`[int]`) or strings (`[string]`) representing the path to pre-navigate. If the last segment is a leaf, it will be highlighted; if it is a sub-menu, it will be highlighted but not entered unless there is a subsequent segment in the path.
- `-NoColor`: (Switch) Disable ANSI styling on the selected row. See [Rendering Modes](#rendering-modes).
- `-Ascii`: (Switch) Swap Unicode glyphs (`↑↓ → ←`, `►` child indicator, box-drawing chars) for ASCII fallbacks. See [Rendering Modes](#rendering-modes).

**Shortcuts:**
- `↑` / `↓`: Move selection within the current menu tier.
- `1` - `99`: Instantly highlight the corresponding numbered option.
- `→`: Expand/drill down into a sub-menu.
- `←`: Go back up one tier.
- `Enter`: Confirm selection (or expand sub-menu).
- `Esc`: Go back up one tier, or exit the menu entirely if at the root.

**Example:**
```powershell
Import-Module ./pwshTui.psm1

$menuData = @(
    @{ Label = "System"; Children = @(
        @{ Label = "Network"; Value = "sys_network" }
        @{ Label = "Storage"; Value = "sys_storage" }
    )}
    @{ Label = "Exit"; Value = "exit" }
)

# Launch directly into the 'System' submenu and highlight 'Storage'
$selection = Invoke-NestedMenu -MenuTree $menuData -Title "Admin Portal" -InitialPath @("System", "Storage")
```

---

### `Write-TuiBox`
The underlying layout engine used by the interactive functions, also available for standalone use.

**Features:**
- Automatic sizing based on content.
- Support for optional Header and Footer sections with horizontal separators.
- ANSI-aware width calculation (correctly handles colors/formatting).
- Absolute positioning (X, Y coordinates).
- Single-line Unicode box borders.

**Parameters:**
- `-Header`: `[string[]]` lines for the top section.
- `-Body`: `[string[]]` lines for the main content.
- `-Footer`: `[string[]]` lines for the bottom section.
- `-Border`: (Switch) Enables box-drawing borders.
- `-MinWidth` / `-MaxWidth`: Constrains the width of the box.
- `-X` / `-Y`: Absolute text coordinates for the top-left corner.
- `-SectionRules`: (Switch) Draw a horizontal rule between sections (header→body, body→footer) when `-Border` is off. No-op in `-Border` mode (the existing `├─┤` connectors are used instead). Useful for borderless layouts that still want visible segregation.
- `-Ascii`: (Switch) Swap Unicode box-drawing chars (`─┌┐└┘├┤│`) for ASCII fallbacks (`-+++++|`). See [Rendering Modes](#rendering-modes).
- `-PassThru`: (Switch) Emit the rendered line count to the pipeline. Without this switch the function returns nothing — matching the `Add-Member -PassThru` / `Set-ItemProperty -PassThru` convention for side-effect cmdlets. The internal callers `Get-PaginatedSelection` and `Invoke-NestedMenu` use the count for cursor management; standalone callers usually don't need it.

**Example:**
```powershell
Write-TuiBox -Header "System Status" -Body @("CPU: 12%", "RAM: 4.2GB") -Border
---

### `Measure-FuzzyMatch`
A utility function for calculating the relevance score between a search term and a target string. It uses a cross-platform, ensemble fuzzy-matching approach written entirely in pure PowerShell, ensuring it works securely in locked-down environments like Azure Automation without compiling C# code.

**Features:**
- **Auto (Intent-Biased Max):** Detects user intent — typing the target (typo) vs. abbreviating — from signals like search/target length ratio and vowel-sparseness, then tilts the contest toward the better-suited algorithm. Uses `Math.Max` of the biased scores, so the recognized signal always survives intact.
- **Subsequence (fzf-style):** Rewards characters that appear in order, with bonuses for consecutive characters and word-boundary matches. Ideal for acronyms and abbreviations (e.g., `pwsh` matches `PowerShell`).
- **Jaro-Winkler:** Similarity score with a prefix boost — catches transpositions and typos cheaply (e.g., `teh` ≈ `the`, `srever` ≈ `server`) and rewards shared leading characters.
- **Word-aware normalization:** Structural separators (`-`, `_`, `.`, `/`, `:`, `\`) and camelCase/PascalCase boundaries are converted to spaces before matching, so `XMLHttpRequest`, `my-server-01`, and `my server 01` all expose the same word structure to the algorithms. Fast paths also check a compact (space-removed) form so users who type identifiers without separators still hit prefix/substring shortcuts.
- Returns an integer score scaled from 0 to 1000 (higher is better, 0 means no match, 1000 means exact match).

**Parameters:**
- `-SearchTerm`: (Required) The string you are searching for.
- `-TargetText`: (Required) The string to evaluate against the search term.
- `-Algorithm`: (Optional) Override the default `Auto` policy. Valid options: `Auto`, `Subsequence`, `JaroWinkler`, `Legacy`.

**Example:**
```powershell
Import-Module ./pwshTui.psd1

# Finds 'Server01' using a subsequence abbreviation
$score1 = Measure-FuzzyMatch -SearchTerm "sv01" -TargetText "Server01"

# Finds 'Storage' despite a typo
$score2 = Measure-FuzzyMatch -SearchTerm "storge" -TargetText "Storage"
```

---

### `Show-Spinner`
Run a scriptblock with a live animated spinner. Wraps "wait for this to finish" UX behind one call.

**Features:**
- **Closures Just Work:** the user's scriptblock runs on the foreground thread in its defining scope — `$baseUrl`, `$connectionString`, and any other caller-local variables are visible without `$using:` or `-ArgumentList`. Only the spinner glyph rendering is pushed to a background runspace.
- **Six glyph styles:** `Braille` (default, smooth 10-frame), `Ascii` (universal `| / - \`), `HalfBlocks` (Unicode corners), `Dots` (text-only `.`, `..`, `...`, `....`), `Circles` (filling-wave `○◔◑◕●◕◑◔`), `Pulse` (breathing `· • ● •`).
- **Optional live timer:** `-ShowTimer` appends an elapsed-time counter that narrows format with scale: `(3.2s)` under a minute, `(2m 34s)` under an hour, `(1h 23m)` beyond.
- **Azure Automation / non-VT fallback:** detects hosts without virtual-terminal support and emits plain bracket log lines (`[ Activity ]` / `[ Activity done in 3.2s ]`) instead of garbled ANSI animation. Scriptblock execution, return values, and exception propagation are identical across both modes — only the render layer changes.
- **Safe cleanup:** exceptions from the scriptblock propagate naturally through the `finally` block; the runspace, signal handle, and cursor visibility are always restored.

**Parameters:**
- `-Activity`: (Required) Text shown after the spinner glyph.
- `-ScriptBlock`: (Required) The work to execute. Runs on the foreground thread in the caller's scope.
- `-Style`: Glyph style — `Braille` (default), `Ascii`, `HalfBlocks`, `Dots`, `Circles`, `Pulse`.
- `-ShowTimer`: (Switch) Append a live elapsed-time counter to the activity line. Controls on-screen display only; orthogonal to `-ElapsedVariable`.
- `-ElapsedVariable`: Name (no `$`) of a variable in the caller's scope to receive the total elapsed time as a `[TimeSpan]` after the spinner exits. Mirrors PowerShell's `-OutVariable` / `-ErrorVariable` convention. The spinner line is erased on exit in interactive (VT) mode, so capture this if you want to render `"fetched in 2.3s"` yourself.
- `-NoColor`: (Switch) Disable ANSI styling on the spinner glyph.
- `-Ascii`: (Switch) Forces `-Style Ascii` regardless of any `-Style` argument. Single consistent fallback switch across the module. See [Rendering Modes](#rendering-modes).

**Clean in-scriptblock output:** plain `Write-Host` from inside the scriptblock still tears the spinner row (same limitation as `Write-Progress`). Use [`Write-Spinner`](#write-spinner) as the opt-in clean channel — it buffers messages and the ticker flushes them above the animated glyph so they persist in scrollback.

**Example:**
```powershell
Import-Module ./pwshTui.psd1

$baseUrl = 'https://api.example.com'
$users = Show-Spinner -Activity "Fetching users..." -ShowTimer -ScriptBlock {
    Invoke-RestMethod "$baseUrl/users"   # closure over $baseUrl works
}
# $users contains the response; spinner line cleared on return.

# Capture elapsed time and compose your own "done" line:
$users = Show-Spinner -Activity "Fetching" -ElapsedVariable el -ScriptBlock {
    Invoke-RestMethod "$baseUrl/users"
}
Write-Host "Got $($users.Count) users in $('{0:F1}s' -f $el.TotalSeconds)"
```

---

### `Write-Spinner`
Emit a log line that persists above an active spinner. The opt-in clean channel for any visible text the scriptblock needs to emit while a spinner is running — solves the otherwise-corrupting interleave with plain `Write-Host`.

**Features:**
- **Persists above the glyph:** when called from inside a `Show-Spinner` `-ScriptBlock` on a VT host, the message is enqueued and the ticker drains it on its next frame — the spinner row is cleared, the message is written with a trailing newline so it scrolls up and persists, and the spinner is redrawn on the now-empty row.
- **Drop-in safe:** outside an active spinner — or in non-VT contexts where there's no animated row to conflict with — the call passes through to `Write-Host`. So helpers that use `Write-Spinner` stay usable whether or not their caller wraps them in a spinner.
- **Color preserved:** `-ForegroundColor` is honored in both paths. For the VT-spinner path the message is ANSI-wrapped with the matching SGR code before being enqueued, so the persisted line keeps its color.
- **Scope is visible output only:** this is specifically for `Write-Host`-style text (the stream that would tear the spinner). `Write-Verbose`, `Write-Warning`, `Write-Error`, and pipeline output are unaffected and continue to use their own streams.

**Parameters:**
- `-Message`: (Required) Text to emit. Pass a single string; embedded newlines render as multiple lines, all of which scroll above the spinner.
- `-ForegroundColor`: Optional `[System.ConsoleColor]`. Suppressed under `$env:NO_COLOR`.

**Example:**
```powershell
Show-Spinner -Activity "Indexing" -ShowTimer -ScriptBlock {
    foreach ($file in $files) {
        Process $file
        Write-Spinner "Indexed $($file.Name)" -ForegroundColor DarkGray
    }
}
# Each "Indexed ..." line scrolls above the spinning glyph and is preserved
# in scrollback when the spinner finishes.
```

## Global Layout Parameters

All interactive functions (`Get-PaginatedSelection`, `Invoke-NestedMenu`, `Read-Date`, `Read-Time`, `Read-Timezone`) now support the following layout parameters:

- `-Border`: Wraps the component in a box.
- `-MinWidth`: Ensures a minimum box width.
- `-MaxWidth`: Caps the box width (defaults to terminal width).
- `-X` / `-Y`: Renders the component at absolute coordinates. If omitted, renders inline at the current cursor position.

## Rendering Modes

Two cross-cutting rendering switches are available on every function where they apply, with consistent semantics across the module.

**`-Ascii`** — Swap Unicode glyphs for ASCII equivalents. Useful in restricted terminals, legacy Windows code pages, log scrapes, or fonts that don't include box-drawing / Braille glyphs.

| Unicode | ASCII | Used in |
|---|---|---|
| `─ ┌ ┐ └ ┘ ├ ┤ │` | `- + + + + + + \|` | `Write-TuiBox` borders + section rules |
| `← →` | `<- ->` | footers of paginated selection / nested menu / date / time |
| `↑↓` | `^v` | footers of paginated selection / nested menu / date / time |
| `►` | `>` | `Invoke-NestedMenu` child indicator |
| Braille `⠋⠙⠹...` | `\| / - \\` | `Show-Spinner` — `-Ascii` forces `-Style Ascii` |

Available on: `Write-TuiBox`, `Get-PaginatedSelection`, `Invoke-NestedMenu`, `Show-Spinner`, `Read-Date`, `Read-Time`, `Read-Timezone`.

**`-NoColor`** — Disable ANSI color/styling. Visual affordances are preserved via bracket fallbacks:

| Function | Color highlight | NoColor fallback |
|---|---|---|
| `Get-PaginatedSelection` / `Invoke-NestedMenu` | Cyan-highlighted selected row | Selection signalled by the `> ` pointer only |
| `Read-MaskedInput` | Cyan-bg cursor slot | `[X]`-bracketed cursor slot |
| `Read-Password` | Cyan-bg cursor block | `_` cursor block |
| `Read-ValidatedInput` | Red/green text + cyan cursor | `[X]`-bracketed cursor + trailing `[OK]` / `[??]` marker |
| `Read-Confirmation` | Cyan-bg selected button | `[Yes]` / `[No]` bracket on the selected option |
| `Read-Choice` | Cyan-bg focused option | `> ` prefix on the focused option |
| `Read-Date` / `Read-Time` | Cyan-bg focused field (blink in type mode) | `[XX]`-bracketed focused field |
| `Read-Timezone` | Inherited from `Get-PaginatedSelection` | Inherited from `Get-PaginatedSelection` |
| `Show-Spinner` | Cyan spinner glyph | Plain glyph |

Available on: `Get-PaginatedSelection`, `Invoke-NestedMenu`, `Show-Spinner`, `Read-MaskedInput`, `Read-Password`, `Read-ValidatedInput`, `Read-Confirmation`, `Read-Choice`, `Read-Date`, `Read-Time`, `Read-Timezone`.

**Resolution rule** (consistent everywhere): explicit per-call switch > environment variable > rich default. A per-call `-Ascii:$false` will force Unicode even when the env var is set.

**Environment variables** (set once for a session or terminal — picked up at module import):

- `$env:PWSHTUI_ASCII = 1` — module-wide ASCII fallback
- `$env:NO_COLOR = 1` — module-wide color disable. pwshTui honours the de-facto [NO_COLOR](https://no-color.org) standard, so the same variable used by `ls --color`, `gh`, `bat`, and friends works here.

## Localization

UI strings (footer labels, status messages) are loaded via `Import-LocalizedData` at module import based on `$PSUICulture`. PowerShell walks the culture hierarchy automatically (e.g. `fr-CA` → `fr-FR` → invariant), so any French-speaking culture picks up the `fr-FR` resource file. If no matching file is found, the English defaults (hard-coded in the module) are used as a complete fallback.

**Bundled locales:** `en-US` (fallback), `fr-FR`, `es-ES`, `de-DE`.

**Adding a locale:** drop a `<culture>/pwshTui.Strings.psd1` next to the existing ones (e.g. `it-IT/pwshTui.Strings.psd1`) using the same key set. Missing keys fall back to the English defaults — partial translations are fine. Example structure:

```powershell
ConvertFrom-StringData @'
Footer_Move      = Sposta
Footer_Select    = Seleziona
Footer_Cancel    = Annulla
# ... other keys ...
'@
```

**Forcing a locale for one session:**
```powershell
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::new('fr-FR')
Import-Module pwshTui -Force   # re-import to pick up the new culture
```

Read-only resource keys: `Footer_Move`, `Footer_Select`, `Footer_Confirm`, `Footer_Cancel`, `Footer_Exit`, `Footer_Toggle`, `Footer_Expand`, `Footer_Back`, `Footer_PrevPage`, `Footer_NextPage`, `Footer_Selected`, `Footer_Search`, `Footer_BackToSelection`, `Footer_Field`, `Footer_Adjust`, `Footer_Edit`, `Status_NoMatches`, `Status_NoItems`, `Status_Cancelled`, `Status_DoneIn`.

## Terminal Safety & UI Polish

All functions in this module share the following safety guarantees:
- **Stateful Cursor Management:** The real terminal cursor is automatically hidden to prevent flickering and visual tearing while drawing menus or input fields. The module captures the state of your terminal's cursor *before* running, and guarantees it is restored to that exact state when it exits.
- **Clean Prompt Fallback:** If you cancel an input or menu (via `Esc` or `CTRL+C`), the module automatically emits a newline to ensure your subsequent shell prompt drops to a clean, fresh line, avoiding trailing artifacts.
- **CTRL+C Safe:** Interactive functions set `[Console]::TreatControlCAsInput = $true` so the Ctrl+C keypress is caught **immediately** (not deferred until the next key) and rethrown as a `PipelineStoppedException`. The `finally` block runs first — cursor restored, alt-screen exited, `TreatControlCAsInput` restored — then the exception propagates. PowerShell handles it as a normal Ctrl+C, so the script terminates cleanly with no stack trace and the terminal lands you back at a clean prompt. (Esc remains the soft cancel — returns `$null`.)
- **Host Compatibility:** Virtual-terminal capability is detected once at module import (`$Host.UI.SupportsVirtualTerminal`). Interactive functions (`Get-PaginatedSelection`, `Read-MaskedInput`, `Read-Password`, `Read-ValidatedInput`, `Read-Confirmation`, `Read-Choice`, `Read-Date`, `Read-Time`, `Read-Timezone`, `Read-Phone`, `Read-Email`, `Read-IPv4`, `Read-CIDR`, `Read-URL`, `Invoke-NestedMenu`) fail fast with a clear error naming the function and current host when invoked from non-VT contexts (Azure Automation, Windows PowerShell ISE, redirected output) — they need `[Console]::ReadKey` which can't be polyfilled. `Show-Spinner` falls back to plain bracket log lines in the same contexts so scripts that wrap work in a spinner still run cleanly under automation.
- **Paste safety on text input:** `Read-Password`, `Read-MaskedInput`, and `Read-ValidatedInput` enable bracketed-paste mode (`\e[?2004h`) on entry, so the terminal hands them the pasted text as one delimited unit instead of streaming bytes that mix with the per-character Enter/Backspace handlers. Each function applies its own sanitation: control characters in the paste body trigger a visible reject; a single trailing `\r`/`\n` is treated as the user's Enter press. This eliminates the otherwise-silent corruption when a pasted value contains an embedded newline, which is particularly critical for `Read-Password -Confirm` where two identically-mangled pastes would otherwise "match" each other and lock the user out of whatever they just provisioned. Older terminals that don't recognize the bracketed-paste enable code silently ignore it and fall back to today's per-character behavior; modern Windows Terminal, iTerm2, Terminal.app, gnome-terminal, kitty, alacritty, and the VS Code integrated terminal all support it.

## Installation

1. Copy the `pwshTui` folder to one of the paths listed in your `$env:PSModulePath`.
2. Run `Import-Module pwshTui` in your script or console.

## What's Next

pwshTui covers the most common script-level prompts well — single-choice selection, masked / validated input, date / time / timezone pickers, and nested menus. The following are on the table as the library grows, listed roughly by scope:

- **Terminal resize handling** — recalculate layout on `WindowWidth` / `WindowHeight` changes.
- **`Get-PaginatedSelection -Columns`** — auto-aligned tabular display for picking from object collections.
- **`Read-Form`** — multi-field composition with Tab navigation, shared layout, and per-field validation.

Continued investment in `Measure-FuzzyMatch` is also on the list: word-aware Jaro-Winkler, additional intent signals (subsequence cluster span, original-case acronyms, multi-word queries), Unicode/diacritic folding, and tunable bias weights.

Out of scope (deliberately): multi-pane / split-window layouts, async event loops, theming frameworks, declarative UI DSLs. pwshTui aims to stay a lightweight library of script primitives — not an application framework.
