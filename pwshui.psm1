function Get-PaginatedSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Collections.IEnumerable]$Items,

        [Parameter(Position = 1)]
        [int]$PageSize = 10,

        [Parameter(Position = 2)]
        [string]$Title = "Select an item:",

        [Parameter(Position = 3)]
        [string]$DisplayProperty,

        [switch]$Wrap,

        [switch]$NoColor
    )

    $itemList = @($Items)
    if ($itemList.Count -eq 0) {
        Write-Warning "No items to select."
        return $null
    }

    $pageIndex = 0
    $selectedIndex = 0
    $pageCount = [Math]::Max(1, [Math]::Ceiling($itemList.Count / $PageSize))

    $pointer = "> "
    $emptyPointer = "  "

    $running = $true
    $result = $null

    # Track original cursor state so we can restore it accurately
    $originalCursorVisible = $true
    try {
        if ($null -ne $Host.UI.RawUI.CursorSize -and $Host.UI.RawUI.CursorSize -eq 0) {
            $originalCursorVisible = $false
        }
    } catch {}

    # Hide cursor using ANSI
    Write-Host "`e[?25l" -NoNewline

    try {
        # Initial empty line to separate from previous output
        Write-Host ""
        $firstRender = $true

        while ($running) {
            # Calculate current page items
            $startIdx = $pageIndex * $PageSize
            $currentPageItems = $itemList | Select-Object -Skip $startIdx -First $PageSize
            
            # Ensure selected index is valid for current page (preserves row when possible)
            if ($selectedIndex -ge $currentPageItems.Count) {
                $selectedIndex = [Math]::Max(0, $currentPageItems.Count - 1)
            }

            if (-not $firstRender) {
                # ANSI to move cursor up before drawing
                # Title (1) + Separator (1) + Items (PageSize) + Newline (1) + Footer1 (1) + Footer2 (1) = PageSize + 5
                $linesToMoveUp = $PageSize + 5
                Write-Host "`e[$($linesToMoveUp)A" -NoNewline
            }
            $firstRender = $false

            # Header
            Write-Host "$Title`e[K" -ForegroundColor Cyan
            Write-Host ("-" * $Title.Length + "`e[K") -ForegroundColor DarkGray

            # Items
            for ($i = 0; $i -lt $currentPageItems.Count; $i++) {
                $item = $currentPageItems[$i]
                $displayText = if ($DisplayProperty -and $item.$DisplayProperty) { $item.$DisplayProperty } else { $item.ToString() }
                $isRowSelected = ($i -eq $selectedIndex)
                
                if ($isRowSelected) {
                    if ($NoColor) {
                        Write-Host "$pointer$displayText`e[K"
                    } else {
                        Write-Host "$pointer" -NoNewline -ForegroundColor Cyan
                        Write-Host "$displayText`e[K" -BackgroundColor Cyan -ForegroundColor Black
                    }
                } else {
                    Write-Host "$emptyPointer$displayText`e[K"
                }
            }

            # Pad empty rows to keep footer stationary and overwrite artifacts
            $padding = $PageSize - $currentPageItems.Count
            $clearString = " " * [Console]::WindowWidth
            for ($i = 0; $i -lt $padding; $i++) {
                # Try to overwrite the full line if WindowWidth is available, else at least clear some space
                if ([Console]::WindowWidth -gt 0) {
                    Write-Host "`e[K" -NoNewline # ANSI Clear line from cursor right
                }
                Write-Host ""
            }

            # Footer
            $pageNumDisplay = "($($pageIndex + 1)/$pageCount)"
            $rangeDisplay = "($($startIdx + 1)-$([Math]::Min($startIdx + $PageSize, $itemList.Count)) of $($itemList.Count))"
            
            Write-Host "`e[K" # Newline before footer, clear any artifacts
            Write-Host "← Prev page $pageNumDisplay   → Next page $pageNumDisplay`e[K" -ForegroundColor DarkGray
            Write-Host "↑↓ Move $rangeDisplay   Enter Select    Esc Cancel`e[K" -ForegroundColor DarkGray

            # Key Input
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                'UpArrow' {
                    if ($selectedIndex -gt 0) {
                        $selectedIndex--
                    } elseif ($Wrap) {
                        $selectedIndex = $currentPageItems.Count - 1
                    }
                }
                'DownArrow' {
                    if ($selectedIndex -lt ($currentPageItems.Count - 1)) {
                        $selectedIndex++
                    } elseif ($Wrap) {
                        $selectedIndex = 0
                    }
                }
                'LeftArrow' {
                    if ($pageIndex -gt 0) {
                        $pageIndex--
                    } elseif ($Wrap) {
                        $pageIndex = ($pageIndex - 1 + $pageCount) % $pageCount
                    }
                }
                'RightArrow' {
                    if ($pageIndex -lt ($pageCount - 1)) {
                        $pageIndex++
                    } elseif ($Wrap) {
                        $pageIndex = ($pageIndex + 1) % $pageCount
                    }
                }
                'Enter' {
                    $result = $itemList[$startIdx + $selectedIndex]
                    $running = $false
                }
                'Escape' {
                    $result = $null
                    $running = $false
                }
            }
        }
    } finally {
        # ANSI to move cursor up before clearing on exit if we rendered at least once
        if (-not $firstRender) {
            $linesToMoveUp = $PageSize + 5
            Write-Host "`e[$($linesToMoveUp)A" -NoNewline
        }

        # Clear the menu area
        Write-Host "`e[J" -NoNewline

        # Restore cursor to its original state
        if ($originalCursorVisible) {
            Write-Host "`e[?25h" -NoNewline
        }

        # If cancelled or aborted, ensure the next prompt starts on a clean line
        if ($null -eq $result) {
            Write-Host ""
        }
    }

    return $result
}

function Read-MaskedInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Mask,

        [Parameter(Position = 1)]
        [string]$Prompt = "Enter value:",

        [Parameter(Position = 2)]
        [char]$Placeholder = '_',

        [switch]$AllowIncomplete,
        
        [switch]$ReturnRaw
    )

    # '#' = Digit
    # 'a' = Letter
    # 'X', 'x' = Hex character (Upper/Lower forced)
    # '*' = Any char
    $slots = @()
    for ($i = 0; $i -lt $Mask.Length; $i++) {
        $c = $Mask[$i]
        if ($c -in '#', 'a', 'X', 'x', '*') {
            $slots += [PSCustomObject]@{ Index = $i; Type = $c }
        }
    }

    if ($slots.Count -eq 0) {
        Write-Warning "Mask must contain at least one input slot (#, a, X, x, or *)."
        return $null
    }

    $rawInput = [System.Collections.Generic.List[char]]::new()
    $cursor = 0
    $running = $true

    # Track original cursor state
    $originalCursorVisible = $true
    try {
        if ($null -ne $Host.UI.RawUI.CursorSize -and $Host.UI.RawUI.CursorSize -eq 0) {
            $originalCursorVisible = $false
        }
    } catch {}

    $checkValid = {
        param([System.Collections.Generic.List[char]]$chars)
        for ($i = 0; $i -lt $chars.Count; $i++) {
            $expectedType = $slots[$i].Type
            $c = $chars[$i]
            $valid = $false
            if ($expectedType -eq '#' -and [char]::IsDigit($c)) { $valid = $true }
            elseif ($expectedType -eq 'a' -and [char]::IsLetter($c)) { $valid = $true }
            elseif ($expectedType -in 'X', 'x' -and $c.ToString() -match '^[0-9a-fA-F]$') { $valid = $true }
            elseif ($expectedType -eq '*' -and -not [char]::IsControl($c)) { $valid = $true }
            if (-not $valid) { return $false }
        }
        return $true
    }
    
    Write-Host "`e[?25l" -NoNewline # Hide real cursor

    try {
        while ($running) {
            # Determine next slot screen index for highlighting
            $nextSlotScreenIdx = -1
            if ($cursor -lt $slots.Count) {
                $nextSlotScreenIdx = $slots[$cursor].Index
            }

            # Render Prompt
            Write-Host "`r$Prompt " -NoNewline -ForegroundColor Cyan
            
            $displayStr = ""
            $slotIdx = 0

            for ($i = 0; $i -lt $Mask.Length; $i++) {
                $m = $Mask[$i]
                if ($m -in '#', 'a', 'X', 'x', '*') {
                    if ($slotIdx -lt $rawInput.Count) {
                        $charToPrint = $rawInput[$slotIdx]
                    } else {
                        $charToPrint = $Placeholder
                    }
                    $displayStr += $charToPrint
                    $slotIdx++
                } else {
                    $displayStr += $m
                }
            }

            # Draw Masked String
            for ($i = 0; $i -lt $displayStr.Length; $i++) {
                if ($i -eq $nextSlotScreenIdx) {
                    Write-Host "$($displayStr[$i])" -NoNewline -BackgroundColor Cyan -ForegroundColor Black
                } else {
                    Write-Host "$($displayStr[$i])" -NoNewline
                }
            }
            
            Write-Host "`e[K" -NoNewline # Clear to end of line

            # Handle Input
            $key = [Console]::ReadKey($true)

            if ($key.Key -eq 'Enter') {
                if ($AllowIncomplete -or $rawInput.Count -eq $slots.Count) {
                    $running = $false
                }
            } elseif ($key.Key -eq 'Escape') {
                $rawInput.Clear()
                $running = $false
            } elseif ($key.Key -eq 'LeftArrow') {
                if ($cursor -gt 0) { $cursor-- }
            } elseif ($key.Key -eq 'RightArrow') {
                if ($cursor -lt $rawInput.Count) { $cursor++ }
            } elseif ($key.Key -eq 'Home') {
                $cursor = 0
            } elseif ($key.Key -eq 'End') {
                $cursor = $rawInput.Count
            } elseif ($key.Key -eq 'Backspace') {
                if ($cursor -gt 0) {
                    $temp = [System.Collections.Generic.List[char]]::new([char[]]$rawInput.ToArray())
                    $temp.RemoveAt($cursor - 1)
                    if (& $checkValid $temp) {
                        $rawInput = $temp
                        $cursor--
                    }
                }
            } elseif ($key.Key -eq 'Delete') {
                if ($cursor -lt $rawInput.Count) {
                    $temp = [System.Collections.Generic.List[char]]::new([char[]]$rawInput.ToArray())
                    $temp.RemoveAt($cursor)
                    if (& $checkValid $temp) {
                        $rawInput = $temp
                    }
                }
            } else {
                if ($cursor -lt $slots.Count) {
                    $char = $key.KeyChar
                    if (-not [char]::IsControl($char)) {
                        $expectedType = $slots[$cursor].Type
                        if ($expectedType -eq 'X' -and $char.ToString() -match '^[0-9a-fA-F]$') { $char = [char]::ToUpper($char) }
                        if ($expectedType -eq 'x' -and $char.ToString() -match '^[0-9a-fA-F]$') { $char = [char]::ToLower($char) }

                        $temp = [System.Collections.Generic.List[char]]::new([char[]]$rawInput.ToArray())
                        if ($cursor -eq $temp.Count) {
                            $temp.Add($char)
                        } else {
                            $temp[$cursor] = $char
                        }

                        if (& $checkValid $temp) {
                            $rawInput = $temp
                            $cursor++
                        }
                    }
                }
            }
        }

        # Final Draw to remove highlight
        Write-Host "`r$Prompt $displayStr`e[K" 
    } finally {
        # Restore cursor to its original state
        if ($originalCursorVisible) {
            Write-Host "`e[?25h" -NoNewline
        }
        
        # Ensure the terminal prompt drops to a clean line on exit
        Write-Host ""
    }

    if ($rawInput.Count -eq 0 -and -not $AllowIncomplete) {
        return $null
    }

    if ($ReturnRaw) {
        return -join $rawInput
    } else {
        # Build final formatted string to return
        $finalStr = ""
        $slotIdx = 0
        for ($i = 0; $i -lt $Mask.Length; $i++) {
            $m = $Mask[$i]
            if ($m -in '#', 'a', 'X', 'x', '*') {
                if ($slotIdx -lt $rawInput.Count) {
                    $finalStr += $rawInput[$slotIdx]
                } else {
                    $finalStr += $Placeholder
                }
                $slotIdx++
            } else {
                $finalStr += $m
            }
        }
        return $finalStr
    }
}

function Read-ValidatedInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Prompt,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Pattern,

        [switch]$AllowEmpty
    )

    $rawInput = [System.Collections.Generic.List[char]]::new()
    $cursor = 0
    $running = $true
    
    # Track original cursor state
    $originalCursorVisible = $true
    try {
        if ($null -ne $Host.UI.RawUI.CursorSize -and $Host.UI.RawUI.CursorSize -eq 0) {
            $originalCursorVisible = $false
        }
    } catch {}

    Write-Host "`e[?25l" -NoNewline # Hide real cursor

    try {
        while ($running) {
            $currentStr = -join $rawInput
            $isValid = ($currentStr -match $Pattern)
            if ($AllowEmpty -and $currentStr.Length -eq 0) { $isValid = $true }

            # Render Prompt
            Write-Host "`r$Prompt " -NoNewline -ForegroundColor Cyan
            
            # Draw Input String
            $useColor = ($currentStr.Length -gt 0)
            $color = if ($isValid) { "Green" } else { "Red" }
            
            for ($i = 0; $i -le $currentStr.Length; $i++) {
                if ($i -eq $cursor) {
                    $charToDraw = if ($i -lt $currentStr.Length) { $currentStr[$i] } else { " " }
                    Write-Host $charToDraw -NoNewline -BackgroundColor Cyan -ForegroundColor Black
                } else {
                    if ($i -lt $currentStr.Length) {
                        if ($useColor) {
                            Write-Host $currentStr[$i] -NoNewline -ForegroundColor $color
                        } else {
                            Write-Host $currentStr[$i] -NoNewline
                        }
                    }
                }
            }
            
            Write-Host "`e[K" -NoNewline # Clear to end of line

            # Handle Input
            $key = [Console]::ReadKey($true)

            if ($key.Key -eq 'LeftArrow') {
                if ($cursor -gt 0) { $cursor-- }
            } elseif ($key.Key -eq 'RightArrow') {
                if ($cursor -lt $rawInput.Count) { $cursor++ }
            } elseif ($key.Key -eq 'Home') {
                $cursor = 0
            } elseif ($key.Key -eq 'End') {
                $cursor = $rawInput.Count
            } elseif ($key.Key -eq 'Backspace') {
                if ($cursor -gt 0) {
                    $rawInput.RemoveAt($cursor - 1)
                    $cursor--
                }
            } elseif ($key.Key -eq 'Delete') {
                if ($cursor -lt $rawInput.Count) {
                    $rawInput.RemoveAt($cursor)
                }
            } elseif ($key.Key -eq 'Enter') {
                if ($isValid) { $running = $false }
            } elseif ($key.Key -eq 'Escape') {
                $rawInput.Clear()
                $running = $false
            } else {
                $char = $key.KeyChar
                # Filter out control characters (like tab, etc)
                if (-not [char]::IsControl($char)) {
                    $rawInput.Insert($cursor, $char)
                    $cursor++
                }
            }
        }

        $finalStr = -join $rawInput
        Write-Host "`r$Prompt $finalStr`e[K" 
    } finally {
        # Restore cursor to its original state
        if ($originalCursorVisible) {
            Write-Host "`e[?25h" -NoNewline
        }

        # Ensure the terminal prompt drops to a clean line on exit
        Write-Host ""
    }

    if ($finalStr.Length -eq 0 -and -not $AllowEmpty) {
        return $null
    }

    return $finalStr
}

function Invoke-NestedMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [array]$MenuTree,

        [Parameter(Position = 1)]
        [string]$Title = "Main Menu"
    )

    # Helper to recursively normalize items
    function ConvertTo-MenuItem ($Item) {
        $obj = [PSCustomObject]@{
            Label = $null
            Value = $null
            Children = $null
        }
        if ($Item -is [hashtable] -or $Item -is [System.Collections.IDictionary]) {
            if ($Item.ContainsKey('Label')) { $obj.Label = $Item.Label }
            if ($Item.ContainsKey('Value')) { $obj.Value = $Item.Value }
            if ($Item.ContainsKey('Children')) {
                $obj.Children = @()
                foreach ($child in $Item.Children) {
                    $obj.Children += ConvertTo-MenuItem $child
                }
            }
        } else {
            if ($null -ne $Item.Label) { $obj.Label = $Item.Label } else { $obj.Label = $Item.ToString() }
            if ($null -ne $Item.Value) { $obj.Value = $Item.Value } else { $obj.Value = $Item }
            if ($null -ne $Item.Children) {
                $obj.Children = @()
                foreach ($child in $Item.Children) {
                    $obj.Children += ConvertTo-MenuItem $child
                }
            }
        }
        return $obj
    }

    $normalizedTree = @()
    foreach ($i in $MenuTree) {
        $normalizedTree += ConvertTo-MenuItem $i
    }

    $history = [System.Collections.Generic.List[PSCustomObject]]::new()
    $history.Add([PSCustomObject]@{ Title = $Title; Items = $normalizedTree; SelectedIndex = 0 })

    $running = $true
    $result = $null
    $numString = ""

    # Track original cursor state
    $originalCursorVisible = $true
    try {
        if ($null -ne $Host.UI.RawUI.CursorSize -and $Host.UI.RawUI.CursorSize -eq 0) {
            $originalCursorVisible = $false
        }
    } catch {}

    Write-Host "`e[?25l" -NoNewline # Hide real cursor

    try {
        Write-Host "" # Initial newline
        $firstRender = $true
        
        while ($running) {
            $currentMenu = $history[$history.Count - 1]
            $currentItems = $currentMenu.Items
            $selectedIndex = $currentMenu.SelectedIndex

            if (-not $firstRender) {
                # Move cursor back up to the top of the menu
                $linesToMoveUp = $currentItems.Count + 4
                Write-Host "`e[$($linesToMoveUp)A" -NoNewline
            }
            $firstRender = $false

            # Clear any artifacts from previous larger menus
            Write-Host "`e[J" -NoNewline 

            # Breadcrumbs
            $breadcrumb = ($history | ForEach-Object Title) -join " > "
            Write-Host "`r$breadcrumb" -ForegroundColor Cyan
            Write-Host ("-" * [Math]::Min($breadcrumb.Length, [Console]::WindowWidth)) -ForegroundColor DarkGray

            # Render Items
            $pointer = "> "
            $emptyPointer = "  "
            
            for ($i = 0; $i -lt $currentItems.Count; $i++) {
                $item = $currentItems[$i]
                $isRowSelected = ($i -eq $selectedIndex)
                $displayNum = $i + 1
                
                $suffix = if ($null -ne $item.Children -and $item.Children.Count -gt 0) { " ►" } else { "" }
                $displayText = "[$displayNum] $($item.Label)$suffix"

                if ($isRowSelected) {
                    Write-Host "$pointer" -NoNewline -ForegroundColor Cyan
                    Write-Host "$displayText" -BackgroundColor Cyan -ForegroundColor Black
                } else {
                    Write-Host "$emptyPointer$displayText"
                }
            }
            
            # Footer
            Write-Host ""
            Write-Host "↑↓ or 1-$($currentItems.Count): Move   →: Expand   ←: Back   Enter: Select   Esc: Exit" -ForegroundColor DarkGray

            # Handle Input
            $key = [Console]::ReadKey($true)

            if ([char]::IsDigit($key.KeyChar)) {
                $numString += $key.KeyChar
                $idx = [int]$numString - 1
                if ($idx -ge 0 -and $idx -lt $currentItems.Count) {
                    $currentMenu.SelectedIndex = $idx
                } else {
                    $numString = $key.KeyChar.ToString()
                    $idx = [int]$numString - 1
                    if ($idx -ge 0 -and $idx -lt $currentItems.Count) {
                        $currentMenu.SelectedIndex = $idx
                    } else {
                        $numString = ""
                    }
                }
            } else {
                $numString = "" # Reset numeric buffer
                
                if ($key.Key -eq 'UpArrow') {
                    if ($selectedIndex -gt 0) {
                        $currentMenu.SelectedIndex--
                    } else {
                        $currentMenu.SelectedIndex = $currentItems.Count - 1
                    }
                } elseif ($key.Key -eq 'DownArrow') {
                    if ($selectedIndex -lt ($currentItems.Count - 1)) {
                        $currentMenu.SelectedIndex++
                    } else {
                        $currentMenu.SelectedIndex = 0
                    }
                } elseif ($key.Key -eq 'LeftArrow') {
                    if ($history.Count -gt 1) {
                        $history.RemoveAt($history.Count - 1)
                        Write-Host "`e[$($currentItems.Count + 4)A`e[J" -NoNewline
                        $firstRender = $true
                    }
                } elseif ($key.Key -eq 'Escape') {
                    if ($history.Count -gt 1) {
                        $history.RemoveAt($history.Count - 1)
                        Write-Host "`e[$($currentItems.Count + 4)A`e[J" -NoNewline
                        $firstRender = $true
                    } else {
                        $running = $false
                        $result = $null
                    }
                } elseif ($key.Key -eq 'RightArrow') {
                    $selectedItem = $currentItems[$selectedIndex]
                    if ($null -ne $selectedItem.Children -and $selectedItem.Children.Count -gt 0) {
                        $history.Add([PSCustomObject]@{ Title = $selectedItem.Label; Items = $selectedItem.Children; SelectedIndex = 0 })
                        Write-Host "`e[$($currentItems.Count + 4)A`e[J" -NoNewline
                        $firstRender = $true
                    }
                } elseif ($key.Key -eq 'Enter') {
                    $selectedItem = $currentItems[$selectedIndex]
                    if ($null -ne $selectedItem.Children -and $selectedItem.Children.Count -gt 0) {
                        $history.Add([PSCustomObject]@{ Title = $selectedItem.Label; Items = $selectedItem.Children; SelectedIndex = 0 })
                        Write-Host "`e[$($currentItems.Count + 4)A`e[J" -NoNewline
                        $firstRender = $true
                    } else {
                        $result = $selectedItem.Value
                        $running = $false
                    }
                }
            }
        }
    } finally {
        # Move cursor back up before clearing on exit if we rendered at least once
        if (-not $firstRender) {
            $linesToMoveUp = $currentItems.Count + 4
            Write-Host "`e[$($linesToMoveUp)A" -NoNewline
        }

        # Clear the entire menu area from the screen on exit
        Write-Host "`e[J" -NoNewline
        
        # Restore cursor
        if ($originalCursorVisible) {
            Write-Host "`e[?25h" -NoNewline
        }

        # Clean line on abort
        if ($null -eq $result) {
            Write-Host ""
        }
    }

    return $result
}

Export-ModuleMember -Function Get-PaginatedSelection, Read-MaskedInput, Read-ValidatedInput, Invoke-NestedMenu
