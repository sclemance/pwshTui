# Localized strings for the pwshTui demo (en-US — fallback culture).
# Strings are demo-only; pwshTui library strings live in pwshTui.Strings.psd1.
# Loaded by Set-DemoCulture in demo.ps1 alongside the library file.
# Format placeholders use PowerShell's -f syntax: {0}, {1}, ...
ConvertFrom-StringData @'
Menu_Group_SelectionMenus     = Selection & Menus
Menu_Group_InputPrompts       = Input Prompts
Menu_Group_DateTime           = Date & Time
Menu_Group_AsyncLayout        = Async & Layout
Menu_ToggleRenderMode         = Toggle Render Mode (currently: {0})
Menu_ChangeLanguage           = Change Language (currently: {0})
Menu_ExitDemo                 = Exit demo
Help_About                    = About

Menu_Paginated                = Paginated Selection (searchable)
Menu_PaginatedJump            = Paginated Selection (-InitialIndex jump to #25)
Menu_MultiSelect              = Paginated Multi-Select (Space toggles)
Menu_Nested                   = Nested Menu
Menu_NestedDeep               = Nested Menu (-InitialPath deep-link)
Menu_NestedBordered           = Nested Menu (bordered + AltScreen)
Menu_SettingsMenu             = Settings Menu (aligned values + help)

Menu_MaskedInput              = Masked Input (phone, MAC)
Menu_PasswordInput            = Password Input (SecureString, confirm, PIN)
Menu_ValidatedInput           = Validated Input (IPv4, CIDR, email)
Menu_Confirmation             = Yes/No Confirmation
Menu_ChoiceSelector           = Choice Selector (single + multi)
Menu_NumberInput              = Number Input (units, separators, accelerating arrows)
Menu_NumberWrappers           = Number Wrappers (Percentage, Temperature, Currency)
Menu_Measurement              = Measurement (mixed-unit input via units/*.psd1)
Menu_TemplatedWrappers        = Templated Wrappers (Phone, Email, IPv4, CIDR, URL)

Menu_DateInline               = Read-Date (inline fields)
Menu_DateCalendar             = Read-Date -Calendar (with month grid)
Menu_Time24                   = Read-Time (24-hour)
Menu_Time12                   = Read-Time -TwelveHour -ShowSeconds
Menu_Timezone                 = Read-Timezone (with preferred list)

Menu_Spinner                  = Show-Spinner (default Braille)
Menu_SpinnerTimer             = Show-Spinner with -ShowTimer
Menu_SpinnerStyles            = Show-Spinner — all six styles
Menu_SpinnerClosure           = Show-Spinner — closure capture
Menu_UIBox                    = Write-TuiBox (standalone)
Menu_Table                    = Write-TuiTable (tabular layout)

Title_Demo                    = pwshTui Demo [{0} | {1}]
Title_SelectSystemObject      = Select a System Object
Title_JumpedToItem25          = Jumped to Item 25
Title_PickMultiple            = Pick multiple objects
Title_AdminPortal             = Admin Portal
Title_BorderedMenu            = Bordered Menu
Title_SystemStatus            = System Status
Title_Services                = Services

Header_Paginated              = Get-PaginatedSelection (searchable)
Header_PaginatedJump          = Get-PaginatedSelection (-InitialIndex jumps to a specific item)
Header_MultiSelect            = Get-PaginatedSelection -MultiSelect
Header_NestedMenu             = Invoke-NestedMenu
Header_NestedMenuDeep         = Invoke-NestedMenu -InitialPath (deep-link into Power Saver)
Header_NestedMenuBordered     = Invoke-NestedMenu (bordered, positioned, AltScreen)
Header_SettingsMenu           = Invoke-NestedMenu (value column + help band)
Header_MaskedInput            = Read-MaskedInput
Header_Password               = Read-Password
Header_ValidatedInput         = Read-ValidatedInput
Header_Confirmation           = Read-Confirmation
Header_Choice                 = Read-Choice
Header_Number                 = Read-Number (units, separators, accelerating arrows)
Header_NumberWrappers         = Read-Percentage / Read-Temperature / Read-Currency
Header_Measurement            = Read-Measurement (mixed-unit input driven by data files)
Header_Spinner                = Show-Spinner (default Braille)
Header_SpinnerTimer           = Show-Spinner -ShowTimer
Header_SpinnerStyles          = Show-Spinner — all six styles, 1.5s each
Header_SpinnerClosure         = Show-Spinner — closures Just Work
Header_UIBox                  = Write-TuiBox (standalone)
Header_Table                  = Write-TuiTable (tabular layout)
Hint_Table                    = Auto-sized columns, right-justified numbers, joined by │ separators — Format-TuiTable lays out the rows, Write-TuiBox frames them.
Header_Date                   = Read-Date (inline)
Header_DateCalendar           = Read-Date -Calendar (with month grid)
Header_Time                   = Read-Time (24-hour)
Header_TimeTwelve             = Read-Time -TwelveHour -ShowSeconds
Header_TemplatedWrappers      = Templated input wrappers (Phone, Email, IPv4, CIDR, URL)
Header_Timezone               = Read-Timezone

Hint_Paginated                = Type to fuzzy-search; arrows to navigate; Enter to pick; Esc to cancel.
Hint_MultiSelect              = Space toggles (selection mode); Tab flips to search mode; type to filter; arrows return to selection mode with the first row highlighted; Enter confirms; Esc cancels.
Hint_NestedBordered           = Drawing a menu with -Border -MinWidth 40 -X 5 -Y 15 -AltScreen...
Hint_Password1                = Type to enter; Backspace deletes; Enter submits; Esc cancels.
Hint_Password2                = Strength indicator appears live to the right of the masked input.
Hint_Confirmation             = Y/N for instant answer; Left/Right/Tab to move highlight; Enter to confirm; Esc to cancel.
Hint_Choice                   = Arrow keys or digit 1-N to move; Enter to confirm; Esc to cancel.
Hint_ChoiceMulti              = Multi-select: Space toggles, digits move focus, Enter returns the array.
Hint_Number1                  = Up/Down to nudge, hold to accelerate (curve scales with range and slows near limits). PgUp/PgDn jump by 10*Step.
Hint_Number2                  = Type digits to edit directly; Backspace/Delete edit the buffer; Enter commits when in range; Esc cancels.
Hint_NumberWrappers           = Locale-aware defaults: temperature unit derived from region, currency symbol from ISO code. Override -Unit / -Currency for non-default formats.
Hint_Measurement              = Type a measurement like "5'11\"", "1m 80cm", or "100cm" — the parser is driven by units/length.psd1 (no hard-coded unit list). Live decorator shows the value in the region's preferred unit.
Hint_Spinner                  = Running a 2-second sleep...
Hint_SpinnerTimer             = Running a 3.5-second sleep with the live elapsed-time counter...
Hint_SpinnerStylesAscii       = ASCII mode is on — -Ascii forces Style=Ascii regardless of -Style, so all four render as the Ascii glyph below. Toggle ASCII off to see each style as-named.
Hint_SpinnerClosure           = Caller scope holds $magicNumber = {0}. The scriptblock will use it without -ArgumentList.
Hint_Date                     = ← → move fields, ↑ ↓ adjust the focused value, type digits to feed the field, Tab toggles modes.
Hint_DateCalendar1            = Same input model as the inline picker; the grid is read-only context showing the focused day.
Hint_DateCalendar2            = Constrained to today..today+1y so Enter is blocked outside that range.
Hint_Time                     = Type four digits to fill HH:MM in one go (1430 → 14:30); arrows for field nav + Up/Down to adjust.
Hint_TimeTwelve               = 12-hour clock with AM/PM (a/p shortcuts) and a seconds field. Internal storage stays 24-hour.
Hint_Templated                = Each wrapper hard-codes a mask or regex for one of the popular input shapes. Esc skips to the next.
Hint_Timezone1                = Local zone highlighted by default; common zones pinned to the top with a leading "*".
Hint_Timezone2                = Inherits paginated-selection's search — Tab to filter.

Prompt_PhoneNumber            = Phone Number:
Prompt_MacAddress             = MAC Address:
Prompt_Password               = Password:
Prompt_NewPassword            = New password:
Prompt_Retype                 = Retype:
Prompt_PIN                    = PIN (hidden length):
Prompt_IPv4                   = IPv4 Address:
Prompt_CIDR                   = CIDR Notation:
Prompt_Email                  = Email Address:
Prompt_DeleteFile             = Delete the file?
Prompt_PickColor              = Pick a color:
Prompt_PickToppings           = Pick toppings:
Prompt_PickDate               = Pick a date:
Prompt_ScheduleFor            = Schedule for:
Prompt_StartTime              = Start time:
Prompt_Alarm                  = Alarm:
Prompt_Phone                  = Phone:
Prompt_EmailShort             = Email:
Prompt_IPv4Short              = IPv4 address:
Prompt_CIDRShort              = CIDR notation:
Prompt_URL                    = URL:
Prompt_Port                   = Port:
Prompt_Coverage               = Coverage:
Prompt_Temperature            = Temperature:
Prompt_Budget                 = Budget:
Prompt_Amount                 = Amount:
Prompt_BodyTemp               = Body temperature:
Prompt_Progress               = Progress:
Prompt_Distance               = Distance:
Prompt_Ambient                = Ambient temperature:

Activity_Working              = Working
Activity_Querying             = Querying
Activity_Computing            = Computing
Activity_StylePrefix          = Style: {0}

Result_YouSelected            = You selected: {0}
Result_YouSelectedWithID      = You selected: {0} (ID: {1})
Result_SelectionCancelled     = Selection cancelled.
Result_Cancelled              = Cancelled.
Result_CancelledNull          = Cancelled (returned $null).
Result_CancelledOrExhausted   = Cancelled or attempts exhausted.
Result_ConfirmedNoSelections  = Confirmed with no selections.
Result_SelectedItems          = Selected {0} item(s):
Result_Captured               = Captured: {0}
Result_CapturedPlainText      = Captured plain text: {0}
Result_CapturedSecureString   = Captured SecureString of length {0}.
Result_ConfirmedSecureString  = Confirmed SecureString of length {0}.
Result_Strength               = Strength: {0} (score {1}/6, {2} char classes)
Result_ConfirmedYes           = Confirmed: Yes
Result_ConfirmedNo            = Confirmed: No
Result_CapturedNone           = Captured: (none)
Result_AllStylesShown         = All styles shown.
Result_ScriptblockReturned    = Scriptblock returned: {0} (expected: 84)
Result_Done                   = Done.
Result_MenuCancelled          = Menu cancelled.
Result_CapturedAction         = Captured Action: {0}
Result_SelectedTimezone       = Selected: {0}
Result_TimezoneDisplay        = Display:  {0}
Result_LocalNow               = Local now:   {0}
Result_InSelected             = In selected: {0}
Result_SelectedDate           = Selected: {0}
Result_SelectedTime           = Selected: {0}

Common_PressAnyKey            = [ Press any key to return to the menu ]
Common_Thanks                 = Thanks for trying pwshTui.
Common_CouldNotLoadLocale     = Could not load locale "{0}".
Common_DemoBox                = Demo box
Common_BodyCPU                = CPU: 12%
Common_BodyRAM                = RAM: 4.2GB
Common_BodyDisk               = Disk: 80% Full
'@
