Set-StrictMode -Version Latest

# Cached once at module load. Drives module-wide rendering decisions:
# interactive prompts fail fast with a clear error in non-VT hosts (Azure
# Automation, ISE, redirected output) where [Console]::ReadKey can't work;
# Show-Spinner falls back to plain bracketed log lines. Capability is per-
# host and doesn't change after the module is imported, so caching is safe.
$script:_SupportsVT = $false
try { $script:_SupportsVT = [bool]$Host.UI.SupportsVirtualTerminal } catch {}

# User preferences via environment variables, resolved once at import.
# Per-call -Ascii / -NoColor switches override these on a per-function basis;
# the resolution rule across the module is: explicit switch > env var > rich
# default. NO_COLOR is the de-facto standard from https://no-color.org.
$script:_AsciiMode = [bool]$env:PWSHTUI_ASCII
$script:_NoColor   = [bool]$env:NO_COLOR

# Spinner output channel. Write-Spinner enqueues to this buffer when a
# spinner is active on a VT host; the ticker drains the queue each frame,
# writing each entry above the spinner row so log lines persist while the
# glyph keeps animating. Outside an active spinner — or in non-VT contexts
# where there's no glyph to conflict with — Write-Spinner passes through
# to Write-Host. ConcurrentQueue handles the producer/consumer split between
# the foreground scriptblock and the background ticker runspace.
$script:_SpinnerActive = $false
$script:_SpinnerBuffer = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

# ConsoleColor -> SGR foreground code. Write-Spinner pre-wraps the message
# with the matching ANSI escape before enqueueing so the ticker — which
# writes raw and has no Write-Host -ForegroundColor available — can just
# blit each entry as-is and keep the user's color.
$script:_ConsoleColorAnsi = @{
    'Black'       = '30'; 'DarkBlue'    = '34'; 'DarkGreen'   = '32'; 'DarkCyan'    = '36'
    'DarkRed'     = '31'; 'DarkMagenta' = '35'; 'DarkYellow'  = '33'; 'Gray'        = '37'
    'DarkGray'    = '90'; 'Blue'        = '94'; 'Green'       = '92'; 'Cyan'        = '96'
    'Red'         = '91'; 'Magenta'     = '95'; 'Yellow'      = '93'; 'White'       = '97'
}

# Glyph tables. Unicode is the rich default; ASCII swaps cover restricted
# fonts (legacy Windows code pages, ancient terminals, log scrapes). The
# Ascii table is chosen so the ASCII version of each glyph reads as the same
# semantic affordance — `->` still feels like a right arrow, `+` still feels
# like a corner/junction, `>` still suggests "drill in."
$script:_GlyphsUnicode = @{
    BorderH        = '─'; BorderV    = '│'
    BorderTL       = '┌'; BorderTR   = '┐'
    BorderBL       = '└'; BorderBR   = '┘'
    BorderTeeL     = '├'; BorderTeeR = '┤'
    ArrowLeft      = '←'; ArrowRight = '→'
    ArrowsUpDown   = '↑↓'
    ChildIndicator = '►'
    RadioOn        = '●'; RadioOff   = '○'
}
$script:_GlyphsAscii = @{
    BorderH        = '-'; BorderV    = '|'
    BorderTL       = '+'; BorderTR   = '+'
    BorderBL       = '+'; BorderBR   = '+'
    BorderTeeL     = '+'; BorderTeeR = '+'
    ArrowLeft      = '<-'; ArrowRight = '->'
    ArrowsUpDown   = '^v'
    ChildIndicator = '>'
    RadioOn        = '[x]'; RadioOff = '[ ]'
}

function Get-Glyphs([bool]$Ascii) {
    if ($Ascii) { $script:_GlyphsAscii } else { $script:_GlyphsUnicode }
}

# Localized UI strings. Defaults below are en-US and stay as a complete
# fallback set so the module renders correctly even if no resource file
# matches. Import-LocalizedData walks the culture hierarchy automatically
# (e.g. fr-CA → fr-FR → invariant) and overlays any keys it finds. Set
# $PSUICulture before importing the module to force a specific locale;
# users wanting to add a translation just drop a new <culture>/
# pwshTui.Strings.psd1 alongside the existing ones.
$script:_Strings = @{
    Footer_Move      = 'Move'
    Footer_Select    = 'Select'
    Footer_Confirm   = 'Confirm'
    Footer_Cancel    = 'Cancel'
    Footer_Exit      = 'Exit'
    Footer_Toggle    = 'Toggle'
    Footer_Expand    = 'Expand'
    Footer_Back      = 'Back'
    Footer_PrevPage  = 'Prev page'
    Footer_NextPage  = 'Next page'
    Footer_Selected  = 'selected'
    Footer_Search    = 'Search'
    Status_NoMatches = '(No matches found)'
    Status_NoItems   = 'No items to select.'
    Status_Cancelled = '(cancelled)'
    Status_DoneIn    = 'done in'
}
try {
    $loaded = $null
    Import-LocalizedData -BindingVariable 'loaded' -BaseDirectory $PSScriptRoot -FileName 'pwshTui.Strings.psd1' -ErrorAction Stop
    if ($loaded) {
        foreach ($k in $loaded.Keys) { $script:_Strings[$k] = $loaded[$k] }
    }
} catch {
    # No matching resource file — defaults already populated.
}

function Test-ControlC([System.ConsoleKeyInfo]$Key) {
    # True when the keypress is Ctrl+C. Interactive functions set
    # [Console]::TreatControlCAsInput = $true so Ctrl+C arrives as a regular
    # key instead of being captured by the PowerShell engine — that lets the
    # function react immediately rather than waiting for the next keystroke
    # to unblock ReadKey. Original setting is restored in finally.
    return ($Key.Key -eq 'C' -and ($Key.Modifiers -band [ConsoleModifiers]::Control))
}

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
    .PARAMETER SectionRules
        Draw a horizontal rule between sections (header→body, body→footer)
        when not in -Border mode. In -Border mode the existing connector
        rules are used instead; this switch is a no-op there. Useful for
        borderless layouts that still want visual segregation between the
        title, content, and key-hint footer.
    .PARAMETER Ascii
        Swap Unicode box-drawing characters for ASCII equivalents
        (`─┌┐└┘├┤│` → `-+++++|`). Module-wide default reads `$env:PWSHTUI_ASCII`;
        the per-call switch overrides. Useful in restricted terminals,
        legacy code pages, or fonts missing box-drawing glyphs.
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
        [switch]$AltScreen,
        [switch]$SectionRules,
        [switch]$Ascii
    )

    # Resolve effective ASCII mode: explicit switch > $env:PWSHTUI_ASCII > rich.
    $asciiOn = if ($PSBoundParameters.ContainsKey('Ascii')) { [bool]$Ascii } else { $script:_AsciiMode }
    $g = Get-Glyphs $asciiOn

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
    $horiz     = $g.BorderH * ($innerBoxWidth + 2)
    $plainRule = $g.BorderH * $innerBoxWidth

    if ($Border) { $frame.Add("$($g.BorderTL)$horiz$($g.BorderTR)") }

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
            if ($Border) { $frame.Add("$($g.BorderV) $displayText$padding $($g.BorderV)") }
            else { $frame.Add("$displayText$padding") }
        }
    }

    if ($Header) {
        & $addSectionLines $Header
        if ($Border -and ($Body -or $Footer)) { $frame.Add("$($g.BorderTeeL)$horiz$($g.BorderTeeR)") }
        elseif ($SectionRules -and ($Body -or $Footer)) { $frame.Add($plainRule) }
    }

    & $addSectionLines $Body

    if ($Footer) {
        if ($Border) { $frame.Add("$($g.BorderTeeL)$horiz$($g.BorderTeeR)") }
        elseif ($SectionRules) { $frame.Add($plainRule) }
        & $addSectionLines $Footer
    }

    if ($Border) { $frame.Add("$($g.BorderBL)$horiz$($g.BorderBR)") }

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
        powered by Measure-FuzzyMatch. With -MultiSelect, Tab toggles rows
        and Enter returns an array of toggled items.

        Keys: Up/Down move within page, Left/Right change page, Enter selects,
        Esc cancels. In Searchable mode any printable character (including
        Space) extends the search buffer; Backspace deletes from it. In
        MultiSelect mode Tab toggles the current row's selection — chosen so
        Space stays available for the search buffer and never silently
        toggles a row mid-query.
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
        Enable multi-selection. Tab toggles the current row's selection
        (independent of cursor position); Enter returns an array of selected
        items in original input order. Selection state persists across search
        filter changes. Esc still returns $null. Enter with no toggled items
        returns an empty array (distinguishable from $null cancel).

        Tab (not Space) is the toggle so the search buffer can accept Space
        as a normal character — matches fzf -m convention.
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

        [switch]$MultiSelect,

        [switch]$Ascii
    )

    Assert-InteractiveHost 'Get-PaginatedSelection'

    # Resolve effective rendering modes: explicit switch > env var > rich.
    $asciiOn   = if ($PSBoundParameters.ContainsKey('Ascii'))   { [bool]$Ascii }   else { $script:_AsciiMode }
    $noColorOn = if ($PSBoundParameters.ContainsKey('NoColor')) { [bool]$NoColor } else { $script:_NoColor }
    $g = Get-Glyphs $asciiOn

    $itemList = @($Items)
    if ($itemList.Count -eq 0) {
        Write-Warning $script:_Strings.Status_NoItems
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

    # Capture Ctrl+C as a regular key so the function can react immediately
    # instead of waiting for the next keystroke to unblock ReadKey. Restored
    # in finally so the user's session-wide Ctrl+C behavior is unchanged.
    $origCtrlC = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true

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
                if ($searchBuffer) { "$Title [$($script:_Strings.Footer_Search): $searchBuffer]" }
                else { "$Title [$($script:_Strings.Footer_Search)]" }
            } else {
                $Title
            }

            $header = @($displayTitle)
            
            $body = @()
            if ($currentPageItems.Count -gt 0) {
                for ($i = 0; $i -lt $currentPageItems.Count; $i++) {
                    $item = $currentPageItems[$i]
                    $displayText = ""
                    if ($DisplayProperty) { $displayText = $item.$DisplayProperty }
                    else { $displayText = $item.ToString() }
                    if ([string]::IsNullOrWhiteSpace($displayText)) { $displayText = $item.ToString() }

                    if ($MultiSelect) {
                        $marker = if ($selectedSet.Contains($item)) { $g.RadioOn } else { $g.RadioOff }
                        $displayText = "$marker  $displayText"
                    }

                    $isRowSelected = ($i -eq $selectedIndex)
                    if ($isRowSelected) {
                        if ($noColorOn) {
                            $body += "$pointer$displayText"
                        } else {
                            $body += "`e[36m$pointer`e[46;30m$displayText`e[0m"
                        }
                    } else {
                        $body += "$emptyPointer$displayText"
                    }
                }
            } else {
                $body += "  $($script:_Strings.Status_NoMatches)"
            }

            $pageNumDisplay = "($($pageIndex + 1)/$pageCount)"
            $endIdx = [Math]::Min($startIdx + $PageSize, $filteredItems.Count)
            $startDisplay = if ($filteredItems.Count -gt 0) { $startIdx + 1 } else { 0 }
            $rangeDisplay = "($startDisplay-$endIdx of $($filteredItems.Count))"
            
            $s = $script:_Strings
            $footerLines = [System.Collections.Generic.List[string]]::new()
            $footerLines.Add("$($g.ArrowLeft) $($s.Footer_PrevPage) $pageNumDisplay   $($g.ArrowRight) $($s.Footer_NextPage) $pageNumDisplay")
            if ($MultiSelect) {
                $footerLines.Add("$($g.ArrowsUpDown) $($s.Footer_Move) $rangeDisplay   Tab=$($s.Footer_Toggle) ($($selectedSet.Count) $($s.Footer_Selected))   Enter=$($s.Footer_Confirm)   Esc=$($s.Footer_Cancel)")
            } else {
                $footerLines.Add("$($g.ArrowsUpDown) $($s.Footer_Move) $rangeDisplay   Enter=$($s.Footer_Select)   Esc=$($s.Footer_Cancel)")
            }

            $footer = @($footerLines)

            # Draw using UIBox
            $newHeight = Write-UIBox -Header $header -Body $body -Footer $footer `
                                      -Border:$Border -MinWidth $MinWidth -MaxWidth $MaxWidth -X $X -Y $Y `
                                      -SectionRules -Ascii:$asciiOn

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

            if (Test-ControlC $key) {
                throw [System.Management.Automation.PipelineStoppedException]::new()
            }

            if ($MultiSelect -and $key.Key -eq 'Tab') {
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
                    # Skip leading spaces. A bare leading space collapses the
                    # list to "no matches" (nothing scores against ' '), which
                    # is the opposite of what users expect from an impulsive
                    # Space press. Internal spaces are still allowed so
                    # multi-word queries like "my server" work.
                    if (-not ($searchBuffer.Length -eq 0 -and $key.KeyChar -eq ' ')) {
                        $searchBuffer += $key.KeyChar
                        $handledSearchKey = $true
                    }
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

        [Console]::TreatControlCAsInput = $origCtrlC

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

        [switch]$ReturnRaw,

        [switch]$NoColor
    )

    Assert-InteractiveHost 'Read-MaskedInput'

    # Resolve effective NoColor: explicit switch > env var > colored default.
    $noColorOn = if ($PSBoundParameters.ContainsKey('NoColor')) { [bool]$NoColor } else { $script:_NoColor }

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

    $origCtrlC = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true

    try {
        while ($running) {
            # Determine next slot screen index for highlighting
            $nextSlotScreenIdx = -1
            if ($cursor -lt $slots.Count) {
                $nextSlotScreenIdx = $slots[$cursor].Index
            }

            # Render Prompt
            if ($noColorOn) {
                Write-Host "`r$Prompt " -NoNewline
            } else {
                Write-Host "`r$Prompt " -NoNewline -ForegroundColor Cyan
            }

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

            # Draw Masked String. In NoColor mode, bracket the cursor slot so
            # the active position is visible without color highlight.
            for ($i = 0; $i -lt $displayStr.Length; $i++) {
                if ($i -eq $nextSlotScreenIdx) {
                    if ($noColorOn) {
                        Write-Host "[$($displayStr[$i])]" -NoNewline
                    } else {
                        Write-Host "$($displayStr[$i])" -NoNewline -BackgroundColor Cyan -ForegroundColor Black
                    }
                } else {
                    Write-Host "$($displayStr[$i])" -NoNewline
                }
            }

            Write-Host "`e[K" -NoNewline # Clear to end of line

            # Handle Input
            $key = [Console]::ReadKey($true)

            if (Test-ControlC $key) {
                throw [System.Management.Automation.PipelineStoppedException]::new()
            } elseif ($key.Key -eq 'Enter') {
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

        [Console]::TreatControlCAsInput = $origCtrlC

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

        [switch]$AllowEmpty,

        [switch]$NoColor
    )

    Assert-InteractiveHost 'Read-ValidatedInput'

    # Resolve effective NoColor: explicit switch > env var > colored default.
    $noColorOn = if ($PSBoundParameters.ContainsKey('NoColor')) { [bool]$NoColor } else { $script:_NoColor }

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

    $origCtrlC = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true

    try {
        while ($running) {
            $currentStr = -join $rawInput
            $isValid = ($currentStr -match $Pattern)
            if ($AllowEmpty -and $currentStr.Length -eq 0) { $isValid = $true }

            # Render Prompt
            if ($noColorOn) {
                Write-Host "`r$Prompt " -NoNewline
            } else {
                Write-Host "`r$Prompt " -NoNewline -ForegroundColor Cyan
            }

            # Draw Input String
            if ($noColorOn) {
                # In NoColor mode: bracket the cursor slot, append a [OK]/[??]
                # marker so the user still gets live validity feedback without
                # red/green coloring.
                for ($i = 0; $i -le $currentStr.Length; $i++) {
                    if ($i -eq $cursor) {
                        $charToDraw = ' '
                        if ($i -lt $currentStr.Length) { $charToDraw = $currentStr[$i] }
                        Write-Host "[$charToDraw]" -NoNewline
                    } elseif ($i -lt $currentStr.Length) {
                        Write-Host $currentStr[$i] -NoNewline
                    }
                }
                $validMarker = if ($currentStr.Length -eq 0) { '' } elseif ($isValid) { ' [OK]' } else { ' [??]' }
                Write-Host $validMarker -NoNewline
            } else {
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
            }

            Write-Host "`e[K" -NoNewline # Clear to end of line

            # Handle Input
            $key = [Console]::ReadKey($true)

            if (Test-ControlC $key) {
                throw [System.Management.Automation.PipelineStoppedException]::new()
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

        [Console]::TreatControlCAsInput = $origCtrlC

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
        [string]$Default = 'No',

        [switch]$NoColor
    )

    Assert-InteractiveHost 'Read-Confirmation'

    # Resolve effective NoColor: explicit switch > env var > colored default.
    $noColorOn = if ($PSBoundParameters.ContainsKey('NoColor')) { [bool]$NoColor } else { $script:_NoColor }

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

    $origCtrlC = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true

    try {
        while ($running) {
            if ($noColorOn) {
                Write-Host "`r$Question " -NoNewline
                # Bracket the highlighted option so it stands out without color.
                $yesPart = if ($selected -eq 0) { '[Yes]' } else { ' Yes ' }
                $noPart  = if ($selected -eq 1) { '[No]'  } else { ' No '  }
                Write-Host "$yesPart  $noPart" -NoNewline
            } else {
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
            }
            Write-Host "`e[K" -NoNewline # Clear to end of line

            $key = [Console]::ReadKey($true)

            if (Test-ControlC $key)             { throw [System.Management.Automation.PipelineStoppedException]::new() }
            elseif ($key.Key -eq 'LeftArrow')   { $selected = 0 }
            elseif ($key.Key -eq 'RightArrow')  { $selected = 1 }
            elseif ($key.Key -eq 'Tab')         { $selected = 1 - $selected }
            elseif ($key.Key -eq 'Enter')       { $result = ($selected -eq 0); $running = $false }
            elseif ($key.Key -eq 'Escape')      { $result = $null; $running = $false }
            else {
                $c = [char]::ToLower($key.KeyChar)
                if ($c -eq 'y')     { $result = $true;  $running = $false }
                elseif ($c -eq 'n') { $result = $false; $running = $false }
            }
        }

        $finalText = if ($result -eq $true) { 'Yes' } elseif ($result -eq $false) { 'No' } else { $script:_Strings.Status_Cancelled }
        Write-Host "`r$Question $finalText`e[K"
    } finally {
        if ($originalCursorVisible) {
            Write-Host "`e[?25h" -NoNewline
        }
        [Console]::TreatControlCAsInput = $origCtrlC
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
          Circles              — `○◔◑◕●◕◑◔`     at ~110ms (filling wave)
          Pulse                — `· • ● •`       at ~200ms (breathing)
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
        [ValidateSet('Braille', 'Ascii', 'HalfBlocks', 'Dots', 'Circles', 'Pulse')]
        [string]$Style = 'Braille',

        [switch]$NoColor,

        [switch]$ShowTimer,

        [switch]$Ascii
    )

    # Resolve effective rendering modes: explicit switch > env var > rich.
    # -Ascii forces -Style Ascii (overrides any -Style choice) so the safety
    # fallback is opt-in via a single consistent switch name across the module.
    $asciiOn   = if ($PSBoundParameters.ContainsKey('Ascii'))   { [bool]$Ascii }   else { $script:_AsciiMode }
    $noColorOn = if ($PSBoundParameters.ContainsKey('NoColor')) { [bool]$NoColor } else { $script:_NoColor }
    if ($asciiOn) { $Style = 'Ascii' }

    # Non-VT fallback (Azure Automation, ISE, redirected output): no animation,
    # just bracket the work with plain log lines. Elapsed always included on
    # the "done" line — cheap to capture and far more useful in logs than at
    # an interactive prompt.
    if (-not $script:_SupportsVT) {
        Write-Host "[ $Activity ]"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $script:_SpinnerActive = $true
        try {
            & $ScriptBlock
        } finally {
            $script:_SpinnerActive = $false
            $sw.Stop()
            $t = $sw.Elapsed
            $elapsed = if ($t.TotalMinutes -lt 1) {
                '{0:F1}s' -f $t.TotalSeconds
            } elseif ($t.TotalHours -lt 1) {
                '{0}m {1}s' -f $t.Minutes, $t.Seconds
            } else {
                '{0}h {1}m' -f [int]$t.TotalHours, $t.Minutes
            }
            Write-Host "[ $Activity $($script:_Strings.Status_DoneIn) $elapsed ]"
        }
        return
    }

    # Glyph table + cadence per style. Cadence empirically tuned to read as
    # "alive" without flicker on fast frames.
    $config = switch ($Style) {
        'Braille'    { @{ Frames = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏'); Ms = 80  } }
        'Ascii'      { @{ Frames = @('|','/','-','\');                            Ms = 120 } }
        'HalfBlocks' { @{ Frames = @('▖','▘','▝','▗');                            Ms = 120 } }
        'Dots'       { @{ Frames = @('.   ','..  ','... ','....');                Ms = 250 } }
        'Circles'    { @{ Frames = @('○','◔','◑','◕','●','◕','◑','◔');            Ms = 110 } }
        'Pulse'      { @{ Frames = @('·','•','●','•');                            Ms = 200 } }
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
        param($frames, $intervalMs, $activity, $stop, $useColor, $sw, $buffer)
        $i = 0
        while (-not $stop.IsSet) {
            # Drain pending log lines from Write-Spinner: clear the
            # spinner row, emit each entry on its own line (with newline so
            # it scrolls up and persists), then fall through to redraw the
            # glyph on the now-empty current row.
            $msg = $null
            while ($buffer.TryDequeue([ref]$msg)) {
                [Console]::Write("`r`e[K$msg`n")
            }
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
        # Final drain: catch anything enqueued between the last tick and the
        # stop signal so no log line is lost when the row is cleared.
        $msg = $null
        while ($buffer.TryDequeue([ref]$msg)) {
            [Console]::Write("`r`e[K$msg`n")
        }
        [Console]::Write("`r`e[K")
    })
    [void]$tickPS.AddArgument($config.Frames)
    [void]$tickPS.AddArgument($config.Ms)
    [void]$tickPS.AddArgument($Activity)
    [void]$tickPS.AddArgument($stopSignal)
    [void]$tickPS.AddArgument(-not $noColorOn)
    [void]$tickPS.AddArgument($stopwatch)
    [void]$tickPS.AddArgument($script:_SpinnerBuffer)

    $script:_SpinnerActive = $true
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
        $script:_SpinnerActive = $false
        if ($originalCursorVisible) {
            Write-Host "`e[?25h" -NoNewline # restore cursor
        }
    }
}

function Write-Spinner {
    <#
    .SYNOPSIS
        Emit a log line that persists above an active spinner.
    .DESCRIPTION
        Solves the Show-Spinner caveat that plain Write-Host output from
        inside a -ScriptBlock visually corrupts the animated glyph row.
        Use Write-Spinner as the opt-in clean channel for any visible
        text the scriptblock needs to emit while a spinner is running.

        On a VT-capable host with an active Show-Spinner, the message is
        enqueued and the spinner's background ticker drains it on its next
        frame: the spinner row is cleared, the message is written with a
        trailing newline so it scrolls up and persists, and the spinner is
        redrawn on the now-empty current row.

        Outside an active spinner — or in non-VT contexts where the
        spinner has no animated row to conflict with — the call passes
        through to Write-Host. So a helper that uses Write-Spinner
        stays drop-in usable whether or not its caller wraps it in a
        spinner.

        Scope: this is specifically for Write-Host-style visible output
        (the stream that would otherwise tear the spinner). Write-Verbose,
        Write-Warning, Write-Error, and pipeline output are unaffected
        and continue to use their own streams.
    .PARAMETER Message
        Required. Text to emit. Pass a single string; embedded `\n` will
        render as multiple lines, all of which scroll above the spinner.
    .PARAMETER ForegroundColor
        Optional. Standard System.ConsoleColor for the message. When
        enqueued for a VT spinner, the message is ANSI-wrapped with the
        matching SGR foreground code so the persisted line keeps its
        color. Suppressed under $env:NO_COLOR.
    .EXAMPLE
        PS> Show-Spinner -Activity "Indexing" -ShowTimer -ScriptBlock {
                foreach ($file in $files) {
                    Process $file
                    Write-Spinner "Indexed $($file.Name)" -ForegroundColor DarkGray
                }
            }
        Each "Indexed ..." line scrolls above the spinning glyph and is
        preserved in scrollback when the spinner finishes.
    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Message,

        [System.ConsoleColor]$ForegroundColor
    )

    if ($script:_SpinnerActive -and $script:_SupportsVT) {
        $payload = if ($PSBoundParameters.ContainsKey('ForegroundColor') -and -not $script:_NoColor) {
            $code = $script:_ConsoleColorAnsi[$ForegroundColor.ToString()]
            "`e[${code}m$Message`e[0m"
        } else {
            $Message
        }
        [void]$script:_SpinnerBuffer.Enqueue($payload)
    } else {
        if ($PSBoundParameters.ContainsKey('ForegroundColor')) {
            Write-Host $Message -ForegroundColor $ForegroundColor
        } else {
            Write-Host $Message
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
        [switch]$AltScreen,
        [switch]$NoColor,
        [switch]$Ascii
    )

    Assert-InteractiveHost 'Invoke-NestedMenu'

    # Resolve effective rendering modes: explicit switch > env var > rich.
    $asciiOn   = if ($PSBoundParameters.ContainsKey('Ascii'))   { [bool]$Ascii }   else { $script:_AsciiMode }
    $noColorOn = if ($PSBoundParameters.ContainsKey('NoColor')) { [bool]$NoColor } else { $script:_NoColor }
    $g = Get-Glyphs $asciiOn

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

    $origCtrlC = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true

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
            $header = @($breadcrumb)

            # Body
            $pointer = "> "
            $emptyPointer = "  "
            $body = @()

            for ($i = 0; $i -lt $currentItems.Count; $i++) {
                $item = $currentItems[$i]
                $isRowSelected = ($i -eq $selectedIndex)
                $displayNum = $i + 1

                $suffix = if ($null -ne $item.Children -and $item.Children.Count -gt 0) { " $($g.ChildIndicator)" } else { "" }
                $displayText = "[$displayNum] $($item.Label)$suffix"

                if ($isRowSelected) {
                    if ($noColorOn) {
                        $body += "$pointer$displayText"
                    } else {
                        $body += "`e[36m$pointer`e[46;30m$displayText`e[0m"
                    }
                } else {
                    $body += "$emptyPointer$displayText"
                }
            }

            # Footer
            $s = $script:_Strings
            $footer = @("$($g.ArrowsUpDown) $($s.Footer_Move)   $($g.ArrowRight) $($s.Footer_Expand)   $($g.ArrowLeft) $($s.Footer_Back)   Enter=$($s.Footer_Select)   Esc=$($s.Footer_Exit)")

            # Draw using UIBox
            $newHeight = Write-UIBox -Header $header -Body $body -Footer $footer `
                                      -Border:$Border -MinWidth $MinWidth -MaxWidth $MaxWidth -X $X -Y $Y `
                                      -SectionRules -Ascii:$asciiOn

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

            if (Test-ControlC $key) {
                throw [System.Management.Automation.PipelineStoppedException]::new()
            }

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

        [Console]::TreatControlCAsInput = $origCtrlC

        # Clean line on abort
        if ($null -eq $result) {
            Write-Host ""
        }
    }

    return $result
}

Export-ModuleMember -Function Write-UIBox, Get-PaginatedSelection, Read-MaskedInput, Read-ValidatedInput, Read-Confirmation, Show-Spinner, Write-Spinner, Invoke-NestedMenu, Measure-FuzzyMatch
