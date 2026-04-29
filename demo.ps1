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
$items = 1..50 | ForEach-Object { 
    [PSCustomObject]@{
        ID = $_
        Name = "Item $_"
        Description = "This is the description for item $_"
    }
}

$selected = Get-PaginatedSelection -Items $items -PageSize 12 -Title "--- Select a System Object ---" -DisplayProperty "Name" -Wrap

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
