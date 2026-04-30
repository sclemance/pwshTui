# pwshui

A portable, flexible suite of PowerShell 7+ functions designed to provide a clean and consistent console user experience across Linux, Windows, and macOS. 

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

**Parameters:**
- `-Items`: (Required) The array of items to select from.
- `-PageSize`: The number of items to show per page (Default: `10`).
- `-Title`: The header text for the menu (Default: `"Select an item:"`).
- `-DisplayProperty`: If passing objects, the name of the property to display in the list.
- `-Wrap`: (Switch) Enables wrapping from the bottom to the top of a page, and from the last page to the first page.
- `-NoColor`: (Switch) Disables ANSI color highlighting, relying entirely on the `> ` pointer.
- `-InitialIndex`: The 0-based index of the item to select by default. This will automatically calculate and display the correct page.

**Shortcuts:**
- `↑` / `↓`: Move selection within the current page.
- `←` / `→`: Navigate between pages.
- `Enter`: Confirm selection.
- `Esc`: Cancel selection (returns `$null`).

**Example:**
```powershell
Import-Module ./pwshui.psd1

$processes = Get-Process | Sort-Object Name
# Start on the 25th process in the list
$selected = Get-PaginatedSelection -Items $processes -PageSize 15 -InitialIndex 24 -Title "Select a Process" -DisplayProperty "ProcessName" -Wrap
```
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
Import-Module ./pwshui.psd1

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
Import-Module ./pwshui.psd1

# IPv4 Address
$ipv4Regex = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
$ip = Read-ValidatedInput -Prompt "Enter IP:" -Pattern $ipv4Regex

# Email Address
$emailRegex = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
$email = Read-ValidatedInput -Prompt "Enter Email:" -Pattern $emailRegex
```

---

### 4. `Invoke-NestedMenu`
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
Import-Module ./pwshui.psd1

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

## Terminal Safety & UI Polish

All functions in this module share the following safety guarantees:
- **Stateful Cursor Management:** The real terminal cursor is automatically hidden to prevent flickering and visual tearing while drawing menus or input fields. The module captures the state of your terminal's cursor *before* running, and guarantees it is restored to that exact state when it exits.
- **Clean Prompt Fallback:** If you cancel an input or menu (via `Esc` or `CTRL+C`), the module automatically emits a newline to ensure your subsequent shell prompt drops to a clean, fresh line, avoiding trailing artifacts.
- **CTRL+C Safe:** All rendering loops are wrapped in `try/finally` blocks. If a user forcefully terminates the script using `CTRL+C`, the cursor state and terminal formatting are guaranteed to be safely restored before the process exits.

## Installation

1. Copy the `pwshui` folder to one of the paths listed in your `$env:PSModulePath`.
2. Run `Import-Module pwshui` in your script or console.