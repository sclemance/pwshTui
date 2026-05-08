# Demo for pwshui
Import-Module ./pwshui.psd1 -Force

# --- Demo 1: Nested Menu ---
Write-Host "--- Nested Menu Demo ---" -ForegroundColor Cyan

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

$menuSelection = Invoke-NestedMenu -MenuTree $menuData -Title "Admin Portal"
if ($menuSelection) { Write-Host "Captured Action Value: $menuSelection`n" -ForegroundColor Green }

# --- Demo 2: Paginated Selection ---
$demoData = @(
    "Active Directory Domain Services"
    "Amazon Web Services (AWS)"
    "Azure Virtual Machines"
    "Cisco AnyConnect VPN"
    "Cove Data Protection"
    "Docker Container Runtime"
    "HaloPSA Professional Services"
    "Hyper-V Host Node"
    "Kubernetes Cluster"
    "Microsoft Exchange Online"
    "Microsoft SQL Server"
    "Microsoft Teams"
    "Network Policy Server"
    "Palo Alto Firewall"
    "PostgreSQL Database"
    "PowerShell Core"
    "ServiceNow Ticketing"
    "SharePoint Online"
    "Ubuntu Linux 24.04"
    "Veeam Backup & Replication"
    "VMware vSphere ESXi"
    "Windows Server 2022"
)

$items = 0..($demoData.Count - 1) | ForEach-Object { 
    [PSCustomObject]@{
        ID = $_ + 100
        Name = $demoData[$_]
        Type = if ($demoData[$_] -match "Microsoft|Windows|Azure|Active Directory") { "Microsoft" } else { "Third-Party" }
    }
}

$selected = Get-PaginatedSelection -Items $items -PageSize 12 -Title "--- Select a System Object ---" -DisplayProperty "Name" -Wrap -Searchable

if ($null -ne $selected) {
    Write-Host "`nYou selected: $($selected.Name) (ID: $($selected.ID))`n" -ForegroundColor Green
} else {
    Write-Host "`nSelection cancelled.`n" -ForegroundColor Yellow
}

# --- Demo 3: Masked Input ---
Write-Host "--- Masked Input Demo ---" -ForegroundColor Cyan
$phone = Read-MaskedInput -Mask "(###) ###-####" -Prompt "Enter Phone Number:" -Placeholder "_"
if ($phone) { Write-Host "Captured Value: $phone`n" -ForegroundColor Green }

$mac = Read-MaskedInput -Mask "XX:XX:XX:XX:XX:XX" -Prompt "Enter MAC Address:" -Placeholder "0"
if ($mac) { Write-Host "Captured Value: $mac`n" -ForegroundColor Green }

# --- Demo 4: Live Validation ---
Write-Host "--- Live Regex Validation Demo ---" -ForegroundColor Cyan

$ipv4 = Read-ValidatedInput -Prompt "Enter IPv4 Address:" -Pattern '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
if ($ipv4) { Write-Host "Captured Value: $ipv4`n" -ForegroundColor Green }

$cidr = Read-ValidatedInput -Prompt "Enter CIDR Notation:" -Pattern '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/(?:[0-9]|[1-2][0-9]|3[0-2])$'
if ($cidr) { Write-Host "Captured Value: $cidr`n" -ForegroundColor Green }

$email = Read-ValidatedInput -Prompt "Enter Email Address:" -Pattern '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
if ($email) { Write-Host "Captured Value: $email`n" -ForegroundColor Green }

# --- Demo 5: Initial Selection & Entry Points ---
Write-Host "--- Initial Selection & Entry Points Demo ---" -ForegroundColor Cyan

# Example 1: Nested Menu starting deep (Power Options > Power Saver)
Write-Host "Launching Nested Menu directly into 'Power Saver'..." -ForegroundColor Gray
$deepSelection = Invoke-NestedMenu -MenuTree $menuData -Title "Admin Portal" -InitialPath @("System Configuration", "Power Options", 1)
if ($deepSelection) { Write-Host "Captured Deep Action: $deepSelection`n" -ForegroundColor Green }

# Example 2: Paginated List starting on Item 25 (Page 3)
Write-Host "Launching Paginated Selection starting at Item 25..." -ForegroundColor Gray
$pagedSelection = Get-PaginatedSelection -Items $items -PageSize 10 -InitialIndex 24 -Title "Jumped to Item 25" -DisplayProperty "Name"
if ($pagedSelection) { Write-Host "Captured Jumped Item: $($pagedSelection.Name)`n" -ForegroundColor Green }

# --- Demo 6: Write-UIBox Standalone ---
Write-Host "--- Write-UIBox Standalone Demo ---" -ForegroundColor Cyan
Write-UIBox -Header "System Status" -Body @("CPU: 12%", "RAM: 4.2GB", "Disk: 80% Full") -Footer "Press any key to continue..." -Border

# --- Demo 7: Borders and Positioning ---
Write-Host "`n--- Borders and Positioning Demo ---" -ForegroundColor Cyan
Write-Host "Drawing a menu with borders at X=5, Y=15 using AltScreen..." -ForegroundColor Gray

$borderedSelection = Invoke-NestedMenu -MenuTree $menuData -Title "Bordered Menu" -Border -MinWidth 40 -X 5 -Y 15 -AltScreen
if ($borderedSelection) { Write-Host "Captured Action: $borderedSelection`n" -ForegroundColor Green }
