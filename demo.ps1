# pwshTui demo — interactive, menu-driven tour of every exported function.
# Picks demos from a nested menu so you can run any one in isolation
# (and re-run them as many times as you like). Use the "Toggle Render Mode"
# entry on the menu to flip between Unicode (default) and ASCII fallback
# rendering to preview how the library degrades in restricted terminals.
Import-Module ./pwshTui.psd1 -Force

# Demo-level rendering preference. Toggled from the menu; threaded into every
# interactive call as -Ascii:$script:demoAsciiMode via the Get-DemoUI splat.
$script:demoAsciiMode = $false
function Get-DemoUI { @{ Ascii = $script:demoAsciiMode } }

# Tracks the language the demo last switched to. Starts as $PSUICulture-derived
# default. Changing it from the menu live-mutates the module's $script:_Strings
# via the module's session state — non-persistent: re-importing the module
# resets to whatever the OS / session $PSUICulture says.
$script:demoCulture = $PSUICulture

function Set-DemoCulture([string]$Culture) {
    $modulePath = (Get-Module pwshTui).ModuleBase
    $loaded = $null
    try {
        Import-LocalizedData -BindingVariable 'loaded' -BaseDirectory $modulePath -FileName 'pwshTui.Strings.psd1' -UICulture $Culture -ErrorAction Stop
    } catch {
        Write-Host "Could not load locale '$Culture'." -ForegroundColor Yellow
        return
    }
    if ($loaded) {
        # Push the loaded strings into the module's private $script:_Strings.
        # & (module) {…} executes the scriptblock in the module's session state
        # so the assignment lands on the same variable the functions read.
        & (Get-Module pwshTui) {
            param($newStrings)
            foreach ($k in $newStrings.Keys) { $script:_Strings[$k] = $newStrings[$k] }
        } $loaded
        $script:demoCulture = $Culture
    }
}

# --- Shared demo data --------------------------------------------------------

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

function Write-DemoHeader([string]$Title) {
    Write-Host ""
    Write-Host "--- $Title ---" -ForegroundColor Cyan
}

function Wait-ReturnKey {
    Write-Host ""
    Write-Host "[ Press any key to return to the menu ]" -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
}

# --- Individual demos --------------------------------------------------------

function Show-PaginatedDemo {
    Write-DemoHeader "Get-PaginatedSelection (searchable)"
    Write-Host "Type to fuzzy-search; arrows to navigate; Enter to pick; Esc to cancel." -ForegroundColor DarkGray
    $ui = Get-DemoUI
    $r = Get-PaginatedSelection -Items $systemObjects -PageSize 12 -Title "Select a System Object" -DisplayProperty "Name" -Wrap -Searchable @ui
    if ($r) { Write-Host "You selected: $($r.Name) (ID: $($r.ID))" -ForegroundColor Green }
    else    { Write-Host "Selection cancelled." -ForegroundColor Yellow }
    Wait-ReturnKey
}

function Show-PaginatedJumpDemo {
    Write-DemoHeader "Get-PaginatedSelection (-InitialIndex jumps to a specific item)"
    $ui = Get-DemoUI
    $r = Get-PaginatedSelection -Items $systemObjects -PageSize 10 -InitialIndex 24 -Title "Jumped to Item 25" -DisplayProperty "Name" @ui
    if ($r) { Write-Host "You selected: $($r.Name)" -ForegroundColor Green }
    else    { Write-Host "Selection cancelled." -ForegroundColor Yellow }
    Wait-ReturnKey
}

function Show-MultiSelectDemo {
    Write-DemoHeader "Get-PaginatedSelection -MultiSelect"
    Write-Host "Tab toggles; Enter confirms; Esc cancels. Search filter persists toggle state. Space is free for the search buffer." -ForegroundColor DarkGray
    $ui = Get-DemoUI
    $r = Get-PaginatedSelection -Items $systemObjects -PageSize 10 -Title "Pick multiple objects" -DisplayProperty "Name" -Wrap -Searchable -MultiSelect @ui
    if ($null -eq $r) {
        Write-Host "Cancelled." -ForegroundColor Yellow
    } elseif ($r.Count -eq 0) {
        Write-Host "Confirmed with no selections." -ForegroundColor Yellow
    } else {
        Write-Host "Selected $($r.Count) item(s):" -ForegroundColor Green
        $r | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Green }
    }
    Wait-ReturnKey
}

function Show-NestedMenuDemo {
    Write-DemoHeader "Invoke-NestedMenu"
    $ui = Get-DemoUI
    $r = Invoke-NestedMenu -MenuTree $menuData -Title "Admin Portal" @ui
    if ($r) { Write-Host "Captured Action: $r" -ForegroundColor Green }
    else    { Write-Host "Menu cancelled." -ForegroundColor Yellow }
    Wait-ReturnKey
}

function Show-NestedMenuDeepDemo {
    Write-DemoHeader "Invoke-NestedMenu -InitialPath (deep-link into Power Saver)"
    $ui = Get-DemoUI
    $r = Invoke-NestedMenu -MenuTree $menuData -Title "Admin Portal" -InitialPath @("System Configuration", "Power Options", 1) @ui
    if ($r) { Write-Host "Captured: $r" -ForegroundColor Green }
    Wait-ReturnKey
}

function Show-NestedMenuBorderedDemo {
    Write-DemoHeader "Invoke-NestedMenu (bordered, positioned, AltScreen)"
    Write-Host "Drawing a menu with -Border -MinWidth 40 -X 5 -Y 15 -AltScreen..." -ForegroundColor DarkGray
    $ui = Get-DemoUI
    $r = Invoke-NestedMenu -MenuTree $menuData -Title "Bordered Menu" -Border -MinWidth 40 -X 5 -Y 15 -AltScreen @ui
    if ($r) { Write-Host "Captured: $r" -ForegroundColor Green }
    Wait-ReturnKey
}

function Show-MaskedInputDemo {
    Write-DemoHeader "Read-MaskedInput"
    $phone = Read-MaskedInput -Mask "(###) ###-####" -Prompt "Phone Number:" -Placeholder "_"
    if ($phone) { Write-Host "Captured: $phone" -ForegroundColor Green }
    $mac = Read-MaskedInput -Mask "XX:XX:XX:XX:XX:XX" -Prompt "MAC Address:" -Placeholder "0"
    if ($mac)   { Write-Host "Captured: $mac" -ForegroundColor Green }
    Wait-ReturnKey
}

function Show-ValidatedInputDemo {
    Write-DemoHeader "Read-ValidatedInput"
    $ipv4 = Read-ValidatedInput -Prompt "IPv4 Address:" -Pattern '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    if ($ipv4) { Write-Host "Captured: $ipv4" -ForegroundColor Green }
    $cidr = Read-ValidatedInput -Prompt "CIDR Notation:" -Pattern '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/(?:[0-9]|[1-2][0-9]|3[0-2])$'
    if ($cidr) { Write-Host "Captured: $cidr" -ForegroundColor Green }
    $email = Read-ValidatedInput -Prompt "Email Address:" -Pattern '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    if ($email) { Write-Host "Captured: $email" -ForegroundColor Green }
    Wait-ReturnKey
}

function Show-ConfirmationDemo {
    Write-DemoHeader "Read-Confirmation"
    Write-Host "Y/N for instant answer; Left/Right/Tab to move highlight; Enter to confirm; Esc to cancel." -ForegroundColor DarkGray
    $delete = Read-Confirmation -Question "Delete the file?" -Default No
    if ($null -eq $delete) { Write-Host "Cancelled (returned `$null)." -ForegroundColor Yellow }
    elseif ($delete)       { Write-Host "Confirmed: Yes" -ForegroundColor Green }
    else                   { Write-Host "Confirmed: No"  -ForegroundColor Green }
    Wait-ReturnKey
}

function Show-SpinnerDemo {
    Write-DemoHeader "Show-Spinner (default Braille)"
    Write-Host "Running a 2-second sleep..." -ForegroundColor DarkGray
    $ui = Get-DemoUI
    Show-Spinner -Activity "Working" -ScriptBlock { Start-Sleep -Milliseconds 2000 } @ui
    Write-Host "Done." -ForegroundColor Green
    Wait-ReturnKey
}

function Show-SpinnerTimerDemo {
    Write-DemoHeader "Show-Spinner -ShowTimer"
    Write-Host "Running a 3.5-second sleep with the live elapsed-time counter..." -ForegroundColor DarkGray
    $ui = Get-DemoUI
    Show-Spinner -Activity "Querying" -ShowTimer -ScriptBlock { Start-Sleep -Milliseconds 3500 } @ui
    Write-Host "Done." -ForegroundColor Green
    Wait-ReturnKey
}

function Show-SpinnerStylesDemo {
    Write-DemoHeader "Show-Spinner — all six styles, 1.5s each"
    if ($script:demoAsciiMode) {
        Write-Host "ASCII mode is on — -Ascii forces Style=Ascii regardless of -Style, so all four render as the Ascii glyph below. Toggle ASCII off to see each style as-named." -ForegroundColor DarkGray
    }
    $ui = Get-DemoUI
    foreach ($style in 'Braille','Ascii','HalfBlocks','Dots','Circles','Pulse') {
        Show-Spinner -Activity "Style: $style" -Style $style -ScriptBlock { Start-Sleep -Milliseconds 1500 } @ui
    }
    Write-Host "All styles shown." -ForegroundColor Green
    Wait-ReturnKey
}

function Show-SpinnerClosureDemo {
    Write-DemoHeader "Show-Spinner — closures Just Work"
    $magicNumber = 42
    Write-Host "Caller scope holds `$magicNumber = $magicNumber. The scriptblock will use it without -ArgumentList." -ForegroundColor DarkGray
    $ui = Get-DemoUI
    $result = Show-Spinner -Activity "Computing" -ShowTimer -ScriptBlock {
        Start-Sleep -Milliseconds 1500
        $magicNumber * 2
    } @ui
    Write-Host "Scriptblock returned: $result (expected: 84)" -ForegroundColor Green
    Wait-ReturnKey
}

function Show-UIBoxDemo {
    Write-DemoHeader "Write-UIBox (standalone)"
    $ui = Get-DemoUI
    Write-UIBox -Header "System Status" -Body @("CPU: 12%","RAM: 4.2GB","Disk: 80% Full") -Footer "Demo box" -Border @ui
    Wait-ReturnKey
}

# --- Top-level demo selector -------------------------------------------------

# Rebuild the menu tree each iteration so the "Toggle Render Mode" label
# always shows the current mode without restarting the script.
$running = $true
while ($running) {
    $modeLabel = if ($script:demoAsciiMode) { 'ASCII' } else { 'Unicode' }
    $demoMenu = @(
        @{ Label = "Selection & Menus"; Children = @(
            @{ Label = "Paginated Selection (searchable)";                 Value = "paginated" }
            @{ Label = "Paginated Selection (-InitialIndex jump to #25)";  Value = "paginated_jump" }
            @{ Label = "Paginated Multi-Select (Tab toggles)";             Value = "multiselect" }
            @{ Label = "Nested Menu";                                      Value = "nested" }
            @{ Label = "Nested Menu (-InitialPath deep-link)";             Value = "nested_deep" }
            @{ Label = "Nested Menu (bordered + AltScreen)";               Value = "nested_bordered" }
        )}
        @{ Label = "Input Prompts"; Children = @(
            @{ Label = "Masked Input (phone, MAC)";                        Value = "masked" }
            @{ Label = "Validated Input (IPv4, CIDR, email)";              Value = "validated" }
            @{ Label = "Yes/No Confirmation";                              Value = "confirm" }
        )}
        @{ Label = "Async & Layout"; Children = @(
            @{ Label = "Show-Spinner (default Braille)";                   Value = "spinner" }
            @{ Label = "Show-Spinner with -ShowTimer";                     Value = "spinner_timer" }
            @{ Label = "Show-Spinner — all six styles";                    Value = "spinner_styles" }
            @{ Label = "Show-Spinner — closure capture";                   Value = "spinner_closure" }
            @{ Label = "Write-UIBox (standalone)";                         Value = "uibox" }
        )}
        @{ Label = "Toggle Render Mode (currently: $modeLabel)";           Value = "toggle_ascii" }
        @{ Label = "Change Language (currently: $script:demoCulture)"; Children = @(
            @{ Label = "English (en-US)";  Value = "lang_en" }
            @{ Label = "Français (fr-FR)"; Value = "lang_fr" }
            @{ Label = "Español (es-ES)";  Value = "lang_es" }
            @{ Label = "Deutsch (de-DE)";  Value = "lang_de" }
        )}
        @{ Label = "Exit demo";                                            Value = "exit" }
    )

    $ui = Get-DemoUI
    $choice = Invoke-NestedMenu -MenuTree $demoMenu -Title "pwshTui Demo [$modeLabel | $script:demoCulture]" @ui
    switch ($choice) {
        'paginated'         { Show-PaginatedDemo }
        'paginated_jump'    { Show-PaginatedJumpDemo }
        'multiselect'       { Show-MultiSelectDemo }
        'nested'            { Show-NestedMenuDemo }
        'nested_deep'       { Show-NestedMenuDeepDemo }
        'nested_bordered'   { Show-NestedMenuBorderedDemo }
        'masked'            { Show-MaskedInputDemo }
        'validated'         { Show-ValidatedInputDemo }
        'confirm'           { Show-ConfirmationDemo }
        'spinner'           { Show-SpinnerDemo }
        'spinner_timer'     { Show-SpinnerTimerDemo }
        'spinner_styles'    { Show-SpinnerStylesDemo }
        'spinner_closure'   { Show-SpinnerClosureDemo }
        'uibox'             { Show-UIBoxDemo }
        'toggle_ascii'      { $script:demoAsciiMode = -not $script:demoAsciiMode }
        'lang_en'           { Set-DemoCulture 'en-US' }
        'lang_fr'           { Set-DemoCulture 'fr-FR' }
        'lang_es'           { Set-DemoCulture 'es-ES' }
        'lang_de'           { Set-DemoCulture 'de-DE' }
        'exit'              { $running = $false }
        default             { $running = $false }   # $null = Esc at top menu
    }
}

Write-Host ""
Write-Host "Thanks for trying pwshTui." -ForegroundColor Cyan
