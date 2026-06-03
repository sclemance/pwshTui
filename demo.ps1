# pwshTui demo — interactive, menu-driven tour of every exported function.
# Picks demos from a nested menu so you can run any one in isolation
# (and re-run them as many times as you like). Use the "Toggle Render Mode"
# entry on the menu to flip between Unicode (default) and ASCII fallback
# rendering to preview how the library degrades in restricted terminals.
Import-Module ./pwshTui.psd1 -Force

# Demo-level rendering preference. Read once from the module's $script:_AsciiMode
# (which itself was seeded from $env:PWSHTUI_ASCII at module import) so the
# label and the actual rendering agree from the first render. The "Toggle
# Render Mode" menu entry calls Set-DemoAsciiMode, which flips both this
# local AND the module's global — see Set-DemoAsciiMode for why.
$script:demoAsciiMode = [bool](& (Get-Module pwshTui) { $script:_AsciiMode })

# Tracks the language the demo last switched to. Starts as $PSUICulture-derived
# default. Changing it from the menu live-mutates the module's $script:_Strings
# via the module's session state — non-persistent: re-importing the module
# resets to whatever the OS / session $PSUICulture says.
$script:demoCulture = $PSUICulture

# Demo-specific localized strings. Kept separate from the library's
# pwshTui.Strings.psd1 so the library stays strings-only and minimal — demo
# scripting and translation concerns live here in <culture>/demo.Strings.psd1.
# Populated below at startup and overwritten by Set-DemoCulture on each
# language change.
$script:demoStrings = @{}

function Get-DemoString {
    # Lookup helper: returns the localized string for $Key, optionally with
    # PowerShell -f formatting applied to any extra positional args. Falls
    # back to a `[?Key]` marker when the key is missing so untranslated
    # references show up loudly during development.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Key,
        [Parameter(Position = 1, ValueFromRemainingArguments = $true)][object[]]$FormatArgs
    )
    $val = if ($script:demoStrings.ContainsKey($Key)) { $script:demoStrings[$Key] } else { "[?$Key]" }
    if ($FormatArgs -and $FormatArgs.Count -gt 0) { return $val -f $FormatArgs }
    return $val
}

function Set-DemoCulture([string]$Culture) {
    $modulePath = (Get-Module pwshTui).ModuleBase
    $loaded = $null
    try {
        Import-LocalizedData -BindingVariable 'loaded' -BaseDirectory $modulePath -FileName 'pwshTui.Strings.psd1' -UICulture $Culture -ErrorAction Stop
    } catch {
        Write-Host ((Get-DemoString 'Common_CouldNotLoadLocale') -f $Culture) -ForegroundColor Yellow
        return
    }
    if ($loaded) {
        # Push library strings into the module's private $script:_Strings.
        # & (module) {…} executes the scriptblock in the module's session state
        # so the assignment lands on the same variable the functions read.
        & (Get-Module pwshTui) {
            param($newStrings)
            foreach ($k in $newStrings.Keys) { $script:_Strings[$k] = $newStrings[$k] }
        } $loaded
        # Demo strings live in a sibling <culture>/demo.Strings.psd1. Fall
        # back to en-US if the requested culture doesn't have a demo file —
        # the library may be translated even when the demo isn't yet.
        $demoLoaded = $null
        try {
            Import-LocalizedData -BindingVariable 'demoLoaded' -BaseDirectory $PSScriptRoot -FileName 'demo.Strings.psd1' -UICulture $Culture -ErrorAction Stop
        } catch {
            try {
                Import-LocalizedData -BindingVariable 'demoLoaded' -BaseDirectory $PSScriptRoot -FileName 'demo.Strings.psd1' -UICulture 'en-US' -ErrorAction Stop
            } catch { $demoLoaded = $null }
        }
        if ($demoLoaded) { $script:demoStrings = $demoLoaded }
        # Also flip the thread's CurrentCulture so widgets that read culture
        # data directly (e.g. Read-Date's month/day name lookups via
        # DateTimeFormatInfo) reflect the chosen language. Without this,
        # only the footer strings change while the calendar grid stays in
        # the host's OS locale.
        try {
            $ci = [System.Globalization.CultureInfo]::new($Culture)
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $ci
            [System.Threading.Thread]::CurrentThread.CurrentUICulture = $ci
        } catch {
            # Invalid culture name — leave CurrentCulture untouched.
        }
        $script:demoCulture = $Culture
    }
}

function Set-DemoAsciiMode([bool]$Ascii) {
    # Flip the module's render-mode global so every widget call — including
    # ones that don't accept -Ascii (Read-Choice, my new Read-Number-family
    # wrappers, the templated wrappers) — picks up the change immediately
    # without the demo having to splat -Ascii everywhere. Same back-door
    # pattern as Set-DemoCulture's $script:_Strings mutation: legitimate
    # for the demo (which owns its PowerShell session) but NOT the public
    # API library callers should use — they should set $env:PWSHTUI_ASCII
    # before importing pwshTui, or pass -Ascii per call on widgets that
    # accept it. We also mirror the new value into $script:demoAsciiMode
    # so the menu label stays in sync.
    & (Get-Module pwshTui) { param($a) $script:_AsciiMode = $a } $Ascii
    $script:demoAsciiMode = $Ascii
}

# Initial demo-string load. Uses the current $PSUICulture so the demo starts
# already in the host's language when a translation exists; en-US otherwise.
try {
    Import-LocalizedData -BindingVariable 'demoLoaded' -BaseDirectory $PSScriptRoot -FileName 'demo.Strings.psd1' -ErrorAction Stop
    if ($demoLoaded) { $script:demoStrings = $demoLoaded }
} catch {
    # No matching demo strings file — fall back to en-US so the demo runs.
    try {
        Import-LocalizedData -BindingVariable 'demoLoaded' -BaseDirectory $PSScriptRoot -FileName 'demo.Strings.psd1' -UICulture 'en-US' -ErrorAction Stop
        if ($demoLoaded) { $script:demoStrings = $demoLoaded }
    } catch { }
}

# --- Shared demo data --------------------------------------------------------
# Sample data (menu tree, system objects, color/topping lists) is intentionally
# left in English. It's filler content that demonstrates the widgets; localizing
# it would dilute the "look how the chrome changes" point of the language
# switcher. Real callers translate their own data.

$menuData = @(
    @{ Label = "System Configuration"; Children = @(
        @{ Label = "Network Settings"; Value = "sys_network" }
        @{ Label = "Storage Management"; Value = "sys_storage" }
        @{ Label = "Power Options"; Children = @(
            @{ Label = "High Performance"; Value = "pwr_high" }
            @{ Label = "Power Saver"; Value = "pwr_save" }
        )}
    )}
    @{ Label = "User Management"; Children = @(
        @{ Label = "Add User"; Value = "usr_add" }
        @{ Label = "Delete User"; Value = "usr_del" }
    )}
    @{ Label = "Exit Application"; Value = "exit" }
)

# A settings-style tree exercising the value column (Display) and the help band
# (HelpTitle + Help). Content is English filler — like $menuData above, real
# callers supply their own translated data. Note "Telemetry" deliberately omits
# Help to show the band reserving a blank line so the box height stays steady.
$settingsMenuData = @(
    @{ Label = "Theme";     Value = "set_theme"; Display = "Dark";
       HelpTitle = "Color scheme"; Help = "Palette used across every widget — borders, highlights, and prompt text all follow it." }
    @{ Label = "Language";  Value = "set_lang";  Display = "English";
       HelpTitle = "UI language"; Help = "Language for the built-in chrome and prompts. Your own menu data is translated separately." }
    @{ Label = "Log level"; Value = "set_log";   Display = "Verbose";
       HelpTitle = "Verbosity"; Help = "How much detail is written to the log. Higher levels help when diagnosing issues but produce larger files." }
    @{ Label = "Telemetry"; Value = "set_telem"; Display = "Off" }
    @{ Label = "Advanced";  Display = ""; HelpTitle = "More settings"; Help = "Drill in for less-common options."; Children = @(
        @{ Label = "Cache size"; Value = "adv_cache"; Display = "256 MB";
           HelpTitle = "Disk cache"; Help = "Maximum space used for cached data before the oldest entries are evicted." }
        @{ Label = "Retries";    Value = "adv_retry"; Display = "3";
           HelpTitle = "Network retries"; Help = "How many times a failed request is retried before giving up." }
    )}
    @{ Label = "Back"; Value = "exit" }
)

# Maps each leaf demo's Value to the primary function it showcases. Used as the
# right-hand value column when the top-level demo menu is shown with aligned
# columns — see Add-DemoMenuColumns. Codes are language-neutral, so no l10n here.
$demoFn = @{
    paginated = 'Get-PaginatedSelection'; paginated_jump = 'Get-PaginatedSelection'; multiselect = 'Get-PaginatedSelection'
    nested = 'Invoke-NestedMenu'; nested_deep = 'Invoke-NestedMenu'; nested_bordered = 'Invoke-NestedMenu'; settings_menu = 'Invoke-NestedMenu'
    masked = 'Read-MaskedInput'; password = 'Read-Password'; validated = 'Read-ValidatedInput'; confirm = 'Read-Confirmation'; choice = 'Read-Choice'
    number = 'Read-Number'; number_wrappers = 'Read-Number family'; measurement = 'Read-Measurement'; templated = 'Read-Phone family'
    date = 'Read-Date'; date_calendar = 'Read-Date'; time = 'Read-Time'; time_twelve = 'Read-Time'; timezone = 'Read-Timezone'
    spinner = 'Show-Spinner'; spinner_timer = 'Show-Spinner'; spinner_styles = 'Show-Spinner'; spinner_closure = 'Show-Spinner'
    uibox = 'Write-TuiBox'
}

$systemObjects = @()
$id = 100
foreach ($name in @(
    "Active Directory Domain Services","Amazon Web Services (AWS)","Azure Virtual Machines",
    "Cisco AnyConnect VPN","Cove Data Protection","Docker Container Runtime",
    "HaloPSA Professional Services","Hyper-V Host Node","Kubernetes Cluster",
    "Microsoft Exchange Online","Microsoft SQL Server","Microsoft Teams",
    "Network Policy Server","Palo Alto Firewall","PostgreSQL Database",
    "PowerShell Core","ServiceNow Ticketing","SharePoint Online",
    "Ubuntu Linux 24.04","Veeam Backup & Replication","VMware vSphere ESXi","Windows Server 2022"
)) {
    $systemObjects += [PSCustomObject]@{
        ID   = $id
        Name = $name
        Type = if ($name -match "Microsoft|Windows|Azure|Active Directory") { "Microsoft" } else { "Third-Party" }
    }
    $id++
}

# --- Demo helpers ------------------------------------------------------------

function Add-DemoMenuColumns {
    # Enriches the demo menu tree in place so Invoke-NestedMenu renders it with
    # the aligned value column + help band — i.e. the demo's own navigation
    # menu showcases those features. It reuses the already-localized labels:
    # each leaf's "Name (detail)" label is split into a short Label plus the
    # detail as Help, the showcased function name is attached as Display, and
    # each parent shows its child count. The only new localized string is the
    # 'About' help title, so no per-entry retranslation is needed.
    param([array]$Tree, [hashtable]$FnMap, [string]$AboutTitle)
    foreach ($node in $Tree) {
        if ($node.ContainsKey('Children') -and $node.Children -and $node.Children.Count -gt 0) {
            $node.Display = [string]$node.Children.Count
            Add-DemoMenuColumns -Tree $node.Children -FnMap $FnMap -AboutTitle $AboutTitle
        } else {
            # Only enrich actual demo leaves (those in the function map). The
            # toggle / language / exit controls keep their plain labels and get
            # no value/help — so the top tier shows just the count column with no
            # mostly-empty help band. Each enriched leaf's "Friendly Name
            # (detail)" label is split into label + help; labels without a
            # parenthetical keep their text and reserve a blank help line.
            $val = if ($node.ContainsKey('Value')) { [string]$node.Value } else { '' }
            if ($FnMap.ContainsKey($val)) {
                if ($node.Label -match '^(.*?)\s*\((.*)\)\s*$') {
                    $node.Label     = $matches[1]
                    $node.HelpTitle = $AboutTitle
                    $node.Help      = $matches[2]
                }
                $node.Display = $FnMap[$val]
            }
        }
    }
}

function Write-DemoHeader([string]$Title) {
    Write-Host ""
    Write-Host "--- $Title ---" -ForegroundColor Cyan
}

function Wait-ReturnKey {
    Write-Host ""
    Write-Host (Get-DemoString 'Common_PressAnyKey') -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
}

# --- Individual demos --------------------------------------------------------

function Show-PaginatedDemo {
    Write-DemoHeader (Get-DemoString 'Header_Paginated')
    Write-Host (Get-DemoString 'Hint_Paginated') -ForegroundColor DarkGray
    $r = Get-PaginatedSelection -Items $systemObjects -PageSize 12 -Title (Get-DemoString 'Title_SelectSystemObject') -DisplayProperty "Name" -Wrap -Searchable
    if ($r) { Write-Host (Get-DemoString 'Result_YouSelectedWithID' $r.Name $r.ID) -ForegroundColor Green }
    else    { Write-Host (Get-DemoString 'Result_SelectionCancelled') -ForegroundColor Yellow }
    Wait-ReturnKey
}

function Show-PaginatedJumpDemo {
    Write-DemoHeader (Get-DemoString 'Header_PaginatedJump')
    $r = Get-PaginatedSelection -Items $systemObjects -PageSize 10 -InitialIndex 24 -Title (Get-DemoString 'Title_JumpedToItem25') -DisplayProperty "Name"
    if ($r) { Write-Host (Get-DemoString 'Result_YouSelected' $r.Name) -ForegroundColor Green }
    else    { Write-Host (Get-DemoString 'Result_SelectionCancelled') -ForegroundColor Yellow }
    Wait-ReturnKey
}

function Show-MultiSelectDemo {
    Write-DemoHeader (Get-DemoString 'Header_MultiSelect')
    Write-Host (Get-DemoString 'Hint_MultiSelect') -ForegroundColor DarkGray
    # Pre-check the first two items so the demo shows the seeded state.
    $preChecked = @($systemObjects | Select-Object -First 2)
    $r = Get-PaginatedSelection -Items $systemObjects -PageSize 10 -Title (Get-DemoString 'Title_PickMultiple') -DisplayProperty "Name" -Wrap -Searchable -MultiSelect -PreSelected $preChecked
    if ($null -eq $r) {
        Write-Host (Get-DemoString 'Result_Cancelled') -ForegroundColor Yellow
    } elseif ($r.Count -eq 0) {
        Write-Host (Get-DemoString 'Result_ConfirmedNoSelections') -ForegroundColor Yellow
    } else {
        Write-Host (Get-DemoString 'Result_SelectedItems' $r.Count) -ForegroundColor Green
        $r | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Green }
    }
    Wait-ReturnKey
}

function Show-NestedMenuDemo {
    Write-DemoHeader (Get-DemoString 'Header_NestedMenu')
    $r = Invoke-NestedMenu -MenuTree $menuData -Title (Get-DemoString 'Title_AdminPortal')
    if ($r) { Write-Host (Get-DemoString 'Result_CapturedAction' $r) -ForegroundColor Green }
    else    { Write-Host (Get-DemoString 'Result_MenuCancelled') -ForegroundColor Yellow }
    Wait-ReturnKey
}

function Show-NestedMenuDeepDemo {
    Write-DemoHeader (Get-DemoString 'Header_NestedMenuDeep')
    $r = Invoke-NestedMenu -MenuTree $menuData -Title (Get-DemoString 'Title_AdminPortal') -InitialPath @("System Configuration", "Power Options", 1)
    if ($r) { Write-Host (Get-DemoString 'Result_Captured' $r) -ForegroundColor Green }
    Wait-ReturnKey
}

function Show-SettingsMenuDemo {
    Write-DemoHeader (Get-DemoString 'Header_SettingsMenu')
    $r = Invoke-NestedMenu -MenuTree $settingsMenuData -Title (Get-DemoString 'Title_AdminPortal') -Border -MinWidth 50
    if ($r) { Write-Host (Get-DemoString 'Result_Captured' $r) -ForegroundColor Green }
    else    { Write-Host (Get-DemoString 'Result_MenuCancelled') -ForegroundColor Yellow }
    Wait-ReturnKey
}

function Show-NestedMenuBorderedDemo {
    Write-DemoHeader (Get-DemoString 'Header_NestedMenuBordered')
    Write-Host (Get-DemoString 'Hint_NestedBordered') -ForegroundColor DarkGray
    $r = Invoke-NestedMenu -MenuTree $menuData -Title (Get-DemoString 'Title_BorderedMenu') -Border -MinWidth 40 -X 5 -Y 15 -AltScreen
    if ($r) { Write-Host (Get-DemoString 'Result_Captured' $r) -ForegroundColor Green }
    Wait-ReturnKey
}

function Show-MaskedInputDemo {
    Write-DemoHeader (Get-DemoString 'Header_MaskedInput')
    $phone = Read-MaskedInput -Mask "(###) ###-####" -Prompt (Get-DemoString 'Prompt_PhoneNumber') -Placeholder "_"
    if ($phone) { Write-Host (Get-DemoString 'Result_Captured' $phone) -ForegroundColor Green }
    $mac = Read-MaskedInput -Mask "XX:XX:XX:XX:XX:XX" -Prompt (Get-DemoString 'Prompt_MacAddress') -Placeholder "0"
    if ($mac)   { Write-Host (Get-DemoString 'Result_Captured' $mac) -ForegroundColor Green }
    Wait-ReturnKey
}

function Show-PasswordDemo {
    Write-DemoHeader (Get-DemoString 'Header_Password')
    Write-Host (Get-DemoString 'Hint_Password1') -ForegroundColor DarkGray
    Write-Host (Get-DemoString 'Hint_Password2') -ForegroundColor DarkGray

    $sec = Read-Password -Prompt (Get-DemoString 'Prompt_Password') -MinLength 4 -ShowStrength -StrengthVariable s
    if ($sec) {
        Write-Host (Get-DemoString 'Result_CapturedSecureString' $sec.Length) -ForegroundColor Green
        Write-Host (Get-DemoString 'Result_Strength' $s.Label $s.Score $s.Classes) -ForegroundColor $s.Color
    } else {
        Write-Host (Get-DemoString 'Result_Cancelled') -ForegroundColor Yellow
    }

    $confirmed = Read-Password -Prompt (Get-DemoString 'Prompt_NewPassword') -Confirm -MinLength 8 -ConfirmPrompt (Get-DemoString 'Prompt_Retype') -ShowStrength
    if ($confirmed) {
        Write-Host (Get-DemoString 'Result_ConfirmedSecureString' $confirmed.Length) -ForegroundColor Green
    } else {
        Write-Host (Get-DemoString 'Result_CancelledOrExhausted') -ForegroundColor Yellow
    }

    $plain = Read-Password -Prompt (Get-DemoString 'Prompt_PIN') -HideTyping -AsPlainText -MinLength 4 -MaxLength 6
    if ($plain) {
        Write-Host (Get-DemoString 'Result_CapturedPlainText' $plain) -ForegroundColor Green
    } else {
        Write-Host (Get-DemoString 'Result_Cancelled') -ForegroundColor Yellow
    }

    Wait-ReturnKey
}

function Show-ValidatedInputDemo {
    Write-DemoHeader (Get-DemoString 'Header_ValidatedInput')
    $ipv4 = Read-ValidatedInput -Prompt (Get-DemoString 'Prompt_IPv4') -Pattern '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    if ($ipv4) { Write-Host (Get-DemoString 'Result_Captured' $ipv4) -ForegroundColor Green }
    $cidr = Read-ValidatedInput -Prompt (Get-DemoString 'Prompt_CIDR') -Pattern '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/(?:[0-9]|[1-2][0-9]|3[0-2])$'
    if ($cidr) { Write-Host (Get-DemoString 'Result_Captured' $cidr) -ForegroundColor Green }
    $email = Read-ValidatedInput -Prompt (Get-DemoString 'Prompt_Email') -Pattern '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    if ($email) { Write-Host (Get-DemoString 'Result_Captured' $email) -ForegroundColor Green }
    Wait-ReturnKey
}

function Show-ConfirmationDemo {
    Write-DemoHeader (Get-DemoString 'Header_Confirmation')
    Write-Host (Get-DemoString 'Hint_Confirmation') -ForegroundColor DarkGray
    $delete = Read-Confirmation -Question (Get-DemoString 'Prompt_DeleteFile') -Default No
    if ($null -eq $delete) { Write-Host (Get-DemoString 'Result_CancelledNull') -ForegroundColor Yellow }
    elseif ($delete)       { Write-Host (Get-DemoString 'Result_ConfirmedYes') -ForegroundColor Green }
    else                   { Write-Host (Get-DemoString 'Result_ConfirmedNo')  -ForegroundColor Green }
    Wait-ReturnKey
}

function Show-ChoiceDemo {
    Write-DemoHeader (Get-DemoString 'Header_Choice')
    Write-Host (Get-DemoString 'Hint_Choice') -ForegroundColor DarkGray

    $color = Read-Choice -Question (Get-DemoString 'Prompt_PickColor') -Options 'Red','Green','Blue','Yellow','Magenta'
    if ($null -eq $color) { Write-Host (Get-DemoString 'Result_Cancelled') -ForegroundColor Yellow }
    else                   { Write-Host (Get-DemoString 'Result_Captured' $color) -ForegroundColor Green }

    Write-Host ""
    Write-Host (Get-DemoString 'Hint_ChoiceMulti') -ForegroundColor DarkGray
    $toppings = Read-Choice -Question (Get-DemoString 'Prompt_PickToppings') -Options 'Cheese','Pepperoni','Mushroom','Olives','Onion' -MultiSelect -PreSelected 0
    if ($null -eq $toppings)        { Write-Host (Get-DemoString 'Result_Cancelled') -ForegroundColor Yellow }
    elseif ($toppings.Count -eq 0)  { Write-Host (Get-DemoString 'Result_CapturedNone') -ForegroundColor Green }
    else                            { Write-Host (Get-DemoString 'Result_Captured' ($toppings -join ', ')) -ForegroundColor Green }

    Wait-ReturnKey
}

function Show-SpinnerDemo {
    Write-DemoHeader (Get-DemoString 'Header_Spinner')
    Write-Host (Get-DemoString 'Hint_Spinner') -ForegroundColor DarkGray
    Show-Spinner -Activity (Get-DemoString 'Activity_Working') -ScriptBlock { Start-Sleep -Milliseconds 2000 }
    Write-Host (Get-DemoString 'Result_Done') -ForegroundColor Green
    Wait-ReturnKey
}

function Show-SpinnerTimerDemo {
    Write-DemoHeader (Get-DemoString 'Header_SpinnerTimer')
    Write-Host (Get-DemoString 'Hint_SpinnerTimer') -ForegroundColor DarkGray
    Show-Spinner -Activity (Get-DemoString 'Activity_Querying') -ShowTimer -ScriptBlock { Start-Sleep -Milliseconds 3500 }
    Write-Host (Get-DemoString 'Result_Done') -ForegroundColor Green
    Wait-ReturnKey
}

function Show-SpinnerStylesDemo {
    Write-DemoHeader (Get-DemoString 'Header_SpinnerStyles')
    if ($script:demoAsciiMode) {
        Write-Host (Get-DemoString 'Hint_SpinnerStylesAscii') -ForegroundColor DarkGray
    }
    foreach ($style in 'Braille','Ascii','HalfBlocks','Dots','Circles','Pulse') {
        Show-Spinner -Activity (Get-DemoString 'Activity_StylePrefix' $style) -Style $style -ScriptBlock { Start-Sleep -Milliseconds 1500 }
    }
    Write-Host (Get-DemoString 'Result_AllStylesShown') -ForegroundColor Green
    Wait-ReturnKey
}

function Show-SpinnerClosureDemo {
    Write-DemoHeader (Get-DemoString 'Header_SpinnerClosure')
    $magicNumber = 42
    Write-Host (Get-DemoString 'Hint_SpinnerClosure' $magicNumber) -ForegroundColor DarkGray
    $result = Show-Spinner -Activity (Get-DemoString 'Activity_Computing') -ShowTimer -ScriptBlock {
        Start-Sleep -Milliseconds 1500
        $magicNumber * 2
    }
    Write-Host (Get-DemoString 'Result_ScriptblockReturned' $result) -ForegroundColor Green
    Wait-ReturnKey
}

function Show-UIBoxDemo {
    Write-DemoHeader (Get-DemoString 'Header_UIBox')
    Write-TuiBox -Header (Get-DemoString 'Title_SystemStatus') -Body @(
        (Get-DemoString 'Common_BodyCPU'),
        (Get-DemoString 'Common_BodyRAM'),
        (Get-DemoString 'Common_BodyDisk')
    ) -Footer (Get-DemoString 'Common_DemoBox') -Border
    Wait-ReturnKey
}

function Show-DateDemo {
    Write-DemoHeader (Get-DemoString 'Header_Date')
    Write-Host (Get-DemoString 'Hint_Date') -ForegroundColor DarkGray
    $d = Read-Date -Prompt (Get-DemoString 'Prompt_PickDate')
    if ($d) { Write-Host (Get-DemoString 'Result_SelectedDate' $d.ToString('yyyy-MM-dd')) -ForegroundColor Green }
    else    { Write-Host (Get-DemoString 'Result_Cancelled') -ForegroundColor Yellow }
    Wait-ReturnKey
}

function Show-DateCalendarDemo {
    Write-DemoHeader (Get-DemoString 'Header_DateCalendar')
    Write-Host (Get-DemoString 'Hint_DateCalendar1') -ForegroundColor DarkGray
    Write-Host (Get-DemoString 'Hint_DateCalendar2') -ForegroundColor DarkGray
    $d = Read-Date -Prompt (Get-DemoString 'Prompt_ScheduleFor') -Calendar `
        -InitialDate ((Get-Date).Date.AddDays(7)) `
        -MinDate (Get-Date).Date `
        -MaxDate (Get-Date).Date.AddYears(1)
    if ($d) { Write-Host (Get-DemoString 'Result_SelectedDate' $d.ToString('dddd, MMMM d, yyyy')) -ForegroundColor Green }
    else    { Write-Host (Get-DemoString 'Result_Cancelled') -ForegroundColor Yellow }
    Wait-ReturnKey
}

function Show-TimeDemo {
    Write-DemoHeader (Get-DemoString 'Header_Time')
    Write-Host (Get-DemoString 'Hint_Time') -ForegroundColor DarkGray
    $t = Read-Time -Prompt (Get-DemoString 'Prompt_StartTime')
    if ($null -ne $t) { Write-Host (Get-DemoString 'Result_SelectedTime' $t.ToString()) -ForegroundColor Green }
    else              { Write-Host (Get-DemoString 'Result_Cancelled') -ForegroundColor Yellow }
    Wait-ReturnKey
}

function Show-TimeTwelveDemo {
    Write-DemoHeader (Get-DemoString 'Header_TimeTwelve')
    Write-Host (Get-DemoString 'Hint_TimeTwelve') -ForegroundColor DarkGray
    $t = Read-Time -Prompt (Get-DemoString 'Prompt_Alarm') -TwelveHour -ShowSeconds `
        -InitialTime ([TimeSpan]::new(14, 30, 0))
    if ($null -ne $t) { Write-Host (Get-DemoString 'Result_SelectedTime' $t.ToString()) -ForegroundColor Green }
    else              { Write-Host (Get-DemoString 'Result_Cancelled') -ForegroundColor Yellow }
    Wait-ReturnKey
}

function Show-NumberDemo {
    Write-DemoHeader (Get-DemoString 'Header_Number')
    Write-Host (Get-DemoString 'Hint_Number1') -ForegroundColor DarkGray
    Write-Host (Get-DemoString 'Hint_Number2') -ForegroundColor DarkGray

    # -Bar works on any Read-Number range, not just percentages — here it
    # shows where the chosen port sits in the 1..65535 space at a glance.
    $port = Read-Number -Prompt (Get-DemoString 'Prompt_Port') -Min 1 -Max 65535 -Default 8080 -Bar
    if ($null -ne $port) { Write-Host (Get-DemoString 'Result_Captured' $port) -ForegroundColor Green }

    $pct = Read-Number -Prompt (Get-DemoString 'Prompt_Coverage') -Min 0 -Max 100 -Default 75 -Suffix ' %'
    if ($null -ne $pct) { Write-Host (Get-DemoString 'Result_Captured' "$pct%") -ForegroundColor Green }

    $temp = Read-Number -Prompt (Get-DemoString 'Prompt_Temperature') -Min -50 -Max 150 -Default 20 -Suffix ([char]0x00B0 + 'C')
    if ($null -ne $temp) { Write-Host (Get-DemoString 'Result_Captured' "$temp$([char]0x00B0)C") -ForegroundColor Green }

    $big = Read-Number -Prompt (Get-DemoString 'Prompt_Budget') -Min 0 -Max 1000000000 -Default 1000000 -ThousandsSeparator
    if ($null -ne $big) { Write-Host (Get-DemoString 'Result_Captured' $big) -ForegroundColor Green }

    $amt = Read-Number -Prompt (Get-DemoString 'Prompt_Amount') -Min 0 -Max 1000000 -Default 9.99 `
        -Precision 2 -Prefix '$' -ThousandsSeparator
    if ($null -ne $amt) { Write-Host (Get-DemoString 'Result_Captured' ('${0:N2}' -f $amt)) -ForegroundColor Green }

    Wait-ReturnKey
}

function Show-NumberWrappersDemo {
    Write-DemoHeader (Get-DemoString 'Header_NumberWrappers')
    Write-Host (Get-DemoString 'Hint_NumberWrappers') -ForegroundColor DarkGray

    $pct = Read-Percentage -Prompt (Get-DemoString 'Prompt_Coverage') -Default 50
    if ($null -ne $pct) { Write-Host (Get-DemoString 'Result_Captured' "$pct%") -ForegroundColor Green }

    $bar = Read-Percentage -Prompt (Get-DemoString 'Prompt_Progress') -Default 30 -Bar
    if ($null -ne $bar) { Write-Host (Get-DemoString 'Result_Captured' "$bar%") -ForegroundColor Green }

    $temp = Read-Temperature -Prompt (Get-DemoString 'Prompt_Temperature')
    if ($null -ne $temp) { Write-Host (Get-DemoString 'Result_Captured' $temp) -ForegroundColor Green }

    $body = Read-Temperature -Prompt (Get-DemoString 'Prompt_BodyTemp') -Unit Celsius `
        -Min 30 -Max 45 -Default 37 -Precision 1
    if ($null -ne $body) { Write-Host (Get-DemoString 'Result_Captured' $body) -ForegroundColor Green }

    $amt = Read-Currency -Prompt (Get-DemoString 'Prompt_Amount') -Default 9.99
    if ($null -ne $amt) { Write-Host (Get-DemoString 'Result_Captured' $amt) -ForegroundColor Green }

    Wait-ReturnKey
}

function Show-MeasurementDemo {
    Write-DemoHeader (Get-DemoString 'Header_Measurement')
    Write-Host (Get-DemoString 'Hint_Measurement') -ForegroundColor DarkGray

    # Length: mixed-unit input. Type "5'11\"", "1m 80cm", or "100cm";
    # the live decorator shows the value converted into the region's
    # preferred unit (m or ft). -DefaultsByUnit pulls Min/Max/Default
    # from units/length.psd1's UnitDefaults block.
    $len = Read-Measurement -Prompt (Get-DemoString 'Prompt_Distance') `
        -Family Length -DefaultsByUnit
    if ($null -ne $len) { Write-Host (Get-DemoString 'Result_Captured' $len) -ForegroundColor Green }

    # Temperature: same engine, different family file. Type "72°F",
    # "20°C", or any plain number with no suffix (interpreted as the
    # region default). The decorator echoes the value in the chosen
    # output unit so the user can sanity-check the parse.
    $temp = Read-Measurement -Prompt (Get-DemoString 'Prompt_Ambient') `
        -Family Temperature -DefaultsByUnit
    if ($null -ne $temp) { Write-Host (Get-DemoString 'Result_Captured' $temp) -ForegroundColor Green }

    Wait-ReturnKey
}

function Show-TemplatedWrappersDemo {
    Write-DemoHeader (Get-DemoString 'Header_TemplatedWrappers')
    Write-Host (Get-DemoString 'Hint_Templated') -ForegroundColor DarkGray

    $phone = Read-Phone -Prompt (Get-DemoString 'Prompt_Phone')
    if ($phone) { Write-Host (Get-DemoString 'Result_Captured' $phone) -ForegroundColor Green }

    $email = Read-Email -Prompt (Get-DemoString 'Prompt_EmailShort')
    if ($email) { Write-Host (Get-DemoString 'Result_Captured' $email) -ForegroundColor Green }

    $ipv4 = Read-IPv4 -Prompt (Get-DemoString 'Prompt_IPv4Short')
    if ($ipv4) { Write-Host (Get-DemoString 'Result_Captured' $ipv4) -ForegroundColor Green }

    $cidr = Read-CIDR -Prompt (Get-DemoString 'Prompt_CIDRShort')
    if ($cidr) { Write-Host (Get-DemoString 'Result_Captured' $cidr) -ForegroundColor Green }

    $url = Read-URL -Prompt (Get-DemoString 'Prompt_URL')
    if ($url) { Write-Host (Get-DemoString 'Result_Captured' $url) -ForegroundColor Green }

    Wait-ReturnKey
}

function Show-TimezoneDemo {
    Write-DemoHeader (Get-DemoString 'Header_Timezone')
    Write-Host (Get-DemoString 'Hint_Timezone1') -ForegroundColor DarkGray
    Write-Host (Get-DemoString 'Hint_Timezone2') -ForegroundColor DarkGray
    $tz = Read-Timezone -PreferredTimezones 'UTC','America/New_York','America/Los_Angeles','Europe/London','Asia/Tokyo'
    if ($tz) {
        Write-Host (Get-DemoString 'Result_SelectedTimezone' $tz.Id) -ForegroundColor Green
        Write-Host (Get-DemoString 'Result_TimezoneDisplay' $tz.DisplayName) -ForegroundColor Green
        $localNow = Get-Date
        $converted = [TimeZoneInfo]::ConvertTime($localNow, $tz)
        Write-Host (Get-DemoString 'Result_LocalNow' $localNow) -ForegroundColor DarkGray
        Write-Host (Get-DemoString 'Result_InSelected' $converted) -ForegroundColor DarkGray
    } else {
        Write-Host (Get-DemoString 'Result_Cancelled') -ForegroundColor Yellow
    }
    Wait-ReturnKey
}

# --- Top-level demo selector -------------------------------------------------

# Rebuild the menu tree each iteration so the "Toggle Render Mode" label
# always shows the current mode without restarting the script, and so the
# whole menu re-renders in the current language after a Set-DemoCulture.
$running = $true
while ($running) {
    $modeLabel = if ($script:demoAsciiMode) { 'ASCII' } else { 'Unicode' }
    $demoMenu = @(
        @{ Label = (Get-DemoString 'Menu_Group_SelectionMenus'); Children = @(
            @{ Label = (Get-DemoString 'Menu_Paginated');       Value = "paginated" }
            @{ Label = (Get-DemoString 'Menu_PaginatedJump');   Value = "paginated_jump" }
            @{ Label = (Get-DemoString 'Menu_MultiSelect');     Value = "multiselect" }
            @{ Label = (Get-DemoString 'Menu_Nested');          Value = "nested" }
            @{ Label = (Get-DemoString 'Menu_NestedDeep');      Value = "nested_deep" }
            @{ Label = (Get-DemoString 'Menu_NestedBordered');  Value = "nested_bordered" }
            @{ Label = (Get-DemoString 'Menu_SettingsMenu');    Value = "settings_menu" }
        )}
        @{ Label = (Get-DemoString 'Menu_Group_InputPrompts'); Children = @(
            @{ Label = (Get-DemoString 'Menu_MaskedInput');       Value = "masked" }
            @{ Label = (Get-DemoString 'Menu_PasswordInput');     Value = "password" }
            @{ Label = (Get-DemoString 'Menu_ValidatedInput');    Value = "validated" }
            @{ Label = (Get-DemoString 'Menu_Confirmation');      Value = "confirm" }
            @{ Label = (Get-DemoString 'Menu_ChoiceSelector');    Value = "choice" }
            @{ Label = (Get-DemoString 'Menu_NumberInput');       Value = "number" }
            @{ Label = (Get-DemoString 'Menu_NumberWrappers');    Value = "number_wrappers" }
            @{ Label = (Get-DemoString 'Menu_Measurement');       Value = "measurement" }
            @{ Label = (Get-DemoString 'Menu_TemplatedWrappers'); Value = "templated" }
        )}
        @{ Label = (Get-DemoString 'Menu_Group_DateTime'); Children = @(
            @{ Label = (Get-DemoString 'Menu_DateInline');    Value = "date" }
            @{ Label = (Get-DemoString 'Menu_DateCalendar');  Value = "date_calendar" }
            @{ Label = (Get-DemoString 'Menu_Time24');        Value = "time" }
            @{ Label = (Get-DemoString 'Menu_Time12');        Value = "time_twelve" }
            @{ Label = (Get-DemoString 'Menu_Timezone');      Value = "timezone" }
        )}
        @{ Label = (Get-DemoString 'Menu_Group_AsyncLayout'); Children = @(
            @{ Label = (Get-DemoString 'Menu_Spinner');         Value = "spinner" }
            @{ Label = (Get-DemoString 'Menu_SpinnerTimer');    Value = "spinner_timer" }
            @{ Label = (Get-DemoString 'Menu_SpinnerStyles');   Value = "spinner_styles" }
            @{ Label = (Get-DemoString 'Menu_SpinnerClosure');  Value = "spinner_closure" }
            @{ Label = (Get-DemoString 'Menu_UIBox');           Value = "uibox" }
        )}
        @{ Label = (Get-DemoString 'Menu_ToggleRenderMode' $modeLabel); Value = "toggle_ascii" }
        @{ Label = (Get-DemoString 'Menu_ChangeLanguage' $script:demoCulture); Children = @(
            @{ Label = "English (en-US)";  Value = "lang_en" }
            @{ Label = "Français (fr-FR)"; Value = "lang_fr" }
            @{ Label = "Español (es-ES)";  Value = "lang_es" }
            @{ Label = "Deutsch (de-DE)";  Value = "lang_de" }
            @{ Label = "日本語 (ja-JP)";   Value = "lang_ja" }
            @{ Label = "简体中文 (zh-CN)"; Value = "lang_zh" }
        )}
        @{ Label = (Get-DemoString 'Menu_ExitDemo'); Value = "exit" }
    )

    # The demo's own menu doubles as a live showcase of the value column + help
    # band: enrich it in place before rendering.
    Add-DemoMenuColumns -Tree $demoMenu -FnMap $demoFn -AboutTitle (Get-DemoString 'Help_About')

    $choice = Invoke-NestedMenu -MenuTree $demoMenu -Title (Get-DemoString 'Title_Demo' $modeLabel $script:demoCulture)
    switch ($choice) {
        'paginated'         { Show-PaginatedDemo }
        'paginated_jump'    { Show-PaginatedJumpDemo }
        'multiselect'       { Show-MultiSelectDemo }
        'nested'            { Show-NestedMenuDemo }
        'nested_deep'       { Show-NestedMenuDeepDemo }
        'nested_bordered'   { Show-NestedMenuBorderedDemo }
        'settings_menu'     { Show-SettingsMenuDemo }
        'masked'            { Show-MaskedInputDemo }
        'password'          { Show-PasswordDemo }
        'validated'         { Show-ValidatedInputDemo }
        'confirm'           { Show-ConfirmationDemo }
        'choice'            { Show-ChoiceDemo }
        'number'            { Show-NumberDemo }
        'number_wrappers'   { Show-NumberWrappersDemo }
        'measurement'       { Show-MeasurementDemo }
        'templated'         { Show-TemplatedWrappersDemo }
        'spinner'           { Show-SpinnerDemo }
        'spinner_timer'     { Show-SpinnerTimerDemo }
        'spinner_styles'    { Show-SpinnerStylesDemo }
        'spinner_closure'   { Show-SpinnerClosureDemo }
        'uibox'             { Show-UIBoxDemo }
        'date'              { Show-DateDemo }
        'date_calendar'     { Show-DateCalendarDemo }
        'time'              { Show-TimeDemo }
        'time_twelve'       { Show-TimeTwelveDemo }
        'timezone'          { Show-TimezoneDemo }
        'toggle_ascii'      { Set-DemoAsciiMode (-not $script:demoAsciiMode) }
        'lang_en'           { Set-DemoCulture 'en-US' }
        'lang_fr'           { Set-DemoCulture 'fr-FR' }
        'lang_es'           { Set-DemoCulture 'es-ES' }
        'lang_de'           { Set-DemoCulture 'de-DE' }
        'lang_ja'           { Set-DemoCulture 'ja-JP' }
        'lang_zh'           { Set-DemoCulture 'zh-CN' }
        'exit'              { $running = $false }
        default             { $running = $false }   # $null = Esc at top menu
    }
}

Write-Host ""
Write-Host (Get-DemoString 'Common_Thanks') -ForegroundColor Cyan
