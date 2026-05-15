# pwshTui

A portable, flexible suite of PowerShell 7.4+ functions designed to provide a clean and consistent console user experience across Linux, Windows, and macOS. 

This library focuses on fast, flicker-free rendering using ANSI escape sequences and provides robust fallbacks for non-color terminals.

## Functions

### 1. `Get-PaginatedSelection`
A powerful interactive selector for arrays or complex objects.

**Features:**
- Keyboard navigation (Up/Down for selection, Left/Right for pagination).
- Smooth rendering using ANSI escape sequences (minimizes flickering).
- Support for wrapping between pages and within pages (`-Wrap`).
- Object-aware: use `-DisplayProperty` to specify which property of an object to display in the menu.
- Clean display logic that prevents artifacts on the screen when navigating between pages of varying lengths.
- **Automatic Truncation:** Long lines are automatically truncated to fit the terminal width, preventing layout breakage and cursor sync issues.
- **Live Search Filtering:** When enabled, typing filters the list dynamically using a robust fuzzy-matching algorithm.
- **Multi-Select Mode:** When `-MultiSelect` is enabled, `Space` toggles the current row's selection (with an `[x]`/`[ ]` marker), and `Enter` returns an array of toggled items in original input order. Selection state persists across search filter changes. In `-Searchable -MultiSelect` mode, `Space` toggles instead of extending the search buffer (matches fzf `-m` behavior).

**Parameters:**
- `-Items`: (Required) The array of items to select from.
- `-PageSize`: The number of items to show per page (Default: `10`).
- `-Title`: The header text for the menu (Default: `"Select an item:"`).
- `-DisplayProperty`: If passing objects, the name of the property to display in the list.
- `-Wrap`: (Switch) Enables wrapping from the bottom to the top of a page, and from the last page to the first page.
- `-NoColor`: (Switch) Disables ANSI color highlighting, relying entirely on the `> ` pointer.
- `-InitialIndex`: The 0-based index of the item to select by default. This will automatically calculate and display the correct page.
- `-Searchable`: (Switch) Enables live fuzzy-search filtering. When active, alpha-numeric key presses will update a search buffer and dynamically filter the displayed list.
- `-SearchAlgorithm`: Specifies the algorithm used for filtering (`Auto`, `Subsequence`, `JaroWinkler`, `Legacy`). Default: `Auto`.
- `-MultiSelect`: (Switch) Enables multi-selection. `Space` toggles the current row; `Enter` returns an array of selected items (possibly empty) in original input order. `Esc` still returns `$null`, so callers can distinguish cancel (`$null`) from "confirmed nothing" (`@()`).

**Shortcuts:**
- `↑` / `↓`: Move selection within the current page.
- `←` / `→`: Navigate between pages.
- `Enter`: Confirm selection.
- `Esc`: Cancel selection (returns `$null`).
- `Backspace` / `Alpha-numeric keys`: (When `-Searchable` is used) Modifies the search query to filter the list.
- `Space`: (When `-MultiSelect` is used) Toggles the current row's selection.

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

### 2. `Read-MaskedInput`
A formatted input prompt that enforces structure and restricts keystrokes as the user types. Ideal for fixed-length data like phone numbers or MAC addresses.

**Features:**
- Supports custom masks indicating expected character types.
- Discards invalid keystrokes dynamically (e.g., ignoring letters when a digit is expected).
- Live syntax highlighting indicating the current input slot, hiding the real terminal cursor to prevent visual glitches.
- Returns the cleanly formatted string by default, or the raw input if requested.

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

### 3. `Read-ValidatedInput`
A free-form input field with live Regex validation. Ideal for variable-length but strictly formatted data like Email addresses or IPs.

**Features:**
- Prevents the user from pressing Enter until the input perfectly matches a provided Regular Expression.
- The input text dynamically turns **Green** when valid and **Red** when invalid as you type.

**Parameters:**
- `-Prompt`: (Required) The text displayed before the input field.
- `-Pattern`: (Required) The Regular Expression string used to validate the input.
- `-AllowEmpty`: (Switch) Allows the user to press Enter on an empty string (returns `$null`).

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

### 4. `Read-Confirmation`
A dedicated Yes/No prompt with single-key answer or arrow-key navigation.

**Features:**
- Single-key `Y` or `N` for an immediate answer (case-insensitive).
- Arrow / `Tab` navigation between buttons for users who prefer to confirm with `Enter`.
- Configurable default highlight — `-Default No` is the safer choice for destructive prompts.
- Returns `$true` / `$false` for the answer, or `$null` on cancel — so `if (Read-Confirmation ...)` only fires on an explicit Yes.

**Parameters:**
- `-Question`: (Required) The yes/no question displayed before the buttons.
- `-Default`: Which button (`Yes` or `No`) is highlighted on open and chosen if `Enter` is pressed without moving. Default: `No`.

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

### 5. `Invoke-NestedMenu`
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

### 6. `Write-UIBox`
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

**Example:**
```powershell
Write-UIBox -Header "System Status" -Body @("CPU: 12%", "RAM: 4.2GB") -Border
---

### 7. `Measure-FuzzyMatch`
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

### 8. `Show-Spinner`
Run a scriptblock with a live animated spinner. Wraps "wait for this to finish" UX behind one call.

**Features:**
- **Closures Just Work:** the user's scriptblock runs on the foreground thread in its defining scope — `$baseUrl`, `$connectionString`, and any other caller-local variables are visible without `$using:` or `-ArgumentList`. Only the spinner glyph rendering is pushed to a background runspace.
- **Four glyph styles:** `Braille` (default, smooth 10-frame), `Ascii` (universal `| / - \`), `HalfBlocks` (Unicode corners), `Dots` (text-only `.`, `..`, `...`, `....`).
- **Optional live timer:** `-ShowTimer` appends an elapsed-time counter that narrows format with scale: `(3.2s)` under a minute, `(2m 34s)` under an hour, `(1h 23m)` beyond.
- **Azure Automation / non-VT fallback:** detects hosts without virtual-terminal support and emits plain bracket log lines (`[ Activity ]` / `[ Activity done in 3.2s ]`) instead of garbled ANSI animation. Scriptblock execution, return values, and exception propagation are identical across both modes — only the render layer changes.
- **Safe cleanup:** exceptions from the scriptblock propagate naturally through the `finally` block; the runspace, signal handle, and cursor visibility are always restored.

**Parameters:**
- `-Activity`: (Required) Text shown after the spinner glyph.
- `-ScriptBlock`: (Required) The work to execute. Runs on the foreground thread in the caller's scope.
- `-Style`: Glyph style — `Braille` (default), `Ascii`, `HalfBlocks`, `Dots`.
- `-ShowTimer`: (Switch) Append a live elapsed-time counter to the activity line.
- `-NoColor`: (Switch) Disable ANSI styling on the spinner glyph.

**Caveat:** `Write-Host` output from the scriptblock will interleave with the spinner line (same limitation as `Write-Progress`). Use `Show-Spinner` for opaque "wait for this" work; do logging/reporting before or after.

**Example:**
```powershell
Import-Module ./pwshTui.psd1

$baseUrl = 'https://api.example.com'
$users = Show-Spinner -Activity "Fetching users..." -ShowTimer -ScriptBlock {
    Invoke-RestMethod "$baseUrl/users"   # closure over $baseUrl works
}
# $users contains the response; spinner line cleared on return.
```

## Global Layout Parameters

All interactive functions (`Get-PaginatedSelection`, `Invoke-NestedMenu`) now support the following layout parameters:

- `-Border`: Wraps the component in a box.
- `-MinWidth`: Ensures a minimum box width.
- `-MaxWidth`: Caps the box width (defaults to terminal width).
- `-X` / `-Y`: Renders the component at absolute coordinates. If omitted, renders inline at the current cursor position.

## Terminal Safety & UI Polish

All functions in this module share the following safety guarantees:
- **Stateful Cursor Management:** The real terminal cursor is automatically hidden to prevent flickering and visual tearing while drawing menus or input fields. The module captures the state of your terminal's cursor *before* running, and guarantees it is restored to that exact state when it exits.
- **Clean Prompt Fallback:** If you cancel an input or menu (via `Esc` or `CTRL+C`), the module automatically emits a newline to ensure your subsequent shell prompt drops to a clean, fresh line, avoiding trailing artifacts.
- **CTRL+C Safe:** All rendering loops are wrapped in `try/finally` blocks. If a user forcefully terminates the script using `CTRL+C`, the cursor state and terminal formatting are guaranteed to be safely restored before the process exits.
- **Host Compatibility:** Virtual-terminal capability is detected once at module import (`$Host.UI.SupportsVirtualTerminal`). Interactive functions (`Get-PaginatedSelection`, `Read-MaskedInput`, `Read-ValidatedInput`, `Read-Confirmation`, `Invoke-NestedMenu`) fail fast with a clear error naming the function and current host when invoked from non-VT contexts (Azure Automation, Windows PowerShell ISE, redirected output) — they need `[Console]::ReadKey` which can't be polyfilled. `Show-Spinner` falls back to plain bracket log lines in the same contexts so scripts that wrap work in a spinner still run cleanly under automation.

## Installation

1. Copy the `pwshTui` folder to one of the paths listed in your `$env:PSModulePath`.
2. Run `Import-Module pwshTui` in your script or console.

## What's Next

pwshTui covers the most common script-level prompts well — single-choice selection, masked / validated input, and nested menus. The following are on the table as the library grows, listed roughly by scope:

- **Terminal resize handling** — recalculate layout on `WindowWidth` / `WindowHeight` changes.
- **`Get-PaginatedSelection -Columns`** — auto-aligned tabular display for picking from object collections.
- **`Read-Form`** — multi-field composition with Tab navigation, shared layout, and per-field validation.

Continued investment in `Measure-FuzzyMatch` is also on the list: word-aware Jaro-Winkler, additional intent signals (subsequence cluster span, original-case acronyms, multi-word queries), Unicode/diacritic folding, and tunable bias weights.

Out of scope (deliberately): multi-pane / split-window layouts, async event loops, theming frameworks, declarative UI DSLs. pwshTui aims to stay a lightweight library of script primitives — not an application framework.