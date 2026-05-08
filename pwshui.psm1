function Measure-FuzzyMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SearchTerm,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$TargetText
    )

    $inputNorm  = ($SearchTerm -replace '[^\w\s]', '' -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($inputNorm)) { return 0 }
    
    $targetNorm = ($TargetText -replace '[^\w\s]', '' -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($targetNorm)) { return 0 }

    if ($targetNorm -eq $inputNorm) { return 1000 }

    $inputWords = $inputNorm -split ' ' | Where-Object { $_.Length -gt 2 }
    $score = 0
    $matchedWords = 0

    if ($inputWords.Count -gt 0) {
        foreach ($word in $inputWords) {
            $wordMatched = $false

            if ($targetNorm -match [regex]::Escape($word)) {
                $wordMatched = $true
            } elseif ($word -match 's$') {
                if ($targetNorm -match [regex]::Escape($word.TrimEnd('s'))) { $wordMatched = $true }
            } else {
                if ($targetNorm -match [regex]::Escape($word + 's')) { $wordMatched = $true }
            }

            if (-not $wordMatched -and $word -match 'ies$') {
                if ($targetNorm -match [regex]::Escape(($word -replace 'ies$', 'y'))) { $wordMatched = $true }
            } elseif (-not $wordMatched -and $word -match 'y$') {
                if ($targetNorm -match [regex]::Escape(($word -replace 'y$', 'ies'))) { $wordMatched = $true }
            }

            if ($wordMatched) { $score += 10; $matchedWords++ }
        }
    } else {
        # Fallback for short search terms
        if ($targetNorm -match [regex]::Escape($inputNorm)) { $score += 10 }
    }

    $targetContainsInput  = $targetNorm  -match [regex]::Escape($inputNorm)
    $inputContainsTarget  = $inputNorm -match [regex]::Escape($targetNorm)

    if ($targetContainsInput -or $inputContainsTarget) { $score += 50 }

    if ($inputWords.Count -ge 3 -and $matchedWords -eq $inputWords.Count -and $targetContainsInput -and $inputContainsTarget) {
        $score += 30
    } elseif ($inputWords.Count -eq 2 -and $matchedWords -eq $inputWords.Count -and $targetContainsInput -and $inputContainsTarget) {
        $score += 20
    }

    return $score
}

function Write-UIBox {
    [CmdletBinding()]
    param(
        [string[]]$Header,
        [Parameter(Mandatory = $true)]
        [string[]]$Body,
        [string[]]$Footer,
        [switch]$Border,
        [int]$MinWidth = 0,
        [int]$MaxWidth = 0,
        [int]$X = -1,
        [int]$Y = -1,
        [switch]$AltScreen
    )

    # ANSI Strip regex to calculate true visible length
    $ansiRegex = "\e\[[0-9;]*[a-zA-Z]"
    
    function Get-VisibleLength ([string]$s) {
        if ([string]::IsNullOrEmpty($s)) { return 0 }
        return ($s -replace $ansiRegex, "").Length
    }

    $allLines = @()
    if ($Header) { $allLines += $Header }
    $allLines += $Body
    if ($Footer) { $allLines += $Footer }

    # Calculate required width
    $maxContentLen = $MinWidth
    foreach ($line in $allLines) {
        $len = Get-VisibleLength $line
        if ($len -gt $maxContentLen) { $maxContentLen = $len }
    }

    $winWidth = 80
    try { if ([Console]::WindowWidth -gt 0) { $winWidth = [Console]::WindowWidth } } catch {}
    
    $limit = ($MaxWidth -gt 0) ? [Math]::Min($MaxWidth, $winWidth) : $winWidth
    $borderOffset = $Border ? 4 : 0
    $innerBoxWidth = [Math]::Min($maxContentLen, $limit - $borderOffset)
    if ($innerBoxWidth -lt 0) { $innerBoxWidth = 0 }
    
    $outerBoxWidth = $innerBoxWidth + $borderOffset

    # Build the final frame lines in an array first to avoid scope/logic errors
    $frame = [System.Collections.Generic.List[string]]::new()
    $horiz = "─" * ($innerBoxWidth + 2)

    if ($Border) { $frame.Add("┌$horiz┐") }

    $addSectionLines = {
        param([string[]]$sectionLines)
        foreach ($line in $sectionLines) {
            $visibleLen = Get-VisibleLength $line
            $displayText = $line
            if ($visibleLen -gt $innerBoxWidth) {
                if ($line -match $ansiRegex) { $displayText = $line } 
                else { $displayText = $line.Substring(0, $innerBoxWidth - 3) + "..." }
                $visibleLen = $innerBoxWidth
            }
            $padding = " " * ($innerBoxWidth - $visibleLen)
            if ($Border) { $frame.Add("│ $displayText$padding │") }
            else { $frame.Add("$displayText$padding") }
        }
    }

    if ($Header) {
        & $addSectionLines $Header
        if ($Border -and ($Body -or $Footer)) { $frame.Add("├$horiz┤") }
    }

    & $addSectionLines $Body

    if ($Footer) {
        if ($Border) { $frame.Add("├$horiz┤") }
        & $addSectionLines $Footer
    }

    if ($Border) { $frame.Add("└$horiz┘") }

    # Render the frame
    $currentY = $Y
    foreach ($line in $frame) {
        if ($X -ge 0) {
            if ($currentY -ge 0) {
                Write-Host "`e[$($currentY);$($X)H" -NoNewline
                $currentY++
            } else {
                Write-Host "`e[$($X)G" -NoNewline
            }
        }
        Write-Host "$line`e[K"
    }

    return $frame.Count
}

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

        [switch]$NoColor,

        [Parameter(Position = 4)]
        [int]$InitialIndex = 0,

        [switch]$Border,
        [int]$MinWidth = 0,
        [int]$MaxWidth = 0,
        [int]$X = -1,
        [int]$Y = -1,
        [switch]$AltScreen,
        [switch]$Searchable
    )

    $itemList = @($Items)
    if ($itemList.Count -eq 0) {
        Write-Warning "No items to select."
        return $null
    }

    # Internal state for tracking filtered items
    $filteredItems = $itemList
    $searchBuffer = ""

    # Ensure InitialIndex is within bounds
    if ($InitialIndex -ge $itemList.Count) { $InitialIndex = $itemList.Count - 1 }
    if ($InitialIndex -lt 0) { $InitialIndex = 0 }

    $pageIndex = [int][Math]::Floor($InitialIndex / $PageSize)
    $selectedIndex = [int]($InitialIndex % $PageSize)
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
    if ($AltScreen) { Write-Host "`e[?1049h" -NoNewline }

    try {
        $firstRender = $true
        $lastHeight = 0

        while ($running) {
            # Recalculate pagination bounds if list changed
            $pageCount = [Math]::Max(1, [Math]::Ceiling($filteredItems.Count / $PageSize))
            if ($pageIndex -ge $pageCount) { $pageIndex = [Math]::Max(0, $pageCount - 1) }

            # Calculate current page items
            $startIdx = $pageIndex * $PageSize
            $currentPageItems = @($filteredItems | Select-Object -Skip $startIdx -First $PageSize)
            
            # Ensure selected index is valid for current page
            if ($selectedIndex -ge $currentPageItems.Count) {
                $selectedIndex = [Math]::Max(0, $currentPageItems.Count - 1)
            }

            if (-not $firstRender -and $X -lt 0 -and $Y -lt 0) {
                # ANSI to move cursor up before drawing if not using absolute positioning
                Write-Host "`e[$($lastHeight)A" -NoNewline
            } elseif ($firstRender -and ($X -lt 0 -and $Y -lt 0)) {
                Write-Host "" # Initial newline for relative positioning
            }
            $firstRender = $false

            # Build Sections for UIBox
            $displayTitle = if ($Searchable) {
                if ($searchBuffer) { "$Title [Search: $searchBuffer]" } else { "$Title [Type to search]" }
            } else {
                $Title
            }

            $header = @($displayTitle, ("-" * $displayTitle.Length))
            
            $body = @()
            if ($currentPageItems.Count -gt 0) {
                for ($i = 0; $i -lt $currentPageItems.Count; $i++) {
                    $item = $currentPageItems[$i]
                    $displayText = ""
                    if ($DisplayProperty) { $displayText = $item.$DisplayProperty }
                    else { $displayText = $item.ToString() }
                    if ([string]::IsNullOrWhiteSpace($displayText)) { $displayText = $item.ToString() }
                    
                    $isRowSelected = ($i -eq $selectedIndex)
                    if ($isRowSelected) {
                        if ($NoColor) {
                            $body += "$pointer$displayText"
                        } else {
                            $body += "`e[36m$pointer`e[46;30m$displayText`e[0m"
                        }
                    } else {
                        $body += "$emptyPointer$displayText"
                    }
                }
            } else {
                $body += "  (No matches found)"
            }

            $pageNumDisplay = "($($pageIndex + 1)/$pageCount)"
            $endIdx = [Math]::Min($startIdx + $PageSize, $filteredItems.Count)
            $startDisplay = if ($filteredItems.Count -gt 0) { $startIdx + 1 } else { 0 }
            $rangeDisplay = "($startDisplay-$endIdx of $($filteredItems.Count))"
            
            $footerLines = [System.Collections.Generic.List[string]]::new()
            $footerLines.Add("← Prev page $pageNumDisplay   → Next page $pageNumDisplay")
            $footerLines.Add("↑↓ Move $rangeDisplay   Enter Select    Esc Cancel")
            if ($Searchable) {
                $footerLines.Add("Type to search   Backspace to delete")
            }

            $footer = @($footerLines)

            # Draw using UIBox
            $newHeight = Write-UIBox -Header $header -Body $body -Footer $footer `
                                      -Border:$Border -MinWidth $MinWidth -MaxWidth $MaxWidth -X $X -Y $Y

            # If the box shrunk, clear the leftover lines below it
            if ($newHeight -lt $lastHeight -and $X -lt 0 -and $Y -lt 0) {
                $diff = $lastHeight - $newHeight
                for ($h = 0; $h -lt $diff; $h++) {
                    Write-Host "`e[K" # Clear line and move down
                }
                Write-Host "`e[$($diff)A" -NoNewline # Move back up to bottom of new box
            }
            $lastHeight = $newHeight

            # Key Input
            $key = [Console]::ReadKey($true)

            if ($Searchable) {
                $handledSearchKey = $false
                if ($key.Key -eq 'Backspace') {
                    if ($searchBuffer.Length -gt 0) {
                        $searchBuffer = $searchBuffer.Substring(0, $searchBuffer.Length - 1)
                        $handledSearchKey = $true
                    }
                } elseif ([char]::IsLetterOrDigit($key.KeyChar) -or [char]::IsPunctuation($key.KeyChar) -or $key.KeyChar -eq ' ') {
                    $searchBuffer += $key.KeyChar
                    $handledSearchKey = $true
                }

                if ($handledSearchKey) {
                    if ([string]::IsNullOrEmpty($searchBuffer)) {
                        $filteredItems = $itemList
                    } else {
                        $scoredItems = @()
                        foreach ($item in $itemList) {
                            $itemName = if ($DisplayProperty) { $item.$DisplayProperty } else { $item.ToString() }
                            $score = Measure-FuzzyMatch -SearchTerm $searchBuffer -TargetText $itemName
                            if ($score -ge 10) { # Threshold for partial typing
                                $scoredItems += [PSCustomObject]@{ Item = $item; Score = $score }
                            }
                        }
                        $filteredItems = @($scoredItems | Sort-Object Score -Descending | Select-Object -ExpandProperty Item)
                    }
                    $pageIndex = 0
                    $selectedIndex = 0
                    continue # Skip standard navigation key checks
                }
            }

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
                    if ($filteredItems.Count -gt 0) {
                        $result = $filteredItems[$startIdx + $selectedIndex]
                    }
                    $running = $false
                }
                'Escape' {
                    $result = $null
                    $running = $false
                }
            }
        }
    } finally {
        # Restore cursor to its original state
        if ($originalCursorVisible) {
            Write-Host "`e[?25h" -NoNewline
        }
        if ($AltScreen) { Write-Host "`e[?1049l" -NoNewline }

        # ANSI to move cursor up before clearing on exit if we rendered at least once
        if (-not $firstRender -and $X -lt 0 -and $Y -lt 0) {
            Write-Host "`e[$($lastHeight)A" -NoNewline
        }

        # Clear the menu area
        Write-Host "`e[J" -NoNewline

        # Restore cursor to its original state
        if ($originalCursorVisible) {
            Write-Host "`e[?25h" -NoNewline
        }
        if ($AltScreen) { Write-Host "`e[?1049l" -NoNewline }

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
    if ($AltScreen) { Write-Host "`e[?1049h" -NoNewline }

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
                    $charToPrint = ""
                    if ($slotIdx -lt $rawInput.Count) { $charToPrint = $rawInput[$slotIdx] }
                    else { $charToPrint = $Placeholder }
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
        if ($AltScreen) { Write-Host "`e[?1049l" -NoNewline }
        
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
    if ($AltScreen) { Write-Host "`e[?1049h" -NoNewline }

    try {
        while ($running) {
            $currentStr = -join $rawInput
            $isValid = ($currentStr -match $Pattern)
            if ($AllowEmpty -and $currentStr.Length -eq 0) { $isValid = $true }

            # Render Prompt
            Write-Host "`r$Prompt " -NoNewline -ForegroundColor Cyan
            
            # Draw Input String
            $useColor = ($currentStr.Length -gt 0)
            $color = "Red"
            if ($isValid) { $color = "Green" }
            
            for ($i = 0; $i -le $currentStr.Length; $i++) {
                if ($i -eq $cursor) {
                    $charToDraw = " "
                    if ($i -lt $currentStr.Length) { $charToDraw = $currentStr[$i] }
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
        if ($AltScreen) { Write-Host "`e[?1049l" -NoNewline }

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
        [string]$Title = "Main Menu",

        [Parameter(Position = 2)]
        [array]$InitialPath,

        [switch]$Border,
        [int]$MinWidth = 0,
        [int]$MaxWidth = 0,
        [int]$X = -1,
        [int]$Y = -1,
        [switch]$AltScreen
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

    # Process InitialPath if provided
    if ($null -ne $InitialPath -and $InitialPath.Count -gt 0) {
        for ($s = 0; $s -lt $InitialPath.Count; $s++) {
            $segment = $InitialPath[$s]
            $currentLayer = $history[$history.Count - 1]
            $items = $currentLayer.Items
            $foundIdx = -1

            if ($segment -is [int]) {
                if ($segment -ge 0 -and $segment -lt $items.Count) {
                    $foundIdx = $segment
                }
            } else {
                for ($i = 0; $i -lt $items.Count; $i++) {
                    if ($items[$i].Label -eq $segment -or $items[$i].Value -eq $segment) {
                        $foundIdx = $i
                        break
                    }
                }
            }

            if ($foundIdx -ne -1) {
                $currentLayer.SelectedIndex = $foundIdx
                $selected = $items[$foundIdx]
                # Only drill down if there are more segments in the path and the item has children
                if ($s -lt ($InitialPath.Count - 1) -and $null -ne $selected.Children -and $selected.Children.Count -gt 0) {
                    $history.Add([PSCustomObject]@{ Title = $selected.Label; Items = $selected.Children; SelectedIndex = 0 })
                } else {
                    break 
                }
            } else {
                break # Segment not found
            }
        }
    }

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
    if ($AltScreen) { Write-Host "`e[?1049h" -NoNewline }

    try {
        if ($X -lt 0 -and $Y -lt 0) { Write-Host "" } # Initial newline
        $firstRender = $true
        $lastHeight = 0
        
        while ($running) {
            $currentMenu = $history[$history.Count - 1]
            $currentItems = $currentMenu.Items
            $selectedIndex = $currentMenu.SelectedIndex

            if (-not $firstRender -and $X -lt 0 -and $Y -lt 0) {
                Write-Host "`e[$($lastHeight)A" -NoNewline
            }
            $firstRender = $false

            # Header
            $breadcrumb = ($history | ForEach-Object Title) -join " > "
            $header = @($breadcrumb, ("-" * $breadcrumb.Length))

            # Body
            $pointer = "> "
            $emptyPointer = "  "
            $body = @()
            
            for ($i = 0; $i -lt $currentItems.Count; $i++) {
                $item = $currentItems[$i]
                $isRowSelected = ($i -eq $selectedIndex)
                $displayNum = $i + 1
                
                $suffix = if ($null -ne $item.Children -and $item.Children.Count -gt 0) { " ►" } else { "" }
                $displayText = "[$displayNum] $($item.Label)$suffix"

                if ($isRowSelected) {
                    $body += "`e[36m$pointer`e[46;30m$displayText`e[0m"
                } else {
                    $body += "$emptyPointer$displayText"
                }
            }
            
            # Footer
            $footer = @("↑↓ or 1-$($currentItems.Count): Move   →: Expand   ←: Back   Enter: Select   Esc: Exit")

            # Draw using UIBox
            $newHeight = Write-UIBox -Header $header -Body $body -Footer $footer `
                                      -Border:$Border -MinWidth $MinWidth -MaxWidth $MaxWidth -X $X -Y $Y

            # If the box shrunk, clear the leftover lines below it
            if ($newHeight -lt $lastHeight -and $X -lt 0 -and $Y -lt 0) {
                $diff = $lastHeight - $newHeight
                for ($h = 0; $h -lt $diff; $h++) {
                    Write-Host "`e[K" # Clear line and move down
                }
                Write-Host "`e[$($diff)A" -NoNewline # Move back up to bottom of new box
            }
            $lastHeight = $newHeight

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
                        if ($X -lt 0 -and $Y -lt 0) { Write-Host "`e[$($lastHeight)A`e[J" -NoNewline }
                        $firstRender = $true
                    }
                } elseif ($key.Key -eq 'Escape') {
                    if ($history.Count -gt 1) {
                        $history.RemoveAt($history.Count - 1)
                        if ($X -lt 0 -and $Y -lt 0) { Write-Host "`e[$($lastHeight)A`e[J" -NoNewline }
                        $firstRender = $true
                    } else {
                        $running = $false
                        $result = $null
                    }
                } elseif ($key.Key -eq 'RightArrow') {
                    $selectedItem = $currentItems[$selectedIndex]
                    if ($null -ne $selectedItem.Children -and $selectedItem.Children.Count -gt 0) {
                        $history.Add([PSCustomObject]@{ Title = $selectedItem.Label; Items = $selectedItem.Children; SelectedIndex = 0 })
                        if ($X -lt 0 -and $Y -lt 0) { Write-Host "`e[$($lastHeight)A`e[J" -NoNewline }
                        $firstRender = $true
                    }
                } elseif ($key.Key -eq 'Enter') {
                    $selectedItem = $currentItems[$selectedIndex]
                    if ($null -ne $selectedItem.Children -and $selectedItem.Children.Count -gt 0) {
                        $history.Add([PSCustomObject]@{ Title = $selectedItem.Label; Items = $selectedItem.Children; SelectedIndex = 0 })
                        if ($X -lt 0 -and $Y -lt 0) { Write-Host "`e[$($lastHeight)A`e[J" -NoNewline }
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
        if (-not $firstRender -and $X -lt 0 -and $Y -lt 0) {
            Write-Host "`e[$($lastHeight)A" -NoNewline
        }

        # Clear the entire menu area from the screen on exit
        Write-Host "`e[J" -NoNewline
        
        # Restore cursor
        if ($originalCursorVisible) {
            Write-Host "`e[?25h" -NoNewline
        }
        if ($AltScreen) { Write-Host "`e[?1049l" -NoNewline }

        # Clean line on abort
        if ($null -eq $result) {
            Write-Host ""
        }
    }

    return $result
}

Export-ModuleMember -Function Write-UIBox, Get-PaginatedSelection, Read-MaskedInput, Read-ValidatedInput, Invoke-NestedMenu, Measure-FuzzyMatch
