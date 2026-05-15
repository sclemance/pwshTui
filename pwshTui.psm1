Set-StrictMode -Version Latest

# Cached once at module load. Drives module-wide rendering decisions:
# interactive prompts fail fast with a clear error in non-VT hosts (Azure
# Automation, ISE, redirected output) where [Console]::ReadKey can't work;
# Show-Spinner falls back to plain bracketed log lines. Capability is per-
# host and doesn't change after the module is imported, so caching is safe.
$script:_SupportsVT = $false
try { $script:_SupportsVT = [bool]$Host.UI.SupportsVirtualTerminal } catch {}

function Assert-InteractiveHost {
    param([string]$FunctionName)
    if (-not $script:_SupportsVT) {
        throw "$FunctionName requires a host with virtual-terminal support. Current host '$($Host.Name)' does not — likely Azure Automation, Windows PowerShell ISE, or redirected output. Run from an interactive console session (pwsh, Windows Terminal, VS Code integrated terminal, etc.)."
    }
}

function Measure-FuzzyMatch {
    <#
    .SYNOPSIS
        Score how well a search term matches a target string (0-1000).
    .DESCRIPTION
        Returns an integer relevance score using an intent-biased ensemble of
        Subsequence (fzf-style) and Jaro-Winkler algorithms.

        Score bands:
          1000 = exact match
           900 = prefix match
           800 = substring match
          1-700 = ranked partial match (algorithm-dependent)
             0 = no match

        Normalization converts structural separators (- _ . / : \) and
        camelCase/PascalCase boundaries into spaces so word structure is
        uniformly visible to all algorithms. Fast paths additionally check a
        compact (space-removed) form so identifier-style queries still hit
        prefix/substring shortcuts.
    .PARAMETER SearchTerm
        The string the user is searching for.
    .PARAMETER TargetText
        The string being evaluated.
    .PARAMETER Algorithm
        Auto (default): intent-biased max of Subsequence + Jaro-Winkler.
        Subsequence: fzf-style ordered character match with word-boundary bonus.
        JaroWinkler: similarity + prefix boost; good for typos/transpositions.
        Legacy: word-based with morphological variants (plural/singular).
    .EXAMPLE
        PS> Measure-FuzzyMatch -SearchTerm "srever" -TargetText "server"
        665

        Transposition typo: JW recognizes high similarity, Auto preserves it.
    .EXAMPLE
        PS> Measure-FuzzyMatch -SearchTerm "fzmgr" -TargetText "fuzzy match manager"
        496

        Vowel-sparse abbreviation: intent detector tilts toward Subsequence.
    .OUTPUTS
        [int] in [0, 1000].
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SearchTerm,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$TargetText,

        [Parameter(Position = 2)]
        [ValidateSet('Auto', 'Subsequence', 'JaroWinkler', 'Legacy')]
        [string]$Algorithm = 'Auto'
    )

    if ([string]::IsNullOrWhiteSpace($SearchTerm) -or [string]::IsNullOrWhiteSpace($TargetText)) {
        return 0
    }

    # Normalize: split structural separators (-_./:\) and camelCase/PascalCase
    # boundaries into spaces so word structure is uniformly visible to all
    # algorithms, then lowercase. -creplace is case-sensitive (required for the
    # camelCase patterns; PS's default -replace is case-insensitive).
    $sNorm = ($SearchTerm `
        -creplace '(?<=[a-z0-9])(?=[A-Z])', ' ' `
        -creplace '(?<=[A-Z])(?=[A-Z][a-z])', ' ' `
        -replace '[-_./:\\]+', ' ' `
        -replace '[^\w\s]', '' `
        -replace '\s+', ' ').Trim().ToLowerInvariant()
    $tNorm = ($TargetText `
        -creplace '(?<=[a-z0-9])(?=[A-Z])', ' ' `
        -creplace '(?<=[A-Z])(?=[A-Z][a-z])', ' ' `
        -replace '[-_./:\\]+', ' ' `
        -replace '[^\w\s]', '' `
        -replace '\s+', ' ').Trim().ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($sNorm)) { return 0 }

    # Compact form (spaces removed) so users who type identifiers without
    # separators (e.g. "myserver" for "my-server-01") still hit the fast paths.
    $sCompact = $sNorm -replace ' ', ''
    $tCompact = $tNorm -replace ' ', ''

    # --- Legacy Fallback ---
    if ($Algorithm -eq 'Legacy') {
        if ($tNorm -eq $sNorm) { return 1000 }

        $inputWords = @($sNorm -split ' ' | Where-Object { $_.Length -gt 2 })
        $score = 0
        $matchedWords = 0

        if ($inputWords.Count -gt 0) {
            foreach ($word in $inputWords) {
                $wordMatched = $false
                if ($tNorm -match [regex]::Escape($word)) { $wordMatched = $true }
                elseif ($word -match 's$') { if ($tNorm -match [regex]::Escape($word.TrimEnd('s'))) { $wordMatched = $true } }
                else { if ($tNorm -match [regex]::Escape($word + 's')) { $wordMatched = $true } }

                if (-not $wordMatched -and $word -match 'ies$') { if ($tNorm -match [regex]::Escape(($word -replace 'ies$', 'y'))) { $wordMatched = $true } }
                elseif (-not $wordMatched -and $word -match 'y$') { if ($tNorm -match [regex]::Escape(($word -replace 'y$', 'ies'))) { $wordMatched = $true } }

                if ($wordMatched) { $score += 10; $matchedWords++ }
            }
        } else {
            if ($tNorm -match [regex]::Escape($sNorm)) { $score += 10 }
        }

        $targetContainsInput  = $tNorm -match [regex]::Escape($sNorm)
        $inputContainsTarget  = $sNorm -match [regex]::Escape($tNorm)

        if ($targetContainsInput -or $inputContainsTarget) { $score += 50 }

        if ($inputWords.Count -ge 3 -and $matchedWords -eq $inputWords.Count -and $targetContainsInput -and $inputContainsTarget) { $score += 30 }
        elseif ($inputWords.Count -eq 2 -and $matchedWords -eq $inputWords.Count -and $targetContainsInput -and $inputContainsTarget) { $score += 20 }

        return $score
    }

    # --- Fast Paths (Common for Auto, Subsequence, JaroWinkler) ---
    # Check both spaced and compact forms so identifier-style queries don't
    # regress when normalization preserves separators as spaces.
    if ($tNorm -eq $sNorm -or $tCompact -eq $sCompact) { return 1000 }
    if ($tNorm.StartsWith($sNorm) -or $tCompact.StartsWith($sCompact)) { return 900 }
    if ($tNorm.Contains($sNorm) -or $tCompact.Contains($sCompact)) { return 800 }

    $subseqScore = 0
    $jwScore = 0

    # --- Subsequence Logic (fzf-style) ---
    if ($Algorithm -in 'Auto', 'Subsequence') {
        $sIdx = 0
        $tIdx = 0
        $consecutive = 0

        while ($sIdx -lt $sNorm.Length -and $tIdx -lt $tNorm.Length) {
            if ($sNorm[$sIdx] -eq $tNorm[$tIdx]) {
                $subseqScore += 10
                if ($consecutive -gt 0) { $subseqScore += ($consecutive * 5) }

                # Word boundary bonus (normalization converts all structural
                # separators to spaces, so a space is the only boundary marker).
                if ($tIdx -eq 0) {
                    $subseqScore += 20
                } elseif ($tNorm[$tIdx - 1] -eq ' ') {
                    $subseqScore += 15
                }

                $consecutive++
                $sIdx++
            } else {
                $consecutive = 0
            }
            $tIdx++
        }
        # Zero score if not all characters matched in order
        if ($sIdx -lt $sNorm.Length) {
            $subseqScore = 0
        } elseif ($subseqScore -gt 0) {
            # Normalize to 0-700 range: max score = 30 + 10*(n-1) + 5*(n-1)*n/2
            # (perfect consecutive match starting at position 0 with word-boundary bonus)
            $n = $sNorm.Length
            $maxSubseqScore = 30 + 10 * ($n - 1) + [int](5 * ($n - 1) * $n / 2)
            $subseqScore = [int](($subseqScore / $maxSubseqScore) * 700)
        }
    }

    # --- Jaro-Winkler Logic ---
    if ($Algorithm -in 'Auto', 'JaroWinkler') {
        $len1 = $sNorm.Length
        $len2 = $tNorm.Length

        if ($len1 -gt 0 -and $len2 -gt 0) {
            $matchWindow = [Math]::Max(0, [int][Math]::Floor([Math]::Max($len1, $len2) / 2.0) - 1)
            $s1Matches = [bool[]]::new($len1)
            $s2Matches = [bool[]]::new($len2)
            $matchCount = 0

            for ($i = 0; $i -lt $len1; $i++) {
                $start = [Math]::Max(0, $i - $matchWindow)
                $end = [Math]::Min($i + $matchWindow + 1, $len2)
                for ($j = $start; $j -lt $end; $j++) {
                    if ($s2Matches[$j]) { continue }
                    if ($sNorm[$i] -ne $tNorm[$j]) { continue }
                    $s1Matches[$i] = $true
                    $s2Matches[$j] = $true
                    $matchCount++
                    break
                }
            }

            if ($matchCount -gt 0) {
                # Count transpositions (matched chars out of order, halved)
                $transpositions = 0
                $k = 0
                for ($i = 0; $i -lt $len1; $i++) {
                    if (-not $s1Matches[$i]) { continue }
                    while (-not $s2Matches[$k]) { $k++ }
                    if ($sNorm[$i] -ne $tNorm[$k]) { $transpositions++ }
                    $k++
                }
                $transpositions = $transpositions / 2.0

                $jaro = (($matchCount / [double]$len1) + ($matchCount / [double]$len2) + (($matchCount - $transpositions) / $matchCount)) / 3.0

                # Winkler prefix boost: up to 4 chars, p = 0.1
                $prefix = 0
                $maxPrefix = [Math]::Min(4, [Math]::Min($len1, $len2))
                for ($i = 0; $i -lt $maxPrefix; $i++) {
                    if ($sNorm[$i] -eq $tNorm[$i]) { $prefix++ } else { break }
                }

                $jw = $jaro + ($prefix * 0.1 * (1.0 - $jaro))
                $jwScore = [int]([Math]::Max(0.0, [Math]::Min(1.0, $jw)) * 700)
            }
        }
    }

    if ($Algorithm -eq 'Subsequence') { return $subseqScore }
    if ($Algorithm -eq 'JaroWinkler') { return $jwScore }

    # --- Auto: intent-biased Max of JW and Subsequence ---
    # Detect signals about user intent (typing the target vs. abbreviating) and tilt
    # the contest toward the algorithm best suited to that intent. We bias the
    # *loser's* score down rather than averaging — Math.Max means the winning signal
    # always survives intact, so a strong typo recognition isn't diluted by a 0
    # subsequence score (and vice versa).
    $intent = 0.0

    # Signal 1: length ratio. r>=0.7 ~ user is typing the target (typo intent);
    # r<=0.3 ~ user is abbreviating sparsely (subsequence intent).
    $ratio = $sNorm.Length / [double]$tNorm.Length
    if ($ratio -ge 0.7) {
        $intent -= 0.5
    } elseif ($ratio -le 0.3) {
        $intent += 0.5
    }

    # Signal 2: vowel sparseness in the search term. Strong abbreviation marker
    # (e.g. cfg, pwsh, mgr). Skipped on very short inputs where the signal is noisy.
    if ($sNorm.Length -ge 3) {
        $vowelCount = ($sNorm -replace '[^aeiou]', '').Length
        if (($vowelCount / [double]$sNorm.Length) -lt 0.2) {
            $intent += 0.3
        }
    }

    $intent = [Math]::Max(-1.0, [Math]::Min(1.0, $intent))

    # Apply bias: positive intent (abbreviation) penalizes JW; negative penalizes Sub.
    # Max keeps the recognized signal intact; bias just tilts ties and ambiguity.
    $jwBias  = 1.0 - [Math]::Max(0.0, $intent) * 0.3
    $subBias = 1.0 + [Math]::Min(0.0, $intent) * 0.3
    return [int][Math]::Max($jwScore * $jwBias, $subseqScore * $subBias)
}

# --- Internal helpers used by Write-UIBox ---
# Module-private (not exported). Hoisted out of Write-UIBox so they're defined
# once at module load instead of re-created on every render call.

$script:_AnsiRegex = "\e\[[0-9;]*[a-zA-Z]"

function Get-VisibleLength ([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return 0 }
    return ($s -replace $script:_AnsiRegex, "").Length
}

# Truncate to N visible characters while preserving ANSI escape sequences inline.
# ANSI sequences don't count toward the visible width but are emitted as-is so
# inline styling survives the truncation.
function Get-VisibleSubstring ([string]$s, [int]$maxVisibleLen) {
    if ($maxVisibleLen -le 0 -or [string]::IsNullOrEmpty($s)) { return "" }
    $sb = [System.Text.StringBuilder]::new()
    $visibleCount = 0
    $i = 0
    while ($i -lt $s.Length -and $visibleCount -lt $maxVisibleLen) {
        if ($s[$i] -eq [char]27 -and ($i + 1) -lt $s.Length -and $s[$i + 1] -eq '[') {
            # Copy the full CSI sequence: ESC [ <params> <final-byte>
            $start = $i
            $i += 2
            while ($i -lt $s.Length -and ($s[$i] -match '[0-9;]')) { $i++ }
            if ($i -lt $s.Length -and [char]::IsLetter($s[$i])) { $i++ }
            [void]$sb.Append($s.Substring($start, $i - $start))
        } else {
            [void]$sb.Append($s[$i])
            $visibleCount++
            $i++
        }
    }
    return $sb.ToString()
}

function Write-UIBox {
    <#
    .SYNOPSIS
        Render a header/body/footer text block with optional Unicode border.
    .DESCRIPTION
        Composes text into a renderable frame with automatic width calculation,
        ANSI-aware truncation (lines that exceed the inner width are truncated
        on visible characters while preserving inline ANSI escape sequences),
        and either absolute or relative positioning. Returns the line count of
        the rendered frame so callers can manage redraws.
    .PARAMETER Header
        Lines drawn above the body. Separated from body by a rule if Border.
    .PARAMETER Body
        Required. The main content lines.
    .PARAMETER Footer
        Lines drawn below the body. Separated from body by a rule if Border.
    .PARAMETER Border
        Wrap the content in a Unicode box.
    .PARAMETER MinWidth
        Lower bound for inner content width. 0 = no minimum.
    .PARAMETER MaxWidth
        Upper bound for outer width. 0 = use terminal width.
    .PARAMETER X
        Absolute column to render at. -1 = current cursor position.
    .PARAMETER Y
        Absolute row to render at. -1 = current cursor position.
    .PARAMETER AltScreen
        Reserved; the caller controls alt-screen mode.
    .OUTPUTS
        [int] number of lines rendered.
    #>
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
                # Truncate visible content to leave room for "..." then reset
                # any open ANSI styling so the box border / padding renders clean.
                $truncated = Get-VisibleSubstring $line ($innerBoxWidth - 3)
                $displayText = "$truncated...`e[0m"
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
    <#
    .SYNOPSIS
        Interactive paginated list selector with optional live fuzzy search
        and multi-select.
    .DESCRIPTION
        Renders a paginated list and returns the selected item, or $null on
        cancel. Supports keyboard navigation, page/selection wrap, an initial
        highlighted index, and (with -Searchable) live fuzzy-search filtering
        powered by Measure-FuzzyMatch. With -MultiSelect, Space toggles rows
        and Enter returns an array of toggled items.

        Keys: Up/Down move within page, Left/Right change page, Enter selects,
        Esc cancels. In Searchable mode any printable character extends the
        search buffer; Backspace deletes from it. In MultiSelect mode Space
        toggles the current row's selection (preempting buffer extension if
        Searchable is also on).
    .PARAMETER Items
        Required. Collection to choose from (strings or objects).
    .PARAMETER PageSize
        Items per page. Default 10.
    .PARAMETER Title
        Header text shown above the list.
    .PARAMETER DisplayProperty
        For object inputs, which property to display (and search against).
    .PARAMETER Wrap
        Enable selection and page wrap at boundaries.
    .PARAMETER NoColor
        Disable ANSI styling on the selected row.
    .PARAMETER InitialIndex
        0-based index of the item to highlight on open.
    .PARAMETER Searchable
        Enable live fuzzy-search filtering on keystrokes.
    .PARAMETER SearchAlgorithm
        Fuzzy algorithm to use. See Measure-FuzzyMatch for details.
    .PARAMETER SearchThreshold
        Minimum match score (0-1000) for an item to appear when searching.
        Default 100. Lower = more permissive.
    .PARAMETER MultiSelect
        Enable multi-selection. Space toggles the current row's selection
        (independent of cursor position); Enter returns an array of selected
        items in original input order. Selection state persists across search
        filter changes. Esc still returns $null. Enter with no toggled items
        returns an empty array (distinguishable from $null cancel).
    .OUTPUTS
        Without -MultiSelect: the selected item, or $null if cancelled.
        With -MultiSelect: an array (possibly empty) of selected items in
        original input order, or $null if cancelled.
    #>
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
        [switch]$Searchable,

        [Parameter()]
        [ValidateSet('Auto', 'Subsequence', 'JaroWinkler', 'Legacy')]
        [string]$SearchAlgorithm = 'Auto',

        # Minimum Measure-FuzzyMatch score for an item to appear in filtered
        # results. Scores 0-1000; 100 hides obvious noise while keeping fuzzy
        # partial matches visible. Set lower to be more permissive.
        [int]$SearchThreshold = 100,

        [switch]$MultiSelect
    )

    Assert-InteractiveHost 'Get-PaginatedSelection'

    $itemList = @($Items)
    if ($itemList.Count -eq 0) {
        Write-Warning "No items to select."
        return $null
    }

    # Internal state for tracking filtered items
    $filteredItems = $itemList
    $searchBuffer = ""
    $previousSearchBuffer = ""

    # MultiSelect: HashSet keyed by item identity (reference equality for
    # objects, value equality for strings). Persists across filter changes
    # so a toggled item stays selected even when filtered off-screen.
    $selectedSet = [System.Collections.Generic.HashSet[object]]::new()

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

                    if ($MultiSelect) {
                        $marker = if ($selectedSet.Contains($item)) { '[x] ' } else { '[ ] ' }
                        $displayText = "$marker$displayText"
                    }

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
            if ($MultiSelect) {
                $footerLines.Add("↑↓ Move $rangeDisplay   Space Toggle ($($selectedSet.Count) selected)   Enter Confirm   Esc Cancel")
            } else {
                $footerLines.Add("↑↓ Move $rangeDisplay   Enter Select    Esc Cancel")
            }
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

            if ($MultiSelect -and $key.Key -eq 'Spacebar') {
                if ($currentPageItems.Count -gt 0) {
                    $toggleItem = $currentPageItems[$selectedIndex]
                    if ($selectedSet.Contains($toggleItem)) {
                        [void]$selectedSet.Remove($toggleItem)
                    } else {
                        [void]$selectedSet.Add($toggleItem)
                    }
                }
                continue
            }

            if ($Searchable) {
                $handledSearchKey = $false
                if ($key.Key -eq 'Backspace') {
                    if ($searchBuffer.Length -gt 0) {
                        $searchBuffer = $searchBuffer.Substring(0, $searchBuffer.Length - 1)
                        $handledSearchKey = $true
                    }
                } elseif ($key.KeyChar -ne [char]0 -and -not [char]::IsControl($key.KeyChar)) {
                    $searchBuffer += $key.KeyChar
                    $handledSearchKey = $true
                }

                if ($handledSearchKey) {
                    if ([string]::IsNullOrEmpty($searchBuffer)) {
                        $filteredItems = $itemList
                    } else {
                        # Incremental narrowing: if the new buffer extends the previous
                        # one, scoring the prior filtered set is sufficient (chars-in-order
                        # algorithms can only lose matches as the query grows). Backspace
                        # / replacement reverts to the full list.
                        $candidateSet = if ($previousSearchBuffer -and $searchBuffer.StartsWith($previousSearchBuffer)) {
                            $filteredItems
                        } else {
                            $itemList
                        }
                        $scoredItems = @()
                        foreach ($item in $candidateSet) {
                            $itemName = if ($DisplayProperty) { $item.$DisplayProperty } else { $item.ToString() }
                            $score = Measure-FuzzyMatch -SearchTerm $searchBuffer -TargetText $itemName -Algorithm $SearchAlgorithm
                            if ($score -ge $SearchThreshold) {
                                $scoredItems += [PSCustomObject]@{ Item = $item; Score = $score }
                            }
                        }
                        $filteredItems = @($scoredItems | Sort-Object Score -Descending | Select-Object -ExpandProperty Item)
                    }
                    $previousSearchBuffer = $searchBuffer
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
                    if ($MultiSelect) {
                        # Return selected items in original input order. Wrapped
                        # in a single-element array via the unary comma so that
                        # PowerShell preserves the array shape even when 0 or 1
                        # items are selected.
                        $result = ,@($itemList | Where-Object { $selectedSet.Contains($_) })
                    } elseif ($filteredItems.Count -gt 0) {
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
        # Move cursor back to top of the box (if rendered) before clearing
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
    <#
    .SYNOPSIS
        Prompt for input that conforms to a fixed-position mask.
    .DESCRIPTION
        Renders a mask template with slot placeholders and accepts only
        characters matching the slot type at the current position. Useful for
        serial numbers, license keys, MAC addresses, etc.

        Mask characters:
          # = digit (0-9)
          a = letter
          X = hex (auto-uppercased)
          x = hex (auto-lowercased)
          * = any non-control character
        Any other character is treated as a literal separator.
    .PARAMETER Mask
        Required. The mask string defining slots and separators.
    .PARAMETER Prompt
        Label shown before the masked field.
    .PARAMETER Placeholder
        Character displayed for empty slots. Default '_'.
    .PARAMETER AllowIncomplete
        Allow Enter to return even when not all slots are filled.
    .PARAMETER ReturnRaw
        Return only the entered characters (no separators or placeholders).
    .EXAMPLE
        PS> Read-MaskedInput -Mask 'XX:XX:XX:XX:XX:XX' -Prompt 'MAC:'
        Reads a MAC address with auto-uppercased hex.
    .OUTPUTS
        [string] formatted value, or $null if cancelled.
    #>
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

    Assert-InteractiveHost 'Read-MaskedInput'

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
    <#
    .SYNOPSIS
        Prompt for input that must match a regex pattern.
    .DESCRIPTION
        Renders the input with green/red coloring based on whether the current
        buffer matches the validation pattern. Enter is only accepted when the
        input is valid (or empty if -AllowEmpty was set).
    .PARAMETER Prompt
        Required. Label shown before the input field.
    .PARAMETER Pattern
        Required. Regex pattern the input must match to be accepted.
    .PARAMETER AllowEmpty
        Treat empty input as valid (returns "").
    .EXAMPLE
        PS> Read-ValidatedInput -Prompt 'Email:' -Pattern '^[^@]+@[^@]+\.[^@]+$'
        Reads an email address with live red/green feedback.
    .OUTPUTS
        [string] entered value, or $null if cancelled or empty (without -AllowEmpty).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Prompt,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Pattern,

        [switch]$AllowEmpty
    )

    Assert-InteractiveHost 'Read-ValidatedInput'

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

        # Ensure the terminal prompt drops to a clean line on exit
        Write-Host ""
    }

    if ($finalStr.Length -eq 0 -and -not $AllowEmpty) {
        return $null
    }

    return $finalStr
}

function Read-Confirmation {
    <#
    .SYNOPSIS
        Prompt for a yes/no answer with single-key or arrow-key input.
    .DESCRIPTION
        Renders the question with two buttons (Yes / No), one highlighted as
        the default. Accepts a single Y or N keystroke for an immediate
        answer, or Left / Right / Tab to move the highlight and Enter to
        confirm the current selection. Esc cancels.
    .PARAMETER Question
        Required. The yes/no question to display.
    .PARAMETER Default
        Which button is highlighted on open and chosen if Enter is pressed
        without first moving. 'Yes' or 'No'. Default 'No'.
    .EXAMPLE
        PS> Read-Confirmation -Question 'Delete the file?' -Default No
        Renders: Delete the file?  Yes  [No]
        Returns $true for Yes, $false for No.
    .OUTPUTS
        [bool] $true for Yes, $false for No, or $null if cancelled.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Question,

        [Parameter(Position = 1)]
        [ValidateSet('Yes', 'No')]
        [string]$Default = 'No'
    )

    Assert-InteractiveHost 'Read-Confirmation'

    # 0 = Yes, 1 = No
    $selected = if ($Default -eq 'Yes') { 0 } else { 1 }
    $running = $true
    $result = $null

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
            Write-Host "`r$Question " -NoNewline -ForegroundColor Cyan

            $yesText = ' Yes '
            $noText  = ' No '
            if ($selected -eq 0) {
                Write-Host $yesText -NoNewline -BackgroundColor Cyan -ForegroundColor Black
                Write-Host '  ' -NoNewline
                Write-Host $noText -NoNewline
            } else {
                Write-Host $yesText -NoNewline
                Write-Host '  ' -NoNewline
                Write-Host $noText -NoNewline -BackgroundColor Cyan -ForegroundColor Black
            }
            Write-Host "`e[K" -NoNewline # Clear to end of line

            $key = [Console]::ReadKey($true)

            if ($key.Key -eq 'LeftArrow')  { $selected = 0 }
            elseif ($key.Key -eq 'RightArrow') { $selected = 1 }
            elseif ($key.Key -eq 'Tab')    { $selected = 1 - $selected }
            elseif ($key.Key -eq 'Enter')  { $result = ($selected -eq 0); $running = $false }
            elseif ($key.Key -eq 'Escape') { $result = $null; $running = $false }
            else {
                $c = [char]::ToLower($key.KeyChar)
                if ($c -eq 'y')     { $result = $true;  $running = $false }
                elseif ($c -eq 'n') { $result = $false; $running = $false }
            }
        }

        $finalText = if ($result -eq $true) { 'Yes' } elseif ($result -eq $false) { 'No' } else { '(cancelled)' }
        Write-Host "`r$Question $finalText`e[K"
    } finally {
        if ($originalCursorVisible) {
            Write-Host "`e[?25h" -NoNewline
        }
        Write-Host ""
    }

    return $result
}

function Show-Spinner {
    <#
    .SYNOPSIS
        Run a scriptblock with a live animated spinner.
    .DESCRIPTION
        Renders an animated spinner glyph + activity text on a single line
        while the scriptblock executes, then clears the line and emits the
        scriptblock's output to the pipeline.

        The spinner runs on a background runspace; the scriptblock runs on
        the foreground thread in its defining scope, so closures over
        caller-local variables work without -ArgumentList or $using:.

        Caveat: Write-Host output from the scriptblock will interleave with
        the spinner line. Same limitation as Write-Progress. Use the
        spinner for opaque "wait for this to finish" work.
    .PARAMETER Activity
        Required. Text shown after the spinner glyph.
    .PARAMETER ScriptBlock
        Required. Work to execute. Runs on the foreground thread in the
        caller's scope — closures, imported modules, and $PSCmdlet
        references all work as if you called the scriptblock directly.
    .PARAMETER Style
        Spinner glyph style:
          Braille    (default) — `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` at ~80ms
          Ascii                — `| / - \`        at ~120ms (universal)
          HalfBlocks           — `▖▘▝▗`           at ~120ms
          Dots                 — `.`, `..`, ...   at ~250ms (text-only)
    .PARAMETER NoColor
        Disable ANSI styling on the spinner glyph.
    .PARAMETER ShowTimer
        Append a live elapsed-time counter to the activity line. Format
        narrows as time grows: `(1.2s)` under a minute, `(2m 34s)` under
        an hour, `(1h 23m)` beyond.
    .EXAMPLE
        PS> $baseUrl = 'https://api.example.com'
        PS> $users = Show-Spinner -Activity "Fetching users..." -ScriptBlock {
                Invoke-RestMethod "$baseUrl/users"
            }
        Closure over $baseUrl from caller scope is preserved.
    .EXAMPLE
        PS> Show-Spinner -Activity "Backing up..." -ShowTimer -ScriptBlock {
                Compress-Archive -Path C:\Data -DestinationPath backup.zip
            }
        Live timer reassures the user that long ops aren't hung.
    .OUTPUTS
        Whatever the scriptblock returned.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Activity,

        [Parameter(Mandatory = $true, Position = 1)]
        [scriptblock]$ScriptBlock,

        [Parameter(Position = 2)]
        [ValidateSet('Braille', 'Ascii', 'HalfBlocks', 'Dots')]
        [string]$Style = 'Braille',

        [switch]$NoColor,

        [switch]$ShowTimer
    )

    # Non-VT fallback (Azure Automation, ISE, redirected output): no animation,
    # just bracket the work with plain log lines. Elapsed always included on
    # the "done" line — cheap to capture and far more useful in logs than at
    # an interactive prompt.
    if (-not $script:_SupportsVT) {
        Write-Host "[ $Activity ]"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            & $ScriptBlock
        } finally {
            $sw.Stop()
            $t = $sw.Elapsed
            $elapsed = if ($t.TotalMinutes -lt 1) {
                '{0:F1}s' -f $t.TotalSeconds
            } elseif ($t.TotalHours -lt 1) {
                '{0}m {1}s' -f $t.Minutes, $t.Seconds
            } else {
                '{0}h {1}m' -f [int]$t.TotalHours, $t.Minutes
            }
            Write-Host "[ $Activity done in $elapsed ]"
        }
        return
    }

    # Glyph table + cadence per style. Cadence empirically tuned to read as
    # "alive" without flicker on fast frames.
    $config = switch ($Style) {
        'Braille'    { @{ Frames = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏'); Ms = 80 } }
        'Ascii'      { @{ Frames = @('|','/','-','\');                            Ms = 120 } }
        'HalfBlocks' { @{ Frames = @('▖','▘','▝','▗');                            Ms = 120 } }
        'Dots'       { @{ Frames = @('.   ','..  ','... ','....');                Ms = 250 } }
    }

    # Track original cursor state so we restore exactly what was there.
    $originalCursorVisible = $true
    try {
        if ($null -ne $Host.UI.RawUI.CursorSize -and $Host.UI.RawUI.CursorSize -eq 0) {
            $originalCursorVisible = $false
        }
    } catch {}

    Write-Host "`e[?25l" -NoNewline # hide cursor

    # ManualResetEventSlim lets the foreground signal "stop ticking" cheaply,
    # and makes the background sleep interruptible — Stop returns immediately
    # rather than waiting out the cadence.
    $stopSignal = [System.Threading.ManualResetEventSlim]::new($false)
    # Stopwatch started just before the runspace launches so the displayed
    # elapsed time matches the user's perceived wait — not including our
    # own setup overhead.
    $stopwatch = if ($ShowTimer) { [System.Diagnostics.Stopwatch]::StartNew() } else { $null }
    $tickPS = [powershell]::Create()
    [void]$tickPS.AddScript({
        param($frames, $intervalMs, $activity, $stop, $useColor, $sw)
        $i = 0
        while (-not $stop.IsSet) {
            $glyph = $frames[$i % $frames.Count]
            $suffix = ''
            if ($null -ne $sw) {
                $t = $sw.Elapsed
                $suffix = if ($t.TotalMinutes -lt 1) {
                    ' ({0:F1}s)' -f $t.TotalSeconds
                } elseif ($t.TotalHours -lt 1) {
                    ' ({0}m {1}s)' -f $t.Minutes, $t.Seconds
                } else {
                    ' ({0}h {1}m)' -f [int]$t.TotalHours, $t.Minutes
                }
            }
            $line = if ($useColor) {
                "`r`e[36m$glyph`e[0m $activity$suffix`e[K"
            } else {
                "`r$glyph $activity$suffix`e[K"
            }
            [Console]::Write($line)
            [void]$stop.Wait($intervalMs)
            $i++
        }
        [Console]::Write("`r`e[K")
    })
    [void]$tickPS.AddArgument($config.Frames)
    [void]$tickPS.AddArgument($config.Ms)
    [void]$tickPS.AddArgument($Activity)
    [void]$tickPS.AddArgument($stopSignal)
    [void]$tickPS.AddArgument(-not $NoColor.IsPresent)
    [void]$tickPS.AddArgument($stopwatch)

    $handle = $null
    try {
        $handle = $tickPS.BeginInvoke()
        # Foreground execution preserves the scriptblock's defining scope —
        # closures, $PSCmdlet, etc. all behave as if called inline.
        & $ScriptBlock
    } finally {
        $stopSignal.Set()
        if ($null -ne $handle) {
            try { [void]$tickPS.EndInvoke($handle) } catch {}
        }
        $tickPS.Dispose()
        $stopSignal.Dispose()
        if ($originalCursorVisible) {
            Write-Host "`e[?25h" -NoNewline # restore cursor
        }
    }
}

function Invoke-NestedMenu {
    <#
    .SYNOPSIS
        Render and navigate a nested menu tree.
    .DESCRIPTION
        Walks a tree of menu items where each node has Label, Value, and
        optional Children. Supports keyboard navigation (Up/Down or numeric
        1-N jump), drill-in (Right or Enter on a parent), back (Left), and
        deep-linking on open via -InitialPath. Returns the selected leaf's
        Value, or $null if cancelled.
    .PARAMETER MenuTree
        Required. Array of menu items. Each item is a hashtable or object with
        Label / Value / Children members.
    .PARAMETER Title
        Root menu title shown in the breadcrumb. Default 'Main Menu'.
    .PARAMETER InitialPath
        Optional path to pre-drill on open. Each segment is either a numeric
        index or a string matching a Label or Value at that depth.
    .EXAMPLE
        $tree = @(
            @{ Label='Settings'; Children=@(
                @{ Label='Display'; Value='display' }
                @{ Label='Network'; Value='network' }
            )}
            @{ Label='Exit'; Value='exit' }
        )
        PS> Invoke-NestedMenu -MenuTree $tree
    .OUTPUTS
        The Value of the selected leaf node, or $null if cancelled.
    #>
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

    Assert-InteractiveHost 'Invoke-NestedMenu'

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
    # Stale-buffer reset: digit input older than this is discarded so that
    # typing `1`, idling, then typing `5` selects item 5 instead of item 15.
    $numStringTimeoutMs = 1000
    $lastDigitTime = [DateTime]::MinValue

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
                # Drop the buffer if the previous digit is older than the timeout.
                if ((([DateTime]::Now) - $lastDigitTime).TotalMilliseconds -gt $numStringTimeoutMs) {
                    $numString = ""
                }
                $lastDigitTime = [DateTime]::Now

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

Export-ModuleMember -Function Write-UIBox, Get-PaginatedSelection, Read-MaskedInput, Read-ValidatedInput, Read-Confirmation, Show-Spinner, Invoke-NestedMenu, Measure-FuzzyMatch
