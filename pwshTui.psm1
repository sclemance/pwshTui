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
# Live spinner label, mutable while the spinner runs. A synchronized hashtable so
# the foreground (Set-SpinnerActivity) and the background ticker runspace share one
# object; the ticker reads .Text each frame. A hashtable rather than a bare string
# leaves room to carry structured progress data later without another shared slot.
$script:_SpinnerActivity = [hashtable]::Synchronized(@{ Text = '' })

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
    BarFill        = '█'; BarEmpty   = '░'
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
    BarFill        = '#';  BarEmpty  = '-'
}

function Get-Glyphs([bool]$Ascii) {
    if ($Ascii) { $script:_GlyphsAscii } else { $script:_GlyphsUnicode }
}

function Get-DisplayWidth {
    # Return the visible column width of a string when rendered to a typical
    # terminal. Differs from String.Length in three ways:
    #   - East-Asian Wide and Fullwidth code points (CJK ideographs, Hiragana,
    #     Katakana, Hangul Syllables, Fullwidth Forms) count as 2 cells.
    #   - Control characters count as 0.
    #   - ANSI CSI sequences (e.g. `\e[31m`) count as 0 — they're skipped
    #     inline so callers can pass already-styled strings without
    #     pre-stripping. Bare ESC without a CSI body is treated as a regular
    #     control char (skipped).
    # The range table is the conservative Unicode East-Asian-Width Wide/
    # Fullwidth set — narrow ambiguous handling and emoji-modifier joining
    # are out of scope; we accept occasional miscounts on edge code points
    # rather than carry a full bidi/grapheme engine.
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    $w = 0
    $i = 0
    while ($i -lt $Text.Length) {
        # ANSI CSI sequence: ESC '[' <params> <final byte A-Za-z>.
        if ($Text[$i] -eq [char]27 -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '[') {
            $i += 2
            while ($i -lt $Text.Length -and ($Text[$i] -match '[0-9;]')) { $i++ }
            if ($i -lt $Text.Length -and [char]::IsLetter($Text[$i])) { $i++ }
            continue
        }
        # Surrogate-pair handling: a high+low surrogate together name one
        # code point. We advance past the low surrogate so the loop sees the
        # pair as a single character.
        if ([char]::IsHighSurrogate($Text[$i]) -and ($i + 1) -lt $Text.Length -and [char]::IsLowSurrogate($Text[$i + 1])) {
            $cp = [char]::ConvertToUtf32($Text, $i)
            $i += 2
        } else {
            $cp = [int][char]$Text[$i]
            $i++
        }
        if ($cp -lt 0x20 -or ($cp -ge 0x7F -and $cp -lt 0xA0)) {
            continue
        }
        $isWide = `
            ($cp -ge 0x1100  -and $cp -le 0x115F) -or          ` # Hangul Jamo
            ($cp -ge 0x2E80  -and $cp -le 0x303E) -or          ` # CJK Radicals / Kangxi
            ($cp -ge 0x3041  -and $cp -le 0x33FF) -or          ` # Hiragana, Katakana, CJK Symbols
            ($cp -ge 0x3400  -and $cp -le 0x4DBF) -or          ` # CJK Ext A
            ($cp -ge 0x4E00  -and $cp -le 0x9FFF) -or          ` # CJK Unified Ideographs
            ($cp -ge 0xA000  -and $cp -le 0xA4CF) -or          ` # Yi
            ($cp -ge 0xAC00  -and $cp -le 0xD7A3) -or          ` # Hangul Syllables
            ($cp -ge 0xF900  -and $cp -le 0xFAFF) -or          ` # CJK Compat Ideographs
            ($cp -ge 0xFE30  -and $cp -le 0xFE4F) -or          ` # CJK Compat Forms
            ($cp -ge 0xFF00  -and $cp -le 0xFF60) -or          ` # Fullwidth Forms
            ($cp -ge 0xFFE0  -and $cp -le 0xFFE6) -or          ` # Fullwidth Signs
            ($cp -ge 0x1F300 -and $cp -le 0x1F64F) -or         ` # Misc Symbols & Pictographs / Emoji
            ($cp -ge 0x1F900 -and $cp -le 0x1F9FF) -or         ` # Supplemental Symbols & Pictographs
            ($cp -ge 0x20000 -and $cp -le 0x3FFFD)               # CJK Ext B-F (supplementary plane)
        if ($isWide) { $w += 2 } else { $w += 1 }
    }
    return $w
}

function Add-DisplayPadding {
    # Right-pad $Text with spaces until its display width reaches $Width.
    # If the text is already at-or-wider than the target, returns it
    # unchanged — callers control truncation policy themselves.
    param([string]$Text, [int]$Width)
    $current = Get-DisplayWidth $Text
    if ($current -ge $Width) { return $Text }
    return $Text + (' ' * ($Width - $current))
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
    Footer_BackToSelection = 'Selection mode'
    Footer_Field     = 'Field'
    Footer_Adjust    = 'Adjust'
    Footer_Edit      = 'Edit'
    Status_NoMatches = '(No matches found)'
    Status_NoItems   = 'No items to select.'
    Status_Cancelled = '(cancelled)'
    Status_DoneIn    = 'done in'
    Notice_PasteControlChars = 'Pasted content contains control characters; rejected.'
    Notice_PasteRejected     = 'Paste rejected ({0}).'
    Notice_PasswordMismatch  = 'Passwords did not match. Try again.'
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

function Write-Notice {
    # Emit a one-line transient notice over the current line (carriage-return +
    # clear-to-EOL), prefixed with a consistent `[!] ` marker, then newline so a
    # subsequent re-prompt lands cleanly below. Centralizes the colour decision
    # (red, or plain when NoColor) that every in-loop rejection used to re-guard
    # by hand, and gives those rejections a single voice. Callers pass their
    # already-resolved NoColor state via -NoColor so an explicit per-call
    # `-NoColor` switch is honoured, not just the module default.
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        [switch]$NoColor
    )
    $noColorOn = if ($PSBoundParameters.ContainsKey('NoColor')) { [bool]$NoColor } else { $script:_NoColor }
    $line = "`r`e[K[!] $Message"
    if ($noColorOn) { Write-Host $line }
    else { Write-Host $line -ForegroundColor Red }
}

function Enter-RawConsole {
    # Put the console into the raw mode every interactive widget needs, and
    # return a state token to hand back to Exit-RawConsole in a finally block.
    # Centralizes the setup that was hand-rolled in each function:
    #   - probe + remember whether the real cursor was visible, then hide it
    #   - route Ctrl+C to input so it arrives as a keystroke (caught and
    #     unwound immediately, instead of waiting for the next ReadKey)
    #   - optionally enable bracketed paste and/or the alternate screen buffer
    # Exit-RawConsole reverses exactly what was changed, so teardown can never
    # drift out of sync with setup.
    param([switch]$BracketedPaste, [switch]$AltScreen)

    $cursorVisible = $true
    try {
        if ($null -ne $Host.UI.RawUI.CursorSize -and $Host.UI.RawUI.CursorSize -eq 0) { $cursorVisible = $false }
    } catch {}

    Write-Host "`e[?25l" -NoNewline                            # hide real cursor
    if ($AltScreen)      { Write-Host "`e[?1049h" -NoNewline } # alternate screen
    if ($BracketedPaste) { Write-Host "`e[?2004h" -NoNewline } # bracketed paste

    $origCtrlC = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true

    return [PSCustomObject]@{
        OrigCtrlC      = $origCtrlC
        CursorVisible  = $cursorVisible
        AltScreen      = [bool]$AltScreen
        BracketedPaste = [bool]$BracketedPaste
    }
}

function Exit-RawConsole {
    # Reverse Enter-RawConsole using its returned state token; call from finally.
    # Disable paste / alt-screen first (mirroring the order the call sites used),
    # re-show the cursor only if it was visible going in, then restore the user's
    # session-wide Ctrl+C behavior. Idempotent enough to be safe in a finally
    # even if setup partially failed.
    param([Parameter(Mandatory, Position = 0)]$State)
    if ($null -eq $State) { return }
    if ($State.BracketedPaste) { Write-Host "`e[?2004l" -NoNewline }
    if ($State.AltScreen)      { Write-Host "`e[?1049l" -NoNewline }
    if ($State.CursorVisible)  { Write-Host "`e[?25h" -NoNewline }
    [Console]::TreatControlCAsInput = $State.OrigCtrlC
}

function Read-KeyOrPaste {
    # Internal: read one input event, transparently consuming bracketed-paste
    # sequences. Returns a PSCustomObject:
    #   Kind = 'Key'     → Key field holds a [ConsoleKeyInfo] (normal keystroke)
    #   Kind = 'Paste'   → Text, TrailingNewline, HasControlChars fields
    #   Kind = 'Discard' → an ESC sequence we don't handle; caller re-reads
    #
    # Callers must have enabled bracketed paste (`\e[?2004h`) before their
    # input loop and must disable it (`\e[?2004l`) in finally — this helper
    # only does protocol parsing, not setup. Sanitation policy (which control
    # chars are acceptable, how to handle a trailing newline) is left to the
    # caller so each input function can apply rules appropriate to its
    # context.
    $key = [Console]::ReadKey($true)
    # Fast path: anything that's not an Escape with buffered follow-up is a
    # normal key. A real Escape press is followed by a pause; a terminal-
    # sent CSI sequence arrives back-to-back, so KeyAvailable right after
    # the ESC distinguishes them. The KeyAvailable check is the standard
    # ANSI-escape disambiguation trick — same as GNU Readline and friends.
    if ($key.Key -ne 'Escape' -or -not [Console]::KeyAvailable) {
        return [PSCustomObject]@{ Kind = 'Key'; Key = $key }
    }
    # CSI sequence: read parameter bytes up to a final byte (~ or A-Za-z per
    # ECMA-48). Capped at 10 chars defensively against pathological input.
    $seq = ''
    while ([Console]::KeyAvailable -and $seq.Length -lt 10) {
        $next = [Console]::ReadKey($true)
        $seq += $next.KeyChar
        if ($next.KeyChar -match '[~A-Za-z]') { break }
    }
    if ($seq -ne '[200~') {
        # Unrecognized CSI (cursor reports, mouse events, raw arrow keys
        # arriving as ESC sequences on some terminals, etc.) — silently
        # discard and let the caller re-read.
        return [PSCustomObject]@{ Kind = 'Discard' }
    }
    # Bracketed paste body. Consume until [201~ end sentinel, watching for
    # ESC sequences embedded in paste content (rare but possible — a paste
    # of terminal-recorded output, say).
    $pasteBuf = New-Object System.Text.StringBuilder
    $endSeen = $false
    while (-not $endSeen) {
        $pc = [Console]::ReadKey($true)
        if (Test-ControlC $pc) {
            throw [System.Management.Automation.PipelineStoppedException]::new()
        }
        if ($pc.KeyChar -eq [char]27 -and [Console]::KeyAvailable) {
            $endSeq = ''
            while ([Console]::KeyAvailable -and $endSeq.Length -lt 10) {
                $en = [Console]::ReadKey($true)
                $endSeq += $en.KeyChar
                if ($en.KeyChar -match '[~A-Za-z]') { break }
            }
            if ($endSeq -eq '[201~') {
                $endSeen = $true
            } else {
                # Unknown ESC sequence inside the paste body — keep the
                # bytes; the control-char check below will flag the paste
                # as unsafe and the caller will reject.
                [void]$pasteBuf.Append([char]27)
                [void]$pasteBuf.Append($endSeq)
            }
        } else {
            [void]$pasteBuf.Append($pc.KeyChar)
        }
    }
    $text = $pasteBuf.ToString()
    # Trailing CR/LF stripping: clipboard sources commonly copy with a
    # trailing newline, and the natural UX is "paste, then submit." We
    # treat the trailing newline as the user's Enter press; the caller
    # decides whether to auto-commit based on its own validation state.
    $trailingNewline = $false
    if ($text -match '[\r\n]+$') {
        $trailingNewline = $true
        $text = $text -replace '[\r\n]+$', ''
    }
    $hasControlChars = ($text -match '[\x00-\x1F\x7F]')
    return [PSCustomObject]@{
        Kind            = 'Paste'
        Text            = $text
        TrailingNewline = $trailingNewline
        HasControlChars = $hasControlChars
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

# --- Internal helpers used by Write-TuiBox ---
# Module-private (not exported). Hoisted out of Write-TuiBox so they're defined
# once at module load instead of re-created on every render call.

# Truncate to a maximum number of display cells while preserving ANSI escape
# sequences inline. ANSI CSI sequences contribute zero cells but are emitted
# as-is so inline styling survives the truncation. East-Asian Wide / Fullwidth
# characters count as 2 cells (same range table as Get-DisplayWidth); if the
# next character would push past $maxVisibleLen the loop stops, so the result
# may be 1 cell short of the limit when truncation lands on a wide char.
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
            continue
        }
        # Cell-width of the next code point. Mirrors Get-DisplayWidth so the
        # two stay consistent; kept inline to avoid per-char function-call
        # overhead in the render hot path.
        if ([char]::IsHighSurrogate($s[$i]) -and ($i + 1) -lt $s.Length -and [char]::IsLowSurrogate($s[$i + 1])) {
            $cp = [char]::ConvertToUtf32($s, $i)
            $charLen = 2
        } else {
            $cp = [int][char]$s[$i]
            $charLen = 1
        }
        if ($cp -lt 0x20 -or ($cp -ge 0x7F -and $cp -lt 0xA0)) {
            $i += $charLen
            continue
        }
        $cellWidth = if (
            ($cp -ge 0x1100  -and $cp -le 0x115F) -or
            ($cp -ge 0x2E80  -and $cp -le 0x303E) -or
            ($cp -ge 0x3041  -and $cp -le 0x33FF) -or
            ($cp -ge 0x3400  -and $cp -le 0x4DBF) -or
            ($cp -ge 0x4E00  -and $cp -le 0x9FFF) -or
            ($cp -ge 0xA000  -and $cp -le 0xA4CF) -or
            ($cp -ge 0xAC00  -and $cp -le 0xD7A3) -or
            ($cp -ge 0xF900  -and $cp -le 0xFAFF) -or
            ($cp -ge 0xFE30  -and $cp -le 0xFE4F) -or
            ($cp -ge 0xFF00  -and $cp -le 0xFF60) -or
            ($cp -ge 0xFFE0  -and $cp -le 0xFFE6) -or
            ($cp -ge 0x1F300 -and $cp -le 0x1F64F) -or
            ($cp -ge 0x1F900 -and $cp -le 0x1F9FF) -or
            ($cp -ge 0x20000 -and $cp -le 0x3FFFD)
        ) { 2 } else { 1 }
        if ($visibleCount + $cellWidth -gt $maxVisibleLen) { break }
        [void]$sb.Append($s.Substring($i, $charLen))
        $visibleCount += $cellWidth
        $i += $charLen
    }
    return $sb.ToString()
}

function Format-TuiColumn {
    <#
    .SYNOPSIS
        Justify and pad a string into a fixed-width display cell.
    .DESCRIPTION
        Fits $Text into a cell exactly $Width display cells wide, measured the
        same way the rest of the module measures (East-Asian Wide/Fullwidth =
        2 cells, ANSI CSI sequences = 0 cells) via Get-DisplayWidth. Shorter
        text is padded with $PadChar on the side(s) implied by $Justify; longer
        text is truncated on visible characters (preserving inline ANSI) and the
        $Ellipsis is appended so the result still measures exactly $Width.

        This is the shared alignment primitive for column layouts — e.g. the
        value column in Invoke-NestedMenu — so callers don't reimplement
        width-aware padding. It is a pure function with no host output.
    .PARAMETER Text
        The content to fit. May contain inline ANSI styling.
    .PARAMETER Width
        Target cell width in display columns. Values <= 0 return ''.
    .PARAMETER Justify
        Left (default), Right, or Center.
    .PARAMETER PadChar
        Single character used for padding. Default ' '. Assumed 1 cell wide.
    .PARAMETER Ellipsis
        Appended when $Text is truncated. Default '…'. Pass '' to hard-cut
        without a marker. An ellipsis wider than $Width is itself trimmed.
    .EXAMPLE
        PS> Format-TuiColumn -Text 'Theme' -Width 12
        'Theme       '
    .EXAMPLE
        PS> Format-TuiColumn -Text '42' -Width 6 -Justify Right
        '    42'
    .OUTPUTS
        [string] exactly $Width display cells wide (or '' when $Width <= 0).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory = $true, Position = 1)]
        [int]$Width,

        [ValidateSet('Left', 'Right', 'Center')]
        [string]$Justify = 'Left',

        [string]$PadChar = ' ',

        [string]$Ellipsis = "$([char]0x2026)"
    )

    if ($Width -le 0) { return '' }
    if ([string]::IsNullOrEmpty($PadChar)) { $PadChar = ' ' }
    # Multiplying a [char] doesn't repeat in PowerShell; use a 1-char string.
    $pc = [string]$PadChar[0]

    $visible = Get-DisplayWidth $Text

    if ($visible -gt $Width) {
        # Truncate, leaving room for the ellipsis, then reset any open ANSI
        # styling so trailing padding / borders render clean.
        $ellWidth = Get-DisplayWidth $Ellipsis
        if ($ellWidth -ge $Width) {
            # Ellipsis alone doesn't fit — trim it to width and drop the text.
            return Get-VisibleSubstring $Ellipsis $Width
        }
        $kept = Get-VisibleSubstring $Text ($Width - $ellWidth)
        $result = "$kept$Ellipsis`e[0m"
        # The kept slice may land 1 cell short on a wide-char boundary; pad it.
        $shortfall = $Width - (Get-DisplayWidth $result)
        if ($shortfall -gt 0) { $result += ($pc * $shortfall) }
        return $result
    }

    $pad = $Width - $visible
    switch ($Justify) {
        'Right'  { return (($pc * $pad) + $Text) }
        'Center' {
            $left  = [int][Math]::Floor($pad / 2)
            $right = $pad - $left
            return (($pc * $left) + $Text + ($pc * $right))
        }
        default  { return ($Text + ($pc * $pad)) }
    }
}

function Format-TuiWrap {
    <#
    .SYNOPSIS
        Display-width-aware greedy word wrap into a list of lines.
    .DESCRIPTION
        Wraps $Text to lines no wider than $Width display cells, breaking on
        whitespace. Words longer than the available width are hard-split on a
        cell boundary via Get-VisibleSubstring. With -HangingIndent, every line
        after the first is left-padded by that many spaces, so wrapped text can
        align past a leading title. -MaxLines caps the number of returned lines;
        when content remains past the cap, the last kept line is truncated with
        an ellipsis.

        Width is measured like the rest of the module (CJK = 2 cells, ANSI = 0).
        Pure function, no host output. Returns @() for empty input.
    .PARAMETER Text
        The content to wrap. Existing newlines are treated as hard breaks.
    .PARAMETER Width
        Maximum line width in display cells. Values <= 0 return @().
    .PARAMETER HangingIndent
        Cells of left padding applied to lines 2..n. Default 0.
    .PARAMETER MaxLines
        Maximum lines to return. Default 0 = unlimited.
    .OUTPUTS
        [string[]] wrapped lines.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory = $true, Position = 1)]
        [int]$Width,

        [int]$HangingIndent = 0,

        [int]$MaxLines = 0
    )

    if ($Width -le 0 -or [string]::IsNullOrEmpty($Text)) { return @() }
    if ($HangingIndent -lt 0) { $HangingIndent = 0 }

    $lines = [System.Collections.Generic.List[string]]::new()
    $indent = ' ' * $HangingIndent

    # Per-line budget: first line gets the full width; continuation lines lose
    # the hanging indent. Guard against a too-deep indent leaving no room.
    $contWidth = $Width - $HangingIndent
    if ($contWidth -lt 1) { $contWidth = 1 }

    foreach ($hardLine in ($Text -split "`r?`n")) {
        $words = @($hardLine -split '\s+' | Where-Object { $_ -ne '' })
        if ($words.Count -eq 0) { $lines.Add(''); continue }

        $current = ''
        foreach ($word in $words) {
            $isFirst = ($lines.Count -eq 0)
            $budget  = if ($isFirst) { $Width } else { $contWidth }

            $candidate = if ($current -eq '') { $word } else { "$current $word" }
            if ((Get-DisplayWidth $candidate) -le $budget) {
                $current = $candidate
                continue
            }

            # Flush the current line if it holds anything.
            if ($current -ne '') {
                $lines.Add($(if ($lines.Count -eq 0) { $current } else { "$indent$current" }))
                $current = ''
            }

            # The word may still be wider than a whole line — hard-split it.
            $remaining = $word
            while ((Get-DisplayWidth $remaining) -gt $budget) {
                $slice = Get-VisibleSubstring $remaining $budget
                if ($slice -eq '') { break } # safety against zero progress
                $lines.Add($(if ($lines.Count -eq 0) { $slice } else { "$indent$slice" }))
                $remaining = $remaining.Substring($slice.Length)
                $budget = $contWidth
            }
            $current = $remaining
        }
        if ($current -ne '') {
            $lines.Add($(if ($lines.Count -eq 0) { $current } else { "$indent$current" }))
        }
    }

    # Clamp to MaxLines, ellipsizing the final kept line so the truncation is
    # visible. The last kept line already fits its budget; strip the hanging
    # indent, trim to leave room for the ellipsis, then re-add the indent.
    if ($MaxLines -gt 0 -and $lines.Count -gt $MaxLines) {
        $kept = [string[]]($lines[0..($MaxLines - 1)])
        $isFirstLine = ($MaxLines -eq 1)
        $budget = if ($isFirstLine) { $Width } else { $contWidth }
        $body = if ($isFirstLine) { $kept[-1] } else { $kept[-1].Substring([Math]::Min($HangingIndent, $kept[-1].Length)) }
        $trimmed = (Get-VisibleSubstring $body ([Math]::Max(1, $budget - 1))).TrimEnd() + "$([char]0x2026)"
        $kept[-1] = if ($isFirstLine) { $trimmed } else { "$indent$trimmed" }
        return $kept
    }

    return $lines.ToArray()
}

function Write-TuiBox {
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
    .PARAMETER Note
        Optional lines drawn between the body and the footer, fenced by rules
        on both sides so the section reads as a distinct band (e.g. a help /
        tooltip strip). Under -Border the rules are tee connectors; under
        -SectionRules they are plain rules. The band's lower fence is shared
        with the footer's leading rule when a Footer is present.
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
    .PARAMETER PassThru
        Emit the rendered line count to the pipeline. Without this switch
        the function returns nothing — matching the convention for Write-*
        functions whose primary purpose is side effects (cf. Add-Member,
        Set-ItemProperty). The internal callers Get-PaginatedSelection and
        Invoke-NestedMenu use the count for cursor management and so pass
        -PassThru; standalone callers usually don't care and can omit it.
    .OUTPUTS
        None by default, or [int] line count under -PassThru.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Header,
        [Parameter(Mandatory = $true)]
        [string[]]$Body,
        [string[]]$Footer,
        [string[]]$Note,
        [switch]$Border,
        [int]$MinWidth = 0,
        [int]$MaxWidth = 0,
        [int]$X = -1,
        [int]$Y = -1,
        [switch]$SectionRules,
        [switch]$Ascii,
        [switch]$PassThru
    )

    # Resolve effective ASCII mode: explicit switch > $env:PWSHTUI_ASCII > rich.
    $asciiOn = if ($PSBoundParameters.ContainsKey('Ascii')) { [bool]$Ascii } else { $script:_AsciiMode }
    $g = Get-Glyphs $asciiOn

    # A Note of @('') (a single blank line, used to reserve a band's height) is
    # falsy under `if ($Note)` because PowerShell unwraps the one-element array
    # to [bool]''. Test element count instead so an explicit blank band renders.
    $hasNote = ($null -ne $Note -and $Note.Count -gt 0)

    $allLines = @()
    if ($Header) { $allLines += $Header }
    $allLines += $Body
    if ($hasNote) { $allLines += $Note }
    if ($Footer) { $allLines += $Footer }

    # Calculate required width. Measured in display cells, so CJK content
    # gets a wider box rather than overflowing the right border.
    $maxContentLen = $MinWidth
    foreach ($line in $allLines) {
        $len = Get-DisplayWidth $line
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
            $visibleLen = Get-DisplayWidth $line
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

    if ($hasNote) {
        if ($Border) { $frame.Add("$($g.BorderTeeL)$horiz$($g.BorderTeeR)") }
        elseif ($SectionRules) { $frame.Add($plainRule) }
        & $addSectionLines $Note
        # Close the band when no Footer follows to provide its lower fence.
        if (-not $Footer) {
            if ($Border) { $frame.Add("$($g.BorderTeeL)$horiz$($g.BorderTeeR)") }
            elseif ($SectionRules) { $frame.Add($plainRule) }
        }
    }

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

    if ($PassThru) { return $frame.Count }
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
        Esc cancels. With -Searchable, input is split into two modes —
        selection (arrows/Enter/Esc, Space toggles in MultiSelect) and
        search (typing feeds the filter buffer). Tab toggles between them;
        typing any printable character from selection mode also enters
        search mode. From search mode, Enter/Esc/Tab/arrow keys return to
        selection mode with the first matching row highlighted (they do not
        confirm or cancel — press the same key again from selection mode
        to do that).
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
        Enable multi-selection. Space toggles the current row's selection;
        Enter returns an array of selected items in original input order.
        Selection state persists across search filter changes. Esc cancels
        and returns $null. Enter with no toggled items returns an empty
        array (distinguishable from $null cancel).
    .PARAMETER MinSelections
        Minimum number of items required before -MultiSelect Enter will
        confirm. Defaults to 0 (no minimum). Clamped to the item count if
        higher; clamped to MaxSelections if higher than that. Ignored
        when -MultiSelect is not set.
    .PARAMETER MaxSelections
        Maximum number of items the user may toggle in -MultiSelect mode.
        Defaults to the item count (no maximum). Clamped to the item count
        if higher. Attempts to toggle on an item beyond this limit are
        silently ignored; items can always be toggled off. Ignored when
        -MultiSelect is not set.
    .PARAMETER PreSelected
        Items to pre-check on open. Ignored unless -MultiSelect is set.
        Identity matches the toggle behavior: reference equality for
        objects, value equality for strings — pass the same item references
        you got from -Items (typical "edit my current selections" flow).
        Items not present in -Items are silently dropped. If -MaxSelections
        is in effect, pre-selection is capped at that limit (in PreSelected
        order); the cap is a script-side misconfig the caller can detect
        from the returned array.
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

        [int]$MinSelections = 0,

        [int]$MaxSelections = [int]::MaxValue,

        [object[]]$PreSelected,

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

    # Clamp Min/MaxSelections to the available item count — a developer
    # passing values larger than the input is a script-side misconfig the
    # caller can detect from the returned array; the UI never advertises an
    # impossible minimum.
    $effectiveMax = if ($MaxSelections -gt $itemList.Count) { $itemList.Count } else { [Math]::Max(0, $MaxSelections) }
    $effectiveMin = if ($MinSelections -gt $itemList.Count) { $itemList.Count } else { [Math]::Max(0, $MinSelections) }
    if ($effectiveMin -gt $effectiveMax) { $effectiveMin = $effectiveMax }

    # Pre-select items: seed $selectedSet with any -PreSelected entries that
    # appear in $itemList, capped at $effectiveMax. Items not in $itemList
    # are silently dropped (same convention as Read-Choice -PreSelected for
    # out-of-range indices). $itemSet is a lookup so a large $PreSelected
    # against a large $itemList stays O(n+m), not O(n*m).
    if ($MultiSelect -and $PreSelected) {
        $itemSet = [System.Collections.Generic.HashSet[object]]::new()
        foreach ($i in $itemList) { [void]$itemSet.Add($i) }
        foreach ($p in $PreSelected) {
            if ($selectedSet.Count -ge $effectiveMax) { break }
            if ($itemSet.Contains($p)) { [void]$selectedSet.Add($p) }
        }
    }

    # When Searchable is on, input is split into two modes. Selection mode
    # (initial) is where arrows navigate and Enter/Esc/Space act; search mode
    # is where keystrokes feed the filter buffer. The split is the same with
    # or without -MultiSelect — only what Space does in selection mode differs
    # (toggles the current row in MultiSelect; ignored in single-select).
    $inputMode = 'selection'

    # Shared mode-switch action: return to selection mode with the first row
    # highlighted. Used both by Tab (search → selection) and by the exit
    # triggers inside search-mode handling (Enter/Esc/arrow). Dot-sourced so
    # the assignments hit the loop scope, not a child.
    $resetToSelection = {
        $inputMode = 'selection'
        $pageIndex = 0
        $selectedIndex = 0
    }

    # Shared filter refresh used by both the typing-enters-search transition
    # and ongoing keystrokes within search mode. Dot-sourced (. $applyFilter)
    # so it mutates $filteredItems / $previousSearchBuffer / $pageIndex /
    # $selectedIndex in the loop's scope instead of a child scope.
    $applyFilter = {
        if ([string]::IsNullOrEmpty($searchBuffer)) {
            $filteredItems = $itemList
        } else {
            # Incremental narrowing: extending the previous buffer can only
            # remove matches, so scoring the previously filtered set is
            # sufficient. Backspace or replacement falls back to the full list.
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
    }

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

    $raw = Enter-RawConsole -AltScreen:$AltScreen

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
            $inSearchMode = $Searchable -and $inputMode -eq 'search'
            $displayTitle = if ($Searchable) {
                # Show a blinking cursor in the search area while in search
                # mode so the user can tell at a glance which mode they're in.
                # No-color path falls back to a plain underscore.
                $searchCursor = if ($inSearchMode) {
                    if ($noColorOn) { "_" } else { "`e[5m_`e[25m" }
                } else { "" }
                if ($searchBuffer -or $inSearchMode) { "$Title [$($script:_Strings.Footer_Search): $searchBuffer$searchCursor]" }
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

                    # MultiSelect renders the radio glyph + two spaces *outside*
                    # the highlight bar so the marker and spacing remain legible
                    # against the cyan background — only the item text itself
                    # is highlighted.
                    $markerPrefix = if ($MultiSelect) {
                        if ($selectedSet.Contains($item)) { "$($g.RadioOn)  " } else { "$($g.RadioOff)  " }
                    } else { "" }

                    $isRowSelected = ($i -eq $selectedIndex)
                    if ($isRowSelected) {
                        if ($noColorOn) {
                            $body += "$pointer$markerPrefix$displayText"
                        } else {
                            # In search mode the highlight is dimmed (faint
                            # attribute) so the user keeps their place while
                            # selection input is paused. Same shape otherwise.
                            $dim = if ($inSearchMode) { '2;' } else { '' }
                            $body += "`e[${dim}36m$pointer`e[0m$markerPrefix`e[${dim}46;30m$displayText`e[0m"
                        }
                    } else {
                        $body += "$emptyPointer$markerPrefix$displayText"
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
                $countDisplay = "$($selectedSet.Count) $($s.Footer_Selected)"
                # Show min/max only when constrained — keeps the footer quiet
                # for the common unconstrained case.
                if ($effectiveMin -gt 0 -or $effectiveMax -lt $itemList.Count) {
                    $countDisplay = "$countDisplay, min=$effectiveMin max=$effectiveMax"
                }
                if ($inSearchMode) {
                    $footerLines.Add("Tab/Enter/Esc/$($g.ArrowsUpDown)=$($s.Footer_BackToSelection)   ($countDisplay)")
                } else {
                    $tabHint = if ($Searchable) { "   Tab=$($s.Footer_Search)" } else { "" }
                    $footerLines.Add("$($g.ArrowsUpDown) $($s.Footer_Move) $rangeDisplay   Space=$($s.Footer_Toggle) ($countDisplay)$tabHint   Enter=$($s.Footer_Confirm)   Esc=$($s.Footer_Cancel)")
                }
            } else {
                if ($inSearchMode) {
                    $footerLines.Add("Tab/Enter/Esc/$($g.ArrowsUpDown)=$($s.Footer_BackToSelection)")
                } else {
                    $tabHint = if ($Searchable) { "   Tab=$($s.Footer_Search)" } else { "" }
                    $footerLines.Add("$($g.ArrowsUpDown) $($s.Footer_Move) $rangeDisplay$tabHint   Enter=$($s.Footer_Select)   Esc=$($s.Footer_Cancel)")
                }
            }

            $footer = @($footerLines)

            # Draw using UIBox
            $newHeight = Write-TuiBox -Header $header -Body $body -Footer $footer `
                                      -Border:$Border -MinWidth $MinWidth -MaxWidth $MaxWidth -X $X -Y $Y `
                                      -SectionRules -Ascii:$asciiOn -PassThru

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

            # Tab: toggle between search and selection input modes (Searchable
            # only — without search there's nothing to switch to). Same
            # mechanism regardless of -MultiSelect.
            if ($Searchable -and $key.Key -eq 'Tab') {
                if ($inputMode -eq 'search') { . $resetToSelection }
                else { $inputMode = 'search' }
                continue
            }

            # Search mode: keystrokes edit the buffer; navigation, Enter, and
            # Esc all exit back to selection mode (with the first row
            # highlighted) rather than triggering their usual actions. The
            # user has to be in selection mode to confirm or cancel — press
            # the same key again from there.
            if ($inputMode -eq 'search') {
                if ($key.Key -eq 'Backspace') {
                    if ($searchBuffer.Length -gt 0) {
                        $searchBuffer = $searchBuffer.Substring(0, $searchBuffer.Length - 1)
                        . $applyFilter
                    }
                    # Empty-buffer Backspace stays in search mode (no-op).
                } elseif ($key.Key -in 'Enter', 'Escape', 'UpArrow', 'DownArrow', 'LeftArrow', 'RightArrow') {
                    . $resetToSelection
                } elseif ($key.KeyChar -ne [char]0 -and -not [char]::IsControl($key.KeyChar)) {
                    $searchBuffer += $key.KeyChar
                    . $applyFilter
                }
                continue
            }

            # Selection mode + MultiSelect: Space toggles the current row.
            # Done before the typing-enters-search check below so Space never
            # silently leaks into the search buffer.
            if ($MultiSelect -and $key.Key -eq 'Spacebar') {
                if ($currentPageItems.Count -gt 0) {
                    $toggleItem = $currentPageItems[$selectedIndex]
                    if ($selectedSet.Contains($toggleItem)) {
                        [void]$selectedSet.Remove($toggleItem)
                    } elseif ($selectedSet.Count -lt $effectiveMax) {
                        # Block toggle-on at the limit (toggle-off above is
                        # always allowed). Friendlier than accepting it and
                        # then blocking Enter — the user finds out at the
                        # press, not at confirm time.
                        [void]$selectedSet.Add($toggleItem)
                    }
                }
                continue
            }

            # Selection mode + Searchable: any printable other than Space
            # flips into search mode and starts the buffer with that
            # character. Space is excluded so a stray Space press is a no-op
            # in single-select (and was already consumed above for
            # MultiSelect) — it can never accidentally start a search with a
            # leading space.
            if ($Searchable -and $key.KeyChar -ne [char]0 -and -not [char]::IsControl($key.KeyChar) -and $key.KeyChar -ne ' ') {
                $inputMode = 'search'
                $searchBuffer += $key.KeyChar
                . $applyFilter
                continue
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
                        # Confirm only when the selection count satisfies the
                        # configured min/max. Out-of-range Enter is silently
                        # ignored — the count is visible in the footer.
                        if ($selectedSet.Count -ge $effectiveMin -and $selectedSet.Count -le $effectiveMax) {
                            # Wrapped in a single-element array via the unary
                            # comma so PowerShell preserves array shape even
                            # when 0 or 1 items are selected.
                            $result = ,@($itemList | Where-Object { $selectedSet.Contains($_) })
                            $running = $false
                        }
                    } else {
                        if ($filteredItems.Count -gt 0) {
                            $result = $filteredItems[$startIdx + $selectedIndex]
                        }
                        # Preserves prior behavior: in single-select, Enter
                        # always exits — with no matches it returns $null (a
                        # cancel-equivalent), matching the original contract.
                        $running = $false
                    }
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

        Exit-RawConsole $raw

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
    
    $raw = Enter-RawConsole -BracketedPaste

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
            $evt = Read-KeyOrPaste

            if ($evt.Kind -eq 'Discard') {
                # No-op — let the loop redraw and re-read.
            } elseif ($evt.Kind -eq 'Paste') {
                # Sanitation: reject the whole paste if it contains any
                # control character in the body. Same logic as Read-Password
                # — silent partial application is worse than a visible reject.
                if ($evt.HasControlChars) {
                    Write-Notice $script:_Strings.Notice_PasteControlChars -NoColor:$noColorOn
                } else {
                    # Apply each pasted char through the same per-slot
                    # validation pipeline as typed input. Chars that don't
                    # match the current slot's type are silently skipped —
                    # this lets users paste "555-1234" into a phone mask and
                    # have the dash filtered out, matching how typed-char
                    # rejection already works.
                    foreach ($pc in $evt.Text.GetEnumerator()) {
                        if ($cursor -ge $slots.Count) { break }
                        $candidate = $pc
                        $expectedType = $slots[$cursor].Type
                        if ($expectedType -eq 'X' -and $candidate.ToString() -match '^[0-9a-fA-F]$') { $candidate = [char]::ToUpper($candidate) }
                        if ($expectedType -eq 'x' -and $candidate.ToString() -match '^[0-9a-fA-F]$') { $candidate = [char]::ToLower($candidate) }
                        $temp = [System.Collections.Generic.List[char]]::new([char[]]$rawInput.ToArray())
                        if ($cursor -eq $temp.Count) {
                            $temp.Add($candidate)
                        } else {
                            $temp[$cursor] = $candidate
                        }
                        if (& $checkValid $temp) {
                            $rawInput = $temp
                            $cursor++
                        }
                    }
                    if ($evt.TrailingNewline -and ($AllowIncomplete -or $rawInput.Count -eq $slots.Count)) {
                        $running = $false
                    }
                }
            } else {
                $key = $evt.Key
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
        }

        # Final Draw to remove highlight
        Write-Host "`r$Prompt $displayStr`e[K"
    } finally {
        Exit-RawConsole $raw

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

function Get-PasswordStrength {
    # Internal: derive a strength record from a class-tracking list —
    # markers only ('L' lower, 'U' upper, 'D' digit, 'S' other), never the
    # actual characters. Read-Password maintains this list in parallel
    # with the SecureString so strength can be scored without ever
    # unwrapping the SecureString to plaintext.
    #
    # Score model (0-6): one point each for length>=8, >=12, >=16, and one
    # each for >=2, >=3, >=4 distinct character classes. Bands:
    #   0-1: Weak    2-3: Fair    4: Good    5-6: Strong
    # Deliberately simple — meant as a visible hint and a programmable
    # metadata bucket, not a cryptographic strength guarantee.
    #
    # Returns a PSCustomObject so callers can render the Label themselves,
    # branch on the Score, gate on Length/Classes, etc. Color is included
    # for the in-function render path but harmless for downstream callers.
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[char]]$ClassList
    )
    $length = $ClassList.Count
    if ($length -eq 0) {
        return [PSCustomObject]@{
            Label = ''; Score = 0; Length = 0; Classes = 0; Color = 'White'
        }
    }
    $hasL = $ClassList -contains 'L'
    $hasU = $ClassList -contains 'U'
    $hasD = $ClassList -contains 'D'
    $hasS = $ClassList -contains 'S'
    $classCount = [int]$hasL + [int]$hasU + [int]$hasD + [int]$hasS

    $score = 0
    if ($length -ge 8)       { $score++ }
    if ($length -ge 12)      { $score++ }
    if ($length -ge 16)      { $score++ }
    if ($classCount -ge 2)   { $score++ }
    if ($classCount -ge 3)   { $score++ }
    if ($classCount -ge 4)   { $score++ }

    $label = ''
    $color = 'White'
    if     ($score -le 1) { $label = 'Weak';   $color = 'Red' }
    elseif ($score -le 3) { $label = 'Fair';   $color = 'Yellow' }
    elseif ($score -le 4) { $label = 'Good';   $color = 'Cyan' }
    else                  { $label = 'Strong'; $color = 'Green' }

    return [PSCustomObject]@{
        Label   = $label
        Score   = $score
        Length  = $length
        Classes = $classCount
        Color   = $color
    }
}

function Read-Password {
    <#
    .SYNOPSIS
        Prompt for a password without echoing the characters.
    .DESCRIPTION
        Reads a password from the console and returns a [SecureString] by
        default. Each keystroke is rendered as a mask character (or hidden
        entirely with -HideTyping); Backspace deletes the last character;
        Enter submits; Escape cancels.

        Cursor navigation (arrow keys, Home/End) is intentionally disabled,
        matching the conventional password-field UX.
    .PARAMETER Prompt
        Label shown before the password field. Default 'Password:'.
    .PARAMETER MaskChar
        Character displayed for each typed character. Default '*'.
    .PARAMETER HideTyping
        Show nothing as the user types — not even a mask character. Hides
        the password length from observers.
    .PARAMETER MinLength
        Minimum length required before Enter is accepted. Default 1.
    .PARAMETER MaxLength
        Maximum length. Additional keystrokes are ignored once reached.
        0 (default) means unbounded.
    .PARAMETER Confirm
        Prompt twice and require both entries to match before returning.
    .PARAMETER ConfirmPrompt
        Label for the confirmation field. Default 'Confirm password:'.
    .PARAMETER MaxAttempts
        Maximum confirmation attempts before giving up and returning $null.
        Default 3.
    .PARAMETER AsPlainText
        Return a [string] instead of a [SecureString]. The plain text lives
        in managed memory and may surface in debuggers, crash dumps, or
        process inspection — prefer the default SecureString when possible.
    .PARAMETER ShowStrength
        Append a live strength indicator (Weak / Fair / Good / Strong) to
        the right of the masked input. Useful when prompting the user to
        *create* a password — gives immediate feedback as they type. Score
        is computed from length thresholds (8 / 12 / 16) and character-
        class diversity (lower / upper / digit / symbol) without ever
        unwrapping the SecureString — a parallel marker-only list (e.g.
        'L','U','D','S' rather than the actual chars) is maintained in
        sync with the SecureString. Only shown on the first prompt; the
        -Confirm second prompt suppresses it (re-typing has no new
        strength to convey).
    .PARAMETER StrengthVariable
        Name (no `$`) of a variable in the caller's scope to receive the
        final strength record as a [PSCustomObject] with fields:
        Label / Score / Length / Classes / Color. Mirrors -OutVariable /
        -ErrorVariable / -ElapsedVariable convention. Independent of
        -ShowStrength: -ShowStrength controls on-screen display while
        -StrengthVariable controls programmable capture. Useful for
        callers that want to gate downstream policy on score (e.g. reject
        anything below 'Good' from being persisted to a password store).
    .EXAMPLE
        PS> $pw = Read-Password
        Reads a password into a SecureString.
    .EXAMPLE
        PS> $pw = Read-Password -Confirm -MinLength 12
        Asks twice and requires at least 12 characters.
    .OUTPUTS
        [SecureString] by default, [string] with -AsPlainText, $null if
        cancelled or confirmation attempts are exhausted.
    #>
    [CmdletBinding()]
    [OutputType([System.Security.SecureString], [string])]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = 'Password:',

        [Parameter(Position = 1)]
        [char]$MaskChar = '*',

        [switch]$HideTyping,

        [int]$MinLength = 1,

        [int]$MaxLength = 0,

        [switch]$Confirm,

        [string]$ConfirmPrompt = 'Confirm password:',

        [int]$MaxAttempts = 3,

        [switch]$AsPlainText,

        [switch]$ShowStrength,

        [string]$StrengthVariable,

        [switch]$NoColor
    )

    Assert-InteractiveHost 'Read-Password'

    if ($MinLength -lt 0) { $MinLength = 0 }
    if ($MaxLength -lt 0) { $MaxLength = 0 }
    if ($MaxLength -gt 0 -and $MaxLength -lt $MinLength) {
        throw "Read-Password: -MaxLength ($MaxLength) cannot be less than -MinLength ($MinLength)."
    }
    if ($MaxAttempts -lt 1) { $MaxAttempts = 1 }

    # Resolve effective NoColor: explicit switch > env var > colored default.
    $noColorOn = if ($PSBoundParameters.ContainsKey('NoColor')) { [bool]$NoColor } else { $script:_NoColor }

    # Inner reader: prompts once, returns a SecureString or $null if Escape.
    # Stores characters directly in a SecureString from the first keystroke
    # so plaintext never lives in a managed List[char]/string for longer than
    # the BSTR unwrap window in -AsPlainText / -Confirm comparison.
    $readOne = {
        param([string]$label, [bool]$showStrengthForThis)

        $sec = [System.Security.SecureString]::new()
        # Marker-only shadow of the SecureString — one char per slot,
        # 'L'/'U'/'D'/'S' (lower/upper/digit/symbol-or-other). Mutated in
        # lockstep with $sec on every append/remove. Lets Get-PasswordStrength
        # score the password without unwrapping the SecureString to plaintext.
        $classes = [System.Collections.Generic.List[char]]::new()
        $running = $true
        $cancelled = $false

        # Bracketed paste matters especially here: silent corruption of a pasted
        # password (e.g. an embedded newline truncating the buffer) would mismatch
        # -Confirm in a way that *succeeds* if both pastes are mangled identically,
        # locking the user out of whatever they just provisioned.
        $raw = Enter-RawConsole -BracketedPaste

        try {
            while ($running) {
                $len = $sec.Length

                if ($noColorOn) {
                    Write-Host "`r$label " -NoNewline
                } else {
                    Write-Host "`r$label " -NoNewline -ForegroundColor Cyan
                }

                if (-not $HideTyping -and $len -gt 0) {
                    Write-Host ([string]::new([char]$MaskChar, $len)) -NoNewline
                }

                # Trailing cursor block so the input position is visible even
                # with a hidden hardware cursor.
                if ($noColorOn) {
                    Write-Host '_' -NoNewline
                } else {
                    Write-Host ' ' -NoNewline -BackgroundColor Cyan
                }

                # Strength indicator (after the cursor block so the typing
                # position stays visually adjacent to the chars). Skipped on
                # the -Confirm second prompt and when the buffer is empty.
                if ($showStrengthForThis -and $classes.Count -gt 0) {
                    $strength = Get-PasswordStrength -ClassList $classes
                    if ($noColorOn) {
                        Write-Host "  ($($strength.Label))" -NoNewline
                    } else {
                        Write-Host "  ($($strength.Label))" -NoNewline -ForegroundColor $strength.Color
                    }
                }

                Write-Host "`e[K" -NoNewline # Clear to end of line

                $evt = Read-KeyOrPaste

                if ($evt.Kind -eq 'Discard') {
                    # No-op — let the loop redraw and re-read.
                } elseif ($evt.Kind -eq 'Paste') {
                    # Sanitation policy: any control character in the body is
                    # a hard reject. Silently dropping or keeping them risks
                    # the stored password drifting from what the user thinks
                    # they pasted, and with -Confirm an identical mangling on
                    # both pastes would even validate — the worst failure.
                    if ($evt.HasControlChars) {
                        Write-Notice $script:_Strings.Notice_PasteControlChars -NoColor:$noColorOn
                    } else {
                        foreach ($pc in $evt.Text.GetEnumerator()) {
                            if ($MaxLength -eq 0 -or $sec.Length -lt $MaxLength) {
                                $sec.AppendChar($pc)
                                # Mirror into the class-tracking list. We
                                # store only the *class* of each char — the
                                # plaintext never lives outside the SecureString.
                                $cls = if ([char]::IsLower($pc)) { 'L' }
                                       elseif ([char]::IsUpper($pc)) { 'U' }
                                       elseif ([char]::IsDigit($pc)) { 'D' }
                                       else { 'S' }
                                $classes.Add($cls)
                            }
                        }
                        if ($evt.TrailingNewline -and $sec.Length -ge $MinLength) {
                            $running = $false
                        }
                    }
                } else {
                    $key = $evt.Key
                    if (Test-ControlC $key) {
                        throw [System.Management.Automation.PipelineStoppedException]::new()
                    } elseif ($key.Key -eq 'Enter') {
                        if ($len -ge $MinLength) { $running = $false }
                    } elseif ($key.Key -eq 'Escape') {
                        $cancelled = $true
                        $running = $false
                    } elseif ($key.Key -eq 'Backspace') {
                        if ($len -gt 0) {
                            $sec.RemoveAt($len - 1)
                            $classes.RemoveAt($classes.Count - 1)
                        }
                    } else {
                        $char = $key.KeyChar
                        if (-not [char]::IsControl($char)) {
                            if ($MaxLength -eq 0 -or $len -lt $MaxLength) {
                                $sec.AppendChar($char)
                                $cls = if ([char]::IsLower($char)) { 'L' }
                                       elseif ([char]::IsUpper($char)) { 'U' }
                                       elseif ([char]::IsDigit($char)) { 'D' }
                                       else { 'S' }
                                $classes.Add($cls)
                            }
                        }
                    }
                }
            }

            # Final draw: replace the cursor block with a clean line so the
            # confirmation entry (or any following output) starts cleanly.
            $finalDisplay = if ($HideTyping) { '' } else { [string]::new([char]$MaskChar, $sec.Length) }
            Write-Host "`r$label $finalDisplay`e[K"
        } finally {
            Exit-RawConsole $raw
            Write-Host ""
        }

        if ($cancelled) {
            $sec.Dispose()
            return $null
        }

        $sec.MakeReadOnly()
        # Bubble the class list out alongside the SecureString so the outer
        # function can compute / expose strength without re-reading $sec.
        return [PSCustomObject]@{ Sec = $sec; Classes = $classes }
    }

    # Compare two SecureStrings via short-lived BSTR unwrap. The .NET string
    # produced by PtrToStringBSTR sits in managed memory and cannot be zeroed
    # — a fundamental SecureString limitation in .NET — but the BSTRs
    # themselves are zeroed in finally.
    $compareSecure = {
        param([System.Security.SecureString]$a, [System.Security.SecureString]$b)
        if ($a.Length -ne $b.Length) { return $false }
        $bstrA = [IntPtr]::Zero
        $bstrB = [IntPtr]::Zero
        try {
            $bstrA = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($a)
            $bstrB = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($b)
            $strA = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstrA)
            $strB = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstrB)
            return [string]::Equals($strA, $strB, [StringComparison]::Ordinal)
        } finally {
            if ($bstrA -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrA) }
            if ($bstrB -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrB) }
        }
    }

    $firstResult = & $readOne $Prompt $ShowStrength
    if ($null -eq $firstResult) { return $null }
    $first = $firstResult.Sec
    $firstClasses = $firstResult.Classes

    if ($Confirm) {
        $attempt = 0
        $confirmed = $false
        while (-not $confirmed) {
            # Strength indicator deliberately suppressed on the confirm
            # prompt — the user has already seen the score for what they
            # typed, and showing it on a re-type would be misleading
            # (different score = typo, but we already catch that via the
            # comparison below).
            $secondResult = & $readOne $ConfirmPrompt $false
            if ($null -eq $secondResult) {
                $first.Dispose()
                return $null
            }
            $second = $secondResult.Sec
            if (& $compareSecure $first $second) {
                $second.Dispose()
                $confirmed = $true
                break
            }
            $second.Dispose()
            $attempt++
            Write-Notice $script:_Strings.Notice_PasswordMismatch -NoColor:$noColorOn
            if ($attempt -ge $MaxAttempts) {
                $first.Dispose()
                return $null
            }
        }
    }

    # Expose the strength record to the caller if requested. Cross-module
    # scope handled via $PSCmdlet.SessionState.PSVariable.Set — same trick
    # as Show-Spinner -ElapsedVariable, because Set-Variable -Scope 1 from
    # a module function lands in module scope, not the caller's.
    if ($StrengthVariable) {
        $strengthRecord = Get-PasswordStrength -ClassList $firstClasses
        $PSCmdlet.SessionState.PSVariable.Set($StrengthVariable, $strengthRecord)
    }

    if ($AsPlainText) {
        $bstr = [IntPtr]::Zero
        try {
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($first)
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        } finally {
            if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
            $first.Dispose()
        }
    }

    return $first
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

    $raw = Enter-RawConsole -BracketedPaste

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
            $evt = Read-KeyOrPaste

            if ($evt.Kind -eq 'Discard') {
                # No-op — let the loop redraw and re-read.
            } elseif ($evt.Kind -eq 'Paste') {
                # Sanitation: reject the whole paste if it contains any
                # control character in the body. Same rule as Read-Password /
                # Read-MaskedInput — fail visibly rather than silently mangle.
                if ($evt.HasControlChars) {
                    Write-Notice $script:_Strings.Notice_PasteControlChars -NoColor:$noColorOn
                } else {
                    foreach ($pc in $evt.Text.GetEnumerator()) {
                        $rawInput.Insert($cursor, $pc)
                        $cursor++
                    }
                    # Trailing newline acts like Enter — auto-submit if the
                    # buffer matches the pattern (or is empty under -AllowEmpty).
                    if ($evt.TrailingNewline) {
                        $newStr = -join $rawInput
                        $stillValid = ($newStr -match $Pattern)
                        if ($AllowEmpty -and $newStr.Length -eq 0) { $stillValid = $true }
                        if ($stillValid) { $running = $false }
                    }
                }
            } else {
                $key = $evt.Key
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
        }

        $finalStr = -join $rawInput
        Write-Host "`r$Prompt $finalStr`e[K"
    } finally {
        Exit-RawConsole $raw

        # Ensure the terminal prompt drops to a clean line on exit
        Write-Host ""
    }

    if ($finalStr.Length -eq 0 -and -not $AllowEmpty) {
        return $null
    }

    return $finalStr
}

function Format-NumberValue {
    # Internal: render a [decimal] for display. "N{Precision}" uses culture
    # thousands separators; "F{Precision}" omits them. Decimal formatting
    # is used throughout so values stay exact (no IEEE drift).
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][decimal]$Value,
        [Parameter(Mandatory)][int]$Precision,
        [switch]$ThousandsSeparator,
        [System.Globalization.CultureInfo]$Culture = ([System.Globalization.CultureInfo]::CurrentCulture)
    )
    $fmt = if ($ThousandsSeparator) { "N$Precision" } else { "F$Precision" }
    return $Value.ToString($fmt, $Culture)
}

function ConvertTo-NumberValue {
    # Internal: parse a typed/pasted buffer into a bounded [decimal]. Returns
    # @{ Ok = $bool; Value = [decimal]; Reason = 'empty'|'unparseable'|'precision'|'range'|'' }.
    # Thousands-separator characters are stripped before TryParse so input is
    # accepted regardless of whether the user typed them. Excess decimal
    # places (beyond -Precision) are rejected — silent rounding would let
    # the rendered value diverge from what the user typed.
    #
    # SI multipliers (case-sensitive): a trailing 'k', 'M', 'G', or 'T'
    # multiplies the parsed value by 10^3, 10^6, 10^9, or 10^12 respectively.
    # "1.5M" → 1500000, "2k" → 2000. When an SI suffix is present the
    # buffer-text precision check is skipped: "1.5k" is a perfectly valid
    # integer (1500) under -Precision 0 even though the literal text has a
    # dot. Precision is instead enforced post-multiplication via modulo
    # against the quantum grid, so "1.555k" (1555) passes at Precision=0
    # but "1.5555k" (1555.5) does not.
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Buffer,
        [Parameter(Mandatory)][int]$Precision,
        [decimal]$Min = [decimal]::MinValue,
        [decimal]$Max = [decimal]::MaxValue,
        [System.Globalization.CultureInfo]$Culture = ([System.Globalization.CultureInfo]::CurrentCulture)
    )
    if ([string]::IsNullOrEmpty($Buffer)) {
        return @{ Ok = $false; Value = [decimal]0; Reason = 'empty' }
    }
    $sep = $Culture.NumberFormat.NumberGroupSeparator
    $dot = $Culture.NumberFormat.NumberDecimalSeparator
    $stripped = $Buffer.Replace($sep, '')

    # Strip a trailing single SI suffix and remember the multiplier.
    # Case-sensitive: lowercase k for kilo (matches SI convention), uppercase
    # M/G/T for mega/giga/tera. -creplace + -cmatch don't help here because
    # we need to BRANCH on the matched char; switch with -CaseSensitive is
    # the readable form.
    $multiplier = [decimal]1
    $siApplied = $false
    if ($stripped.Length -ge 2) {
        $lastChar = $stripped[$stripped.Length - 1]
        switch -CaseSensitive ([string]$lastChar) {
            'k' { $multiplier = [decimal]1000;          $siApplied = $true }
            'M' { $multiplier = [decimal]1000000;       $siApplied = $true }
            'G' { $multiplier = [decimal]1000000000;    $siApplied = $true }
            'T' { $multiplier = [decimal]1000000000000; $siApplied = $true }
        }
        if ($siApplied) {
            $stripped = $stripped.Substring(0, $stripped.Length - 1)
        }
    }

    $styles = [System.Globalization.NumberStyles]::Float -bor [System.Globalization.NumberStyles]::AllowThousands
    $parsed = [decimal]0
    if (-not [decimal]::TryParse($stripped, $styles, $Culture, [ref]$parsed)) {
        return @{ Ok = $false; Value = [decimal]0; Reason = 'unparseable' }
    }
    $final = $parsed * $multiplier

    $dotIdx = $stripped.IndexOf($dot)
    if ($siApplied) {
        # SI suffix is in play — typed dot is legitimate ("1.5k" → 1500).
        # Enforce precision against the multiplied result via modulo on
        # the quantum grid. Precision=0 → quantum=1 → require integer.
        $quantum = if ($Precision -eq 0) { [decimal]1 } else { [decimal][Math]::Pow(10.0, -$Precision) }
        if (($final % $quantum) -ne 0) {
            return @{ Ok = $false; Value = $final; Reason = 'precision' }
        }
    } else {
        # No SI multiplier — preserve the original UX: any dot at
        # Precision=0 is invalid; more decimals than Precision in the buffer
        # text is invalid. (This gives the user immediate red-feedback the
        # moment they type a stray '.', rather than waiting until they
        # finish typing the fractional digits.)
        if ($Precision -eq 0 -and $dotIdx -ge 0) {
            return @{ Ok = $false; Value = $final; Reason = 'precision' }
        }
        if ($dotIdx -ge 0) {
            $decimalsTyped = $stripped.Length - $dotIdx - $dot.Length
            if ($decimalsTyped -gt $Precision) {
                return @{ Ok = $false; Value = $final; Reason = 'precision' }
            }
        }
    }

    if ($final -lt $Min -or $final -gt $Max) {
        return @{ Ok = $false; Value = $final; Reason = 'range' }
    }
    return @{ Ok = $true; Value = $final; Reason = '' }
}

function Get-AcceleratedStep {
    # Internal: compute the next [decimal] value after a single Up/Down arrow,
    # given how long the same-direction key has been held. The curve has three
    # inputs (hold time, total range, proximity to the relevant limit):
    #
    #   factor    = min(10^(holdMs/1000), maxFactor)
    #               grows one order of magnitude per second of hold. At a
    #               terminal repeat of ~30Hz that's ~30 ticks per decade, so
    #               the user actually sees and can release at intermediate
    #               step magnitudes (1, 2, 5, 10, 20, 50, 100, ...) rather
    #               than skipping straight through the orders.
    #   maxFactor = max(2, range / (baseStep * 30))
    #               peak grows linearly with range so big ranges still reach
    #               useful speeds — a fully-held arrow traverses the full
    #               range in ~1s at peak. The max(2, ...) floor preserves a
    #               small amount of acceleration even for tiny ranges.
    #   dampener  = proxRatio where proxRatio = distance / dampenZone, and
    #               dampenZone = max(baseStep*5, factor*baseStep*3). Linear
    #               falloff in a *speed-scaled* zone — the brake distance
    #               equals about 3 ticks of the user's current speed, so on
    #               big ranges the brake doesn't start absurdly early and
    #               the closing trajectory is geometric (~33% of remaining
    #               distance per tick → ~20-tick brake from peak to limit
    #               regardless of range). The final max(baseStep, ...) clamp
    #               restores single-tick precision in the last few units.
    #
    # Caller passes the parsed current value, the direction (+1/-1), and the
    # measured hold time. Returns the clamped, precision-quantized next value.
    [CmdletBinding()]
    [OutputType([decimal])]
    param(
        [Parameter(Mandatory)][decimal]$Current,
        [Parameter(Mandatory)][int]$Direction,
        [Parameter(Mandatory)][decimal]$Min,
        [Parameter(Mandatory)][decimal]$Max,
        [Parameter(Mandatory)][decimal]$BaseStep,
        [Parameter(Mandatory)][int]$Precision,
        [Parameter(Mandatory)][double]$HoldMs
    )
    if ($Direction -ne 1 -and $Direction -ne -1) {
        throw "Get-AcceleratedStep: -Direction must be +1 or -1."
    }
    $range = [double]($Max - $Min)
    if ($range -le 0) {
        if ($Current -lt $Min) { return $Min }
        if ($Current -gt $Max) { return $Max }
        return $Current
    }

    $rampFactor = [Math]::Pow(10.0, $HoldMs / 1000.0)
    $maxFactor = [Math]::Max(2.0, $range / ([double]$BaseStep * 30.0))
    $factor = [Math]::Min($rampFactor, $maxFactor)

    $distanceToLimit = if ($Direction -gt 0) {
        [double]($Max - $Current)
    } else {
        [double]($Current - $Min)
    }
    if ($distanceToLimit -lt 0) { $distanceToLimit = 0.0 }
    $dampenZone = [Math]::Max([double]$BaseStep * 5.0, $factor * [double]$BaseStep * 3.0)
    $proxRatio = [Math]::Min(1.0, $distanceToLimit / $dampenZone)
    $dampener = $proxRatio

    $rawStep = [double]$BaseStep * $factor * $dampener

    $quantum = [Math]::Pow(10.0, -[double]$Precision)
    $quantizedSteps = [Math]::Max(1.0, [Math]::Round($rawStep / $quantum))
    $stepD = $quantizedSteps * $quantum

    $step = [decimal][Math]::Round($stepD, [Math]::Max(0, $Precision))
    if ($step -lt $BaseStep) { $step = $BaseStep }

    $next = $Current + [decimal]$Direction * $step
    if ($next -lt $Min) { $next = $Min }
    if ($next -gt $Max) { $next = $Max }
    return $next
}

function Read-Number {
    <#
    .SYNOPSIS
        Inline numeric input with arrow-key acceleration and unit display.
    .DESCRIPTION
        Renders a bounded numeric field decorated with optional Prefix /
        Suffix strings (e.g. "$", " %", " km/h", " °C"). Arrow Up/Down
        increment/decrement; held arrows accelerate via a continuous curve
        derived from hold time, total range, and proximity to the nearest
        limit (so big ranges traverse quickly without overshooting). PageUp
        / PageDown jump by 10 * Step without acceleration; Home / End move
        the text cursor for in-place editing. Direct typing of digits is
        always accepted; '-' is accepted only at position 0 when Min < 0;
        the culture's decimal point is accepted only when Precision > 0; the
        culture's thousands separator is accepted only when -ThousandsSeparator
        is on. A trailing SI multiplier ('k', 'M', 'G', or 'T' = 10^3, 10^6,
        10^9, 10^12) is also accepted — "1.5M" means 1,500,000. Case-
        sensitive (lowercase k for kilo, uppercase M/G/T per SI). The widget
        re-formats the buffer to the canonical numeric form the next time the
        value is updated by an arrow key or paste. Pasted content must parse
        to a single in-range number or it is rejected wholesale (same
        convention as Read-ValidatedInput).

        Internal arithmetic uses [decimal] end-to-end to avoid IEEE-754
        drift in display and stepping — important when Precision > 0 or
        when the same value is rendered with grouping separators.
    .PARAMETER Prompt
        Label shown before the input field.
    .PARAMETER Min
        Minimum allowed value (inclusive).
    .PARAMETER Max
        Maximum allowed value (inclusive).
    .PARAMETER Default
        Initial value. Defaults to 0 when 0 is in [Min, Max], else Min.
    .PARAMETER Step
        Base arrow-key increment (the value the acceleration curve scales).
        Defaults to 1 when Precision=0; 10^-Precision otherwise.
    .PARAMETER Precision
        Decimal places (0-6). 0 (default) gives integer behavior; any '.'
        in the buffer is rejected.
    .PARAMETER Prefix
        Literal string shown before the number (e.g. "$").
    .PARAMETER Suffix
        Literal string shown after the number (e.g. " %", " km/h", " °C").
        Caveat: wide-character suffixes (CJK Wide / Fullwidth) are rendered
        literally — the widget does not compute their display width.
    .PARAMETER ThousandsSeparator
        Render and accept the current culture's thousands separator
        (e.g. "10,000,000" in en-US, "10.000.000" in de-DE).
    .PARAMETER NoColor
        Suppress color; show [OK]/[??] markers in place of green/red text.
        Defaults to $script:_NoColor (set by NO_COLOR env var at import).
    .PARAMETER Decorator
        Optional scriptblock called once per render with the current parsed
        value ([decimal]). Whatever string it returns is written between
        the prompt and the prefix — useful for live, value-driven
        decoration (signal bars, level meters, sparklines). The decorator
        owns its own ANSI escapes if it wants color; nothing is wrapped
        or styled by the framework. When both -Bar and -Decorator are
        passed, -Bar wins (it builds a decorator internally).
    .PARAMETER Bar
        Render a live progress bar between the prompt and the numeric
        value, tracking how far the current value sits between -Min and
        -Max (e.g. "Port: [██████░░░░░░░░░░░░░░] 16384"). Updates each
        tick as arrow keys, typing, or paste change the value.
    .PARAMETER BarWidth
        Bar width in characters. Default: 20. Only meaningful with -Bar.
    .PARAMETER Ascii
        Force ASCII bar glyphs ('#'/'-') instead of Unicode ('█'/'░').
        Defaults to $script:_AsciiMode (PWSHTUI_ASCII env var). Only
        meaningful with -Bar.
    .PARAMETER BufferParser
        Optional scriptblock that replaces the built-in buffer-validation
        path. Invoked with the current buffer string; must return a hashtable
        @{ Ok; Value; Reason }. When set, the per-character typing filter
        relaxes — any non-control printable character is accepted at the
        cursor and the parser becomes the sole arbiter of validity. The
        custom parser also handles paste content. -Min / -Max remain
        meaningful for arrow-key navigation, PageUp/Down clamping, and the
        bar fill ratio, so the parser's returned Value must be expressed
        in the same units as Min / Max. Used internally by Read-Measurement
        to handle mixed-unit input (e.g. "12ft 3in") that the built-in
        numeric parser would reject.
    .EXAMPLE
        PS> Read-Number -Prompt 'Port:' -Min 1 -Max 65535 -Default 8080
    .EXAMPLE
        PS> Read-Number -Prompt 'Coverage:' -Min 0 -Max 100 -Suffix ' %'
    .EXAMPLE
        PS> Read-Number -Prompt 'Amount:' -Min 0 -Max 1000000000 -Precision 2 `
                        -Prefix '$' -ThousandsSeparator
    .EXAMPLE
        PS> Read-Number -Prompt 'Volume:' -Min 0 -Max 11 -Default 7 -Bar
    .OUTPUTS
        [decimal] entered value, or $null on Escape.
    #>
    [CmdletBinding()]
    [OutputType([decimal])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Prompt,
        [Parameter(Mandatory)][decimal]$Min,
        [Parameter(Mandatory)][decimal]$Max,
        [decimal]$Default,
        [decimal]$Step,
        [ValidateRange(0, 6)][int]$Precision = 0,
        [string]$Prefix = '',
        [string]$Suffix = '',
        [switch]$ThousandsSeparator,
        [switch]$NoColor,
        [scriptblock]$Decorator,
        [switch]$Bar,
        [ValidateRange(5, 80)][int]$BarWidth = 20,
        [switch]$Ascii,
        [scriptblock]$BufferParser
    )

    Assert-InteractiveHost 'Read-Number'

    if ($Min -gt $Max) {
        throw "Read-Number: -Min ($Min) must be less than or equal to -Max ($Max)."
    }

    if (-not $PSBoundParameters.ContainsKey('Default')) {
        $Default = if ([decimal]0 -ge $Min -and [decimal]0 -le $Max) { [decimal]0 } else { $Min }
    }
    if ($Default -lt $Min) { $Default = $Min }
    if ($Default -gt $Max) { $Default = $Max }

    if (-not $PSBoundParameters.ContainsKey('Step')) {
        $Step = if ($Precision -eq 0) { [decimal]1 } else { [decimal][Math]::Pow(10.0, -$Precision) }
    }
    if ($Step -le 0) {
        throw "Read-Number: -Step must be greater than 0."
    }

    $noColorOn = if ($PSBoundParameters.ContainsKey('NoColor')) { [bool]$NoColor } else { $script:_NoColor }
    $culture = [System.Globalization.CultureInfo]::CurrentCulture
    $sepChar = $culture.NumberFormat.NumberGroupSeparator
    $dotChar = $culture.NumberFormat.NumberDecimalSeparator

    # -Bar builds its own decorator (overriding any caller-supplied one).
    # Resolve glyphs once up here. The decorator closure can capture
    # variables but its function-resolution scope is the global session
    # state (a quirk of GetNewClosure), so it would not find module-
    # private helpers like Get-Glyphs or Format-ValueBar. Keeping the
    # closure body to plain operators + captured POD values sidesteps
    # the whole issue.
    #
    # NOTE — deliberate duplication: the math below mirrors
    # Format-ValueBar. We accept the dup because (a) the logic is tiny
    # (~10 lines of arithmetic and a format string), (b) the alternative
    # is non-obvious session-state plumbing that requires its own
    # explanation, and (c) Format-ValueBar remains the canonical, unit-
    # tested implementation for any direct callers. If the bar geometry,
    # glyphs, or color scheme ever change, both spots must be updated
    # together.
    if ($Bar) {
        $asciiOn = if ($PSBoundParameters.ContainsKey('Ascii')) { [bool]$Ascii } else { $script:_AsciiMode }
        $glyphs = Get-Glyphs $asciiOn
        $fillChar = $glyphs.BarFill
        $emptyChar = $glyphs.BarEmpty
        $barMin = $Min
        $barMax = $Max
        $Decorator = {
            param($v)
            $range = [double]($barMax - $barMin)
            $ratio = if ($range -le 0) { 1.0 } else { [double]($v - $barMin) / $range }
            if     ($ratio -lt 0.0) { $ratio = 0.0 }
            elseif ($ratio -gt 1.0) { $ratio = 1.0 }
            $filled = [int][Math]::Round($ratio * $BarWidth)
            if     ($filled -lt 0)         { $filled = 0 }
            elseif ($filled -gt $BarWidth) { $filled = $BarWidth }
            $empty = $BarWidth - $filled
            $filledStr = $fillChar * $filled
            $emptyStr  = $emptyChar * $empty
            if ($noColorOn) { return "[$filledStr$emptyStr] " }
            return "[`e[92m$filledStr`e[90m$emptyStr`e[0m] "
        }.GetNewClosure()
    }

    $lastValidValue = $Default
    $buffer = Format-NumberValue -Value $Default -Precision $Precision `
        -ThousandsSeparator:$ThousandsSeparator -Culture $culture
    $cursor = $buffer.Length

    # Hold-acceleration state. lastArrowDir is the most recent Up/Down direction
    # (or 0 if the previous event wasn't Up/Down). holdStartTime anchors the
    # hold; the next consecutive arrow within $holdGapMs of $lastArrowTime
    # keeps that anchor, otherwise we start a fresh hold.
    $lastArrowDir = 0
    $lastArrowTime = [DateTime]::MinValue
    $holdStartTime = [DateTime]::MinValue
    $holdGapMs = 80.0

    $raw = Enter-RawConsole -BracketedPaste

    $running = $true
    $cancelled = $false
    $result = $null

    try {
        while ($running) {
            $parseResult = if ($BufferParser) {
                & $BufferParser $buffer
            } else {
                ConvertTo-NumberValue -Buffer $buffer -Precision $Precision `
                    -Min $Min -Max $Max -Culture $culture
            }
            $isValid = [bool]$parseResult.Ok
            if ($isValid) { $lastValidValue = $parseResult.Value }

            if ($noColorOn) {
                Write-Host "`r$Prompt " -NoNewline
            } else {
                Write-Host "`r$Prompt " -NoNewline -ForegroundColor Cyan
            }

            if ($null -ne $Decorator) {
                # Pass the current parsed value when it parses, otherwise
                # the last known valid value — keeps the decoration stable
                # during mid-edit transient invalid states.
                $decoVal = if ($isValid) { $parseResult.Value } else { $lastValidValue }
                $decoText = & $Decorator $decoVal
                if ($decoText) { Write-Host $decoText -NoNewline }
            }

            if ($Prefix) { Write-Host $Prefix -NoNewline }

            if ($noColorOn) {
                for ($i = 0; $i -le $buffer.Length; $i++) {
                    if ($i -eq $cursor) {
                        $ch = if ($i -lt $buffer.Length) { $buffer[$i] } else { ' ' }
                        Write-Host "[$ch]" -NoNewline
                    } elseif ($i -lt $buffer.Length) {
                        Write-Host $buffer[$i] -NoNewline
                    }
                }
            } else {
                $color = if ($isValid) { 'Green' } else { 'Red' }
                for ($i = 0; $i -le $buffer.Length; $i++) {
                    if ($i -eq $cursor) {
                        $ch = if ($i -lt $buffer.Length) { $buffer[$i] } else { ' ' }
                        Write-Host $ch -NoNewline -BackgroundColor Cyan -ForegroundColor Black
                    } elseif ($i -lt $buffer.Length) {
                        Write-Host $buffer[$i] -NoNewline -ForegroundColor $color
                    }
                }
            }

            if ($Suffix) { Write-Host $Suffix -NoNewline }

            if ($noColorOn) {
                $marker = if ($isValid) { ' [OK]' } else { ' [??]' }
                Write-Host $marker -NoNewline
            }

            Write-Host "`e[K" -NoNewline

            $evt = Read-KeyOrPaste

            if ($evt.Kind -eq 'Discard') {
                continue
            }

            if ($evt.Kind -eq 'Paste') {
                if ($evt.HasControlChars) {
                    Write-Notice $script:_Strings.Notice_PasteControlChars -NoColor:$noColorOn
                } else {
                    $pasteParse = if ($BufferParser) {
                        & $BufferParser $evt.Text
                    } else {
                        ConvertTo-NumberValue -Buffer $evt.Text -Precision $Precision `
                            -Min $Min -Max $Max -Culture $culture
                    }
                    if ($pasteParse.Ok) {
                        # When a custom parser is in play the typed buffer may
                        # not be a canonical numeric form (e.g. "12ft 3in") —
                        # preserve it verbatim. Built-in path re-formats so
                        # grouping separators and precision render cleanly.
                        $buffer = if ($BufferParser) {
                            $evt.Text
                        } else {
                            Format-NumberValue -Value $pasteParse.Value -Precision $Precision `
                                -ThousandsSeparator:$ThousandsSeparator -Culture $culture
                        }
                        $cursor = $buffer.Length
                        $lastValidValue = $pasteParse.Value
                        if ($evt.TrailingNewline) { $running = $false }
                    } else {
                        Write-Notice ($script:_Strings.Notice_PasteRejected -f $pasteParse.Reason) -NoColor:$noColorOn
                    }
                }
                $lastArrowDir = 0
                $holdStartTime = [DateTime]::MinValue
                continue
            }

            $key = $evt.Key
            if (Test-ControlC $key) {
                throw [System.Management.Automation.PipelineStoppedException]::new()
            }

            $thisArrowDir = 0

            switch ($key.Key) {
                'UpArrow' {
                    $thisArrowDir = 1
                    $now = [DateTime]::UtcNow
                    if ($lastArrowDir -eq 1 -and ($now - $lastArrowTime).TotalMilliseconds -lt $holdGapMs) {
                        # continue current hold; $holdStartTime unchanged
                    } else {
                        $holdStartTime = $now
                    }
                    $holdMs = ($now - $holdStartTime).TotalMilliseconds
                    $lastArrowTime = $now
                    $base = if ($isValid) { $parseResult.Value } else { $lastValidValue }
                    $newVal = Get-AcceleratedStep -Current $base -Direction 1 `
                        -Min $Min -Max $Max -BaseStep $Step -Precision $Precision -HoldMs $holdMs
                    $buffer = Format-NumberValue -Value $newVal -Precision $Precision `
                        -ThousandsSeparator:$ThousandsSeparator -Culture $culture
                    $cursor = $buffer.Length
                }
                'DownArrow' {
                    $thisArrowDir = -1
                    $now = [DateTime]::UtcNow
                    if ($lastArrowDir -eq -1 -and ($now - $lastArrowTime).TotalMilliseconds -lt $holdGapMs) {
                        # continue current hold; $holdStartTime unchanged
                    } else {
                        $holdStartTime = $now
                    }
                    $holdMs = ($now - $holdStartTime).TotalMilliseconds
                    $lastArrowTime = $now
                    $base = if ($isValid) { $parseResult.Value } else { $lastValidValue }
                    $newVal = Get-AcceleratedStep -Current $base -Direction -1 `
                        -Min $Min -Max $Max -BaseStep $Step -Precision $Precision -HoldMs $holdMs
                    $buffer = Format-NumberValue -Value $newVal -Precision $Precision `
                        -ThousandsSeparator:$ThousandsSeparator -Culture $culture
                    $cursor = $buffer.Length
                }
                'PageUp' {
                    $base = if ($isValid) { $parseResult.Value } else { $lastValidValue }
                    $newVal = $base + ([decimal]10 * $Step)
                    if ($newVal -gt $Max) { $newVal = $Max }
                    $buffer = Format-NumberValue -Value $newVal -Precision $Precision `
                        -ThousandsSeparator:$ThousandsSeparator -Culture $culture
                    $cursor = $buffer.Length
                }
                'PageDown' {
                    $base = if ($isValid) { $parseResult.Value } else { $lastValidValue }
                    $newVal = $base - ([decimal]10 * $Step)
                    if ($newVal -lt $Min) { $newVal = $Min }
                    $buffer = Format-NumberValue -Value $newVal -Precision $Precision `
                        -ThousandsSeparator:$ThousandsSeparator -Culture $culture
                    $cursor = $buffer.Length
                }
                'LeftArrow'  { if ($cursor -gt 0) { $cursor-- } }
                'RightArrow' { if ($cursor -lt $buffer.Length) { $cursor++ } }
                'Home'       { $cursor = 0 }
                'End'        { $cursor = $buffer.Length }
                'Backspace'  {
                    if ($cursor -gt 0) {
                        $buffer = $buffer.Substring(0, $cursor - 1) + $buffer.Substring($cursor)
                        $cursor--
                    }
                }
                'Delete'     {
                    if ($cursor -lt $buffer.Length) {
                        $buffer = $buffer.Substring(0, $cursor) + $buffer.Substring($cursor + 1)
                    }
                }
                'Enter'      {
                    if ($isValid) { $running = $false }
                }
                'Escape'     {
                    $cancelled = $true
                    $running = $false
                }
                default      {
                    $ch = $key.KeyChar
                    if (-not [char]::IsControl($ch)) {
                        $accept = $false
                        if ($BufferParser) {
                            # Custom parser owns the validity contract; widget
                            # accepts any printable so mixed-unit input like
                            # "5'11\"" or "12ft 3in" can be typed character by
                            # character without per-key gating.
                            $accept = $true
                        } elseif ([char]::IsDigit($ch)) {
                            $accept = $true
                        } elseif ($ch -eq '-') {
                            if ($cursor -eq 0 -and $Min -lt 0 -and $buffer.IndexOf('-') -lt 0) {
                                $accept = $true
                            }
                        } elseif ([string]$ch -eq $dotChar) {
                            if ($Precision -gt 0 -and $buffer.IndexOf($dotChar) -lt 0) {
                                $accept = $true
                            }
                        } elseif ([string]$ch -eq $sepChar) {
                            if ($ThousandsSeparator) {
                                $accept = $true
                            }
                        } elseif ($ch -cin 'k','M','G','T') {
                            # SI multiplier: only at end of buffer, only once,
                            # only when at least one digit is already typed.
                            # Case-sensitive (lowercase k for kilo per SI).
                            if ($cursor -eq $buffer.Length -and ($buffer -match '\d')) {
                                $last = if ($buffer.Length -gt 0) { $buffer[$buffer.Length - 1] } else { [char]' ' }
                                if ($last -cnotin 'k','M','G','T') {
                                    $accept = $true
                                }
                            }
                        }
                        if ($accept) {
                            $buffer = $buffer.Substring(0, $cursor) + $ch + $buffer.Substring($cursor)
                            $cursor++
                        }
                    }
                }
            }

            $lastArrowDir = $thisArrowDir
            if ($thisArrowDir -eq 0) {
                $holdStartTime = [DateTime]::MinValue
            }
        }

        if (-not $cancelled) {
            $finalParse = if ($BufferParser) {
                & $BufferParser $buffer
            } else {
                ConvertTo-NumberValue -Buffer $buffer -Precision $Precision `
                    -Min $Min -Max $Max -Culture $culture
            }
            $result = $finalParse.Value
        }

        $finalStr = if ($null -eq $result) {
            ''
        } elseif ($BufferParser) {
            # The buffer holds the user's free-form text (e.g. "12ft 3in"); the
            # custom parser converts it to the base-unit value but the
            # commit-line echoes what they actually typed.
            $buffer
        } else {
            Format-NumberValue -Value $result -Precision $Precision `
                -ThousandsSeparator:$ThousandsSeparator -Culture $culture
        }
        $finalDeco = ''
        if ($null -ne $Decorator -and $null -ne $result) {
            $finalDeco = & $Decorator $result
            if (-not $finalDeco) { $finalDeco = '' }
        }
        Write-Host "`r$Prompt $finalDeco$Prefix$finalStr$Suffix`e[K"
    } finally {
        Exit-RawConsole $raw
        Write-Host ""
    }

    return $result
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

    $raw = Enter-RawConsole

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
        Exit-RawConsole $raw
        Write-Host ""
    }

    return $result
}

function Read-Choice {
    <#
    .SYNOPSIS
        One-line N-option selector with optional multi-select.
    .DESCRIPTION
        Renders a question and a horizontal list of 2-9 options on a single
        line. Navigate with Left/Right (Tab also moves forward); press a
        digit key 1-N to jump. Enter confirms; Escape returns $null.

        In single-select mode, pressing a digit commits immediately
        (matching the Y/N shortcut in Read-Confirmation). In -MultiSelect
        mode, Space toggles the focused option's checked state, digit keys
        move focus only, and Enter returns the array of selected labels.

        Options are always numbered ("1.Apple  2.Banana  ...") so digit-key
        selection is discoverable. Focus is shown by background color in
        the default mode; in -NoColor mode the focused option is prefixed
        with '> ' to keep layout stable as focus moves. Multi-select uses
        the module's radio glyphs (Unicode '●'/'○' or ASCII '[x]'/'[ ]').

        For longer lists, searchable selection, or screen-filling menus,
        use Get-PaginatedSelection or Invoke-NestedMenu instead — this
        function is intentionally narrow for short inline prompts.
    .PARAMETER Question
        Required. Label shown before the options.
    .PARAMETER Options
        Required. 2-9 option labels. Labels should be short enough to fit
        on one line at the user's terminal width.
    .PARAMETER Default
        Initial focused-option index (0-based). Default 0.
    .PARAMETER MultiSelect
        Allow toggling multiple options with Space; Enter returns an
        array of selected labels.
    .PARAMETER PreSelected
        Initial checked indices (0-based) for -MultiSelect. Ignored
        otherwise. Out-of-range indices are silently dropped.
    .EXAMPLE
        PS> Read-Choice -Question 'Pick a color:' -Options 'Red','Green','Blue'
        Returns 'Red', 'Green', or 'Blue' — or $null if cancelled.
    .EXAMPLE
        PS> Read-Choice -Question 'Toppings:' -Options 'Cheese','Pepperoni','Mushroom','Olives' -MultiSelect
        Returns an array of selected toppings (possibly empty), or $null
        if cancelled.
    .OUTPUTS
        [string] selected label in single-select; [string[]] in -MultiSelect;
        $null if cancelled.
    #>
    [CmdletBinding()]
    [OutputType([string], [string[]])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Question,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateCount(2, 9)]
        [string[]]$Options,

        [int]$Default = 0,

        [switch]$MultiSelect,

        [int[]]$PreSelected,

        [switch]$NoColor
    )

    Assert-InteractiveHost 'Read-Choice'

    $noColorOn = if ($PSBoundParameters.ContainsKey('NoColor')) { [bool]$NoColor } else { $script:_NoColor }
    $glyphs = Get-Glyphs $script:_AsciiMode

    $count = $Options.Count
    $focus = $Default
    if ($focus -lt 0 -or $focus -ge $count) { $focus = 0 }

    # Multi-select checked state. Use a fixed-size [bool[]] so strict mode
    # is happy with index access; pre-seed from -PreSelected (ignoring
    # out-of-range indices silently — callers wiring up dynamic option
    # lists shouldn't have to filter defensively).
    $checked = New-Object 'bool[]' $count
    if ($MultiSelect -and $PreSelected) {
        foreach ($i in $PreSelected) {
            if ($i -ge 0 -and $i -lt $count) { $checked[$i] = $true }
        }
    }

    $running = $true
    $result = $null
    # Track the multi-select selection as a flat array for the final echo;
    # $result wraps it via the unary-comma trick to preserve array shape
    # through the pipeline, which makes it unusable for direct -join.
    $selLabels = @()

    $raw = Enter-RawConsole

    try {
        while ($running) {
            if ($noColorOn) {
                Write-Host "`r$Question " -NoNewline
            } else {
                Write-Host "`r$Question " -NoNewline -ForegroundColor Cyan
            }

            for ($i = 0; $i -lt $count; $i++) {
                $isFocused = ($i -eq $focus)
                $isChecked = $MultiSelect -and $checked[$i]

                # Inter-option separator: two spaces between items keeps the
                # one-line layout readable without a heavyweight delimiter.
                if ($i -gt 0) { Write-Host '  ' -NoNewline }

                # NoColor focus marker: '> ' before the focused option, two
                # spaces before every other option, so column alignment is
                # stable across arrow-key moves. Color mode skips this slot
                # entirely since bg highlight makes focus self-evident.
                if ($noColorOn) {
                    if ($isFocused) { Write-Host '> ' -NoNewline } else { Write-Host '  ' -NoNewline }
                }

                $marker = ''
                if ($MultiSelect) {
                    $marker = if ($isChecked) { "$($glyphs.RadioOn) " } else { "$($glyphs.RadioOff) " }
                }

                $label = "$marker$($i + 1).$($Options[$i])"

                if ($noColorOn -or -not $isFocused) {
                    Write-Host $label -NoNewline
                } else {
                    Write-Host $label -NoNewline -BackgroundColor Cyan -ForegroundColor Black
                }
            }

            Write-Host "`e[K" -NoNewline # Clear to end of line

            $key = [Console]::ReadKey($true)

            if (Test-ControlC $key) {
                throw [System.Management.Automation.PipelineStoppedException]::new()
            } elseif ($key.Key -eq 'LeftArrow') {
                if ($focus -gt 0) { $focus-- }
            } elseif ($key.Key -eq 'RightArrow' -or $key.Key -eq 'Tab') {
                if ($focus -lt $count - 1) { $focus++ }
            } elseif ($key.Key -eq 'Home') {
                $focus = 0
            } elseif ($key.Key -eq 'End') {
                $focus = $count - 1
            } elseif ($key.Key -eq 'Spacebar' -and $MultiSelect) {
                $checked[$focus] = -not $checked[$focus]
            } elseif ($key.Key -eq 'Enter') {
                if ($MultiSelect) {
                    $selLabels = @()
                    for ($i = 0; $i -lt $count; $i++) {
                        if ($checked[$i]) { $selLabels += $Options[$i] }
                    }
                    $result = ,$selLabels
                } else {
                    $result = $Options[$focus]
                }
                $running = $false
            } elseif ($key.Key -eq 'Escape') {
                $result = $null
                $running = $false
            } else {
                # Digit-key hotkey: 1..N. In single-select, commit and exit;
                # in multi-select, move focus (Space then toggles).
                $c = $key.KeyChar
                if ($c -ge '1' -and $c -le '9') {
                    $idx = [int]([string]$c) - 1
                    if ($idx -lt $count) {
                        $focus = $idx
                        if (-not $MultiSelect) {
                            $result = $Options[$focus]
                            $running = $false
                        }
                    }
                }
            }
        }

        # Final draw: echo the chosen value(s) so the prompt line records
        # the answer above any subsequent output, matching Read-Confirmation.
        $echo = ''
        if ($null -eq $result) {
            $echo = $script:_Strings.Status_Cancelled
        } elseif ($MultiSelect) {
            if ($selLabels.Count -eq 0) { $echo = '(none)' }
            else { $echo = ($selLabels -join ', ') }
        } else {
            $echo = $result
        }
        Write-Host "`r$Question $echo`e[K"
    } finally {
        Exit-RawConsole $raw
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
        an hour, `(1h 23m)` beyond. Orthogonal to -ElapsedVariable: this
        controls on-screen display while the spinner runs.
    .PARAMETER ElapsedVariable
        Name (no `$`) of a variable in the caller's scope to receive the
        total elapsed time as a [TimeSpan] after the spinner exits.
        Mirrors PowerShell's -OutVariable / -ErrorVariable convention.
        The spinner line is erased on exit in interactive (VT) mode, so
        capture this if you want to render "fetched in 2.3s" yourself.
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
    .EXAMPLE
        PS> $users = Show-Spinner -Activity "Fetching" -ElapsedVariable el -ScriptBlock {
                Invoke-RestMethod $url
            }
        PS> Write-Host "$($users.Count) users in $('{0:F1}s' -f $el.TotalSeconds)"
        Spinner is gone; the caller composes whatever post-line they want.
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

        [string]$ElapsedVariable,

        [switch]$Ascii
    )

    # Resolve effective rendering modes: explicit switch > env var > rich.
    # -Ascii forces -Style Ascii (overrides any -Style choice) so the safety
    # fallback is opt-in via a single consistent switch name across the module.
    $asciiOn   = if ($PSBoundParameters.ContainsKey('Ascii'))   { [bool]$Ascii }   else { $script:_AsciiMode }
    $noColorOn = if ($PSBoundParameters.ContainsKey('NoColor')) { [bool]$NoColor } else { $script:_NoColor }
    if ($asciiOn) { $Style = 'Ascii' }

    # Seed the live-updatable label holder; Set-SpinnerActivity mutates it while
    # the spinner runs so callers can show progress ("(item 63 of 120)") in place.
    $script:_SpinnerActivity.Text = $Activity

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
            if ($ElapsedVariable) {
                # Modules have isolated scope, so -Scope 1 lands in module
                # scope, not the caller's. SessionState.PSVariable.Set on
                # $PSCmdlet targets the actual invoker, matching how
                # -OutVariable / -ErrorVariable behave across module bounds.
                $PSCmdlet.SessionState.PSVariable.Set($ElapsedVariable, $t)
            }
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
    # Stopwatch started just before the runspace launches so the elapsed
    # time matches the user's perceived wait — not including our own setup
    # overhead. Always running so -ElapsedVariable has a value to return;
    # only handed to the ticker when -ShowTimer wants the live counter on
    # screen.
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $tickerStopwatch = if ($ShowTimer) { $stopwatch } else { $null }
    $tickPS = [powershell]::Create()
    [void]$tickPS.AddScript({
        param($frames, $intervalMs, $activityRef, $stop, $useColor, $sw, $buffer)
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
            # Re-read the label every frame so Set-SpinnerActivity updates appear
            # live. The glyph keeps animating regardless of the label or of the
            # foreground blocking, so a long step never looks frozen.
            $activity = [string]$activityRef.Text
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
    [void]$tickPS.AddArgument($script:_SpinnerActivity)
    [void]$tickPS.AddArgument($stopSignal)
    [void]$tickPS.AddArgument(-not $noColorOn)
    [void]$tickPS.AddArgument($tickerStopwatch)
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
        $stopwatch.Stop()
        $script:_SpinnerActive = $false
        if ($originalCursorVisible) {
            Write-Host "`e[?25h" -NoNewline # restore cursor
        }
        if ($ElapsedVariable) {
            $PSCmdlet.SessionState.PSVariable.Set($ElapsedVariable, $stopwatch.Elapsed)
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

function Set-SpinnerActivity {
    <#
    .SYNOPSIS
        Update the activity text of the currently running Show-Spinner in place.
    .DESCRIPTION
        Show-Spinner's -Activity is normally fixed for the life of the spinner.
        Set-SpinnerActivity lets a long-running -ScriptBlock rewrite that label as
        it makes progress - e.g. "Syncing assets (63 of 120)" - and the change
        appears on the next animation frame. The glyph keeps spinning on its own
        background ticker, so even while the foreground blocks on a slow step the
        line stays alive; this just keeps the text current.

        Complements Write-Spinner: Write-Spinner emits lines that scroll up and
        persist above the spinner; Set-SpinnerActivity rewrites the single live
        line. Any -ShowTimer suffix continues to render after the new text.

        Outside an active VT spinner the call is a silent no-op, so progress
        updates never spam a redirected log in automation - the spinner there
        already degraded to plain start/done lines.
    .PARAMETER Activity
        The new activity text to display after the spinner glyph.
    .EXAMPLE
        PS> Show-Spinner -Activity "Syncing assets" -ShowTimer -ScriptBlock {
                for ($i = 0; $i -lt $items.Count; $i++) {
                    Set-SpinnerActivity "Syncing assets ($($i + 1) of $($items.Count))"
                    Sync-Item $items[$i]
                }
            }
        The single spinner line counts up in place while the work runs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Activity
    )
    # Mutate the shared holder the ticker reads each frame. Harmless when no
    # spinner is running (the next Show-Spinner reseeds it) and invisible in
    # non-VT contexts (the ticker that reads it never started).
    $script:_SpinnerActivity.Text = $Activity
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
    # Help text is hard-capped so a runaway string can't blow out the band.
    $helpCap = 255
    $clampHelp = {
        param($text)
        if ([string]::IsNullOrEmpty($text)) { return $null }
        $t = [string]$text
        if ($t.Length -gt $helpCap) { $t = $t.Substring(0, $helpCap - 1) + "$([char]0x2026)" }
        return $t
    }

    function ConvertTo-MenuItem ($Item) {
        $obj = [PSCustomObject]@{
            Label = $null
            Value = $null
            Children = $null
            Display = $null
            HelpTitle = $null
            Help = $null
        }
        if ($Item -is [hashtable] -or $Item -is [System.Collections.IDictionary]) {
            if ($Item.ContainsKey('Label')) { $obj.Label = $Item.Label }
            if ($Item.ContainsKey('Value')) { $obj.Value = $Item.Value }
            if ($Item.ContainsKey('Display')) { $obj.Display = $Item.Display }
            if ($Item.ContainsKey('HelpTitle')) { $obj.HelpTitle = $Item.HelpTitle }
            if ($Item.ContainsKey('Help')) { $obj.Help = & $clampHelp $Item.Help }
            if ($Item.ContainsKey('Children')) {
                $obj.Children = @()
                foreach ($child in $Item.Children) {
                    $obj.Children += ConvertTo-MenuItem $child
                }
            }
        } else {
            if ($null -ne $Item.Label) { $obj.Label = $Item.Label } else { $obj.Label = $Item.ToString() }
            if ($null -ne $Item.Value) { $obj.Value = $Item.Value } else { $obj.Value = $Item }
            if ($null -ne $Item.Display) { $obj.Display = $Item.Display }
            if ($null -ne $Item.HelpTitle) { $obj.HelpTitle = $Item.HelpTitle }
            if ($null -ne $Item.Help) { $obj.Help = & $clampHelp $Item.Help }
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

    $raw = Enter-RawConsole -AltScreen:$AltScreen

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

            # An optional value column and help band only engage when items at
            # this level opt in via Display / Help. Plain menus take neither
            # branch and render exactly as before.
            $levelHasDisplay = $false
            $levelHasHelp    = $false
            $labelColWidth   = 0
            for ($i = 0; $i -lt $currentItems.Count; $i++) {
                $it = $currentItems[$i]
                if (-not [string]::IsNullOrEmpty($it.Display)) { $levelHasDisplay = $true }
                if (-not [string]::IsNullOrEmpty($it.Help))    { $levelHasHelp = $true }
                $sfx = if ($null -ne $it.Children -and $it.Children.Count -gt 0) { " $($g.ChildIndicator)" } else { "" }
                $w = Get-DisplayWidth "[$($i + 1)] $($it.Label)$sfx"
                if ($w -gt $labelColWidth) { $labelColWidth = $w }
            }

            for ($i = 0; $i -lt $currentItems.Count; $i++) {
                $item = $currentItems[$i]
                $isRowSelected = ($i -eq $selectedIndex)
                $displayNum = $i + 1

                $suffix = if ($null -ne $item.Children -and $item.Children.Count -gt 0) { " $($g.ChildIndicator)" } else { "" }

                if ($levelHasDisplay) {
                    # Align labels into a column, then the current-value column.
                    $labelCell = Format-TuiColumn -Text "[$displayNum] $($item.Label)$suffix" -Width $labelColWidth
                    $displayText = if (-not [string]::IsNullOrEmpty($item.Display)) { "$labelCell  $($item.Display)" } else { $labelCell }
                } else {
                    $displayText = "[$displayNum] $($item.Label)$suffix"
                }

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

            # Help band: rendered as a fenced Note section between body and
            # footer, but only when some item at this level carries Help. The
            # focused item's HelpTitle leads, with its Help text wrapped and
            # hanging-indented to align past the title.
            $note = $null
            if ($levelHasHelp) {
                # Match the inner width Write-TuiBox will settle on, computed
                # from the non-help lines so help never widens the box.
                $winW = 80
                try { if ([Console]::WindowWidth -gt 0) { $winW = [Console]::WindowWidth } } catch {}
                $limit = ($MaxWidth -gt 0) ? [Math]::Min($MaxWidth, $winW) : $winW
                $borderOff = $Border ? 4 : 0
                $maxNonNote = $MinWidth
                foreach ($l in (@($header) + $body + $footer)) {
                    $lw = Get-DisplayWidth $l
                    if ($lw -gt $maxNonNote) { $maxNonNote = $lw }
                }
                $wrapWidth = [Math]::Max(1, [Math]::Min($maxNonNote, $limit - $borderOff))

                $focused = $currentItems[$selectedIndex]
                if (-not [string]::IsNullOrEmpty($focused.Help)) {
                    $title = if (-not [string]::IsNullOrEmpty($focused.HelpTitle)) { [string]$focused.HelpTitle } else { '' }
                    $hang = (Get-DisplayWidth $title) + 2
                    $textWidth = $wrapWidth - $hang
                    if ($textWidth -lt 10) {
                        # Title too wide for a hanging layout: title on its own
                        # line, help wrapped beneath at a shallow indent.
                        $note = @(Format-TuiColumn -Text $title -Width $wrapWidth)
                        $note += @(Format-TuiWrap -Text $focused.Help -Width ([Math]::Max(1, $wrapWidth - 2)) -MaxLines 3 |
                                   ForEach-Object { "  $_" })
                    } else {
                        $wrapped = @(Format-TuiWrap -Text $focused.Help -Width $textWidth -MaxLines 3)
                        $indent = ' ' * $hang
                        $note = @()
                        for ($k = 0; $k -lt $wrapped.Count; $k++) {
                            if ($k -eq 0) { $note += "$title  $($wrapped[0])" }
                            else { $note += "$indent$($wrapped[$k])" }
                        }
                    }
                } else {
                    # Level has help but this item doesn't — keep the fenced
                    # band present (blank body) so its structure doesn't flicker.
                    $note = @('')
                }
            }

            # Draw using UIBox
            $newHeight = Write-TuiBox -Header $header -Body $body -Footer $footer -Note $note `
                                      -Border:$Border -MinWidth $MinWidth -MaxWidth $MaxWidth -X $X -Y $Y `
                                      -SectionRules -Ascii:$asciiOn -PassThru

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
        
        Exit-RawConsole $raw

        # Clean line on abort
        if ($null -eq $result) {
            Write-Host ""
        }
    }

    return $result
}

function Read-Date {
    <#
    .SYNOPSIS
        Inline date picker with optional calendar visualization.
    .DESCRIPTION
        Renders YYYY / Month / DD fields and lets the user pick a date via
        arrow navigation, Up/Down adjustment, or direct typing. Same
        mode-split as Get-PaginatedSelection's search: arrows navigate
        fields and Up/Down adjust values in selection mode; typing digits
        flips to type mode and feeds the focused field. Year and Day fields
        accept two/four-digit input; the Month field accepts 1..12.
        Tab toggles modes; from type mode, arrows / Enter / Esc commit
        the buffer and return to selection mode.

        With -Calendar a month grid is rendered beneath the fields as
        visual context — the input model is unchanged.
    .PARAMETER Prompt
        Header text. Default: "Pick a date:".
    .PARAMETER InitialDate
        Starting value. Default: today (date component only).
    .PARAMETER MinDate
        Earliest acceptable date (inclusive). Enter is blocked silently
        when the current selection is below this. Default: unconstrained.
    .PARAMETER MaxDate
        Latest acceptable date (inclusive). Enter is blocked silently
        when the current selection is above this. Default: unconstrained.
    .PARAMETER Calendar
        Switch. Render a month grid beneath the fields showing the focused
        day in context. The input model is the same as without the switch.
    .OUTPUTS
        [DateTime] with the chosen date and a 00:00:00 time component, or
        $null on cancel.
    #>
    [CmdletBinding()]
    [OutputType([System.DateTime])]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = 'Pick a date:',

        [System.DateTime]$InitialDate = (Get-Date).Date,

        [Nullable[System.DateTime]]$MinDate,
        [Nullable[System.DateTime]]$MaxDate,

        [switch]$Calendar,

        [switch]$NoColor,
        [switch]$Ascii,
        [switch]$Border,
        [int]$MinWidth = 0,
        [int]$MaxWidth = 0,
        [int]$X = -1,
        [int]$Y = -1,
        [switch]$AltScreen
    )

    Assert-InteractiveHost 'Read-Date'

    $asciiOn   = if ($PSBoundParameters.ContainsKey('Ascii'))   { [bool]$Ascii }   else { $script:_AsciiMode }
    $noColorOn = if ($PSBoundParameters.ContainsKey('NoColor')) { [bool]$NoColor } else { $script:_NoColor }
    $g = Get-Glyphs $asciiOn

    $initDate = $InitialDate.Date
    $year  = $initDate.Year
    $month = $initDate.Month
    $day   = $initDate.Day

    # Field ordering is fixed Year/Month/Day (ISO-style), with an optional
    # Calendar grid focus appended when -Calendar is set. Culture-specific
    # ordering is an explicit non-goal — keeps the visual unambiguous and
    # the typing rules consistent across locales.
    $fields = @('Y','M','D')
    if ($Calendar) { $fields += 'C' }
    $lastFieldIdx = $fields.Count - 1

    $focusedIdx = 0
    # Editing is only entered for Y or D fields when the user starts typing
    # digits. Enter commits, Esc discards, Tab commits-and-advances. Month is
    # Up/Down-only — typing has no edit state for it.
    $editing = $false
    $typeBuffer = ''

    # Culture-aware abbreviated month names for display.
    $dtfi = [System.Globalization.DateTimeFormatInfo]::CurrentInfo
    $monthAbbrs = @(1..12 | ForEach-Object { $dtfi.GetAbbreviatedMonthName($_) })
    # Find the widest abbreviation so the inline display has stable spacing.
    # Measured in terminal display cells rather than String.Length — CJK
    # locales render `月` etc. as fullwidth (2 cells).
    $monthWidth = ($monthAbbrs | ForEach-Object { Get-DisplayWidth $_ } | Measure-Object -Maximum).Maximum

    $raw = Enter-RawConsole -AltScreen:$AltScreen

    $running = $true
    $result = $null

    # Clamp day to the focused month/year's actual length whenever month or
    # year changes — keeps "Feb 30" from ever being a stable state.
    $clampDay = {
        $maxD = [DateTime]::DaysInMonth($year, $month)
        if ($day -gt $maxD) { $day = $maxD }
        if ($day -lt 1) { $day = 1 }
    }

    # Commit the digit buffer to the focused field. Only Y and D fields
    # accept typed input; Month is cycled via Up/Down arrows only.
    $commitBuffer = {
        if ([string]::IsNullOrEmpty($typeBuffer)) { return }
        $n = $fields[$focusedIdx]
        switch ($n) {
            'Y' {
                $val = 0
                if ([int]::TryParse($typeBuffer, [ref]$val)) {
                    $year = [Math]::Max(1, [Math]::Min(9999, $val))
                    . $clampDay
                }
            }
            'D' {
                $val = 0
                if ([int]::TryParse($typeBuffer, [ref]$val)) {
                    $maxD = [DateTime]::DaysInMonth($year, $month)
                    $day = [Math]::Max(1, [Math]::Min($maxD, $val))
                }
            }
        }
        $typeBuffer = ''
    }

    # Selection-mode Up/Down. Year clamps at 1..9999; Month wraps within the
    # year (Up at Dec → Jan); Day wraps within the focused month. When
    # MinDate/MaxDate are set, the adjustment is reverted if it would push
    # the date out of range — keeps Enter from being silently blocked
    # because the user navigated past a constraint.
    $adjustField = {
        param([int]$delta)
        $savedYear = $year; $savedMonth = $month; $savedDay = $day
        $n = $fields[$focusedIdx]
        switch ($n) {
            'Y' {
                $year = [Math]::Max(1, [Math]::Min(9999, $year + $delta))
                . $clampDay
            }
            'M' {
                $month = ((($month - 1) + $delta) % 12 + 12) % 12 + 1
                . $clampDay
            }
            'D' {
                $maxD = [DateTime]::DaysInMonth($year, $month)
                $day = (($day - 1 + $delta) % $maxD + $maxD) % $maxD + 1
            }
        }
        if ($null -ne $MinDate -or $null -ne $MaxDate) {
            $proposed = & $currentDate
            if ($null -ne $proposed) {
                $tooEarly = ($null -ne $MinDate) -and ($proposed -lt $MinDate.Date)
                $tooLate  = ($null -ne $MaxDate) -and ($proposed -gt $MaxDate.Date)
                if ($tooEarly -or $tooLate) {
                    $year = $savedYear; $month = $savedMonth; $day = $savedDay
                }
            }
        }
    }

    # Composed date used for MinDate/MaxDate gating. Wrapped in try/catch
    # for the unlikely paranoid case where state somehow drifted invalid.
    $currentDate = {
        try { return [DateTime]::new($year, $month, $day) }
        catch { return $null }
    }

    # Calendar-grid focus: move the highlighted day by N days, crossing month
    # and year boundaries via DateTime arithmetic. Stops at MinDate/MaxDate
    # — out-of-range targets are a silent no-op so the visual greying makes
    # the boundary self-evident.
    $moveCalendarDay = {
        param([int]$dayDelta)
        try {
            $current = [DateTime]::new($year, $month, $day)
            $target = $current.AddDays($dayDelta)
        } catch { return }
        if ($target.Year -lt 1 -or $target.Year -gt 9999) { return }
        if (($null -ne $MinDate) -and ($target -lt $MinDate.Date)) { return }
        if (($null -ne $MaxDate) -and ($target -gt $MaxDate.Date)) { return }
        $year = $target.Year
        $month = $target.Month
        $day = $target.Day
    }

    # Calendar-grid focus: jump by N months. Day is clamped to the new
    # month's length (so May 31 → Jun 30) and the resulting date is checked
    # against MinDate/MaxDate; out-of-range is a no-op.
    $moveCalendarMonth = {
        param([int]$monthDelta)
        $newYear = $year
        $newMonth = $month + $monthDelta
        while ($newMonth -lt 1)  { $newMonth += 12; $newYear-- }
        while ($newMonth -gt 12) { $newMonth -= 12; $newYear++ }
        if ($newYear -lt 1 -or $newYear -gt 9999) { return }
        $maxD = [DateTime]::DaysInMonth($newYear, $newMonth)
        $newDay = [Math]::Min($day, $maxD)
        try { $target = [DateTime]::new($newYear, $newMonth, $newDay) }
        catch { return }
        if (($null -ne $MinDate) -and ($target -lt $MinDate.Date)) { return }
        if (($null -ne $MaxDate) -and ($target -gt $MaxDate.Date)) { return }
        $year = $newYear
        $month = $newMonth
        $day = $newDay
    }

    # Render one field's text — buffer-in-progress when typing into it,
    # otherwise the current value formatted to the field's width. Month is
    # arrow-only so it never shows a type buffer.
    $fieldText = {
        param([int]$idx)
        $n = $fields[$idx]
        $isEditing = ($idx -eq $focusedIdx -and $editing -and $typeBuffer.Length -gt 0)
        switch ($n) {
            'Y' {
                if ($isEditing) { return $typeBuffer.PadRight(4, '_') }
                return ('{0:0000}' -f $year)
            }
            'M' {
                return Add-DisplayPadding $monthAbbrs[$month - 1] $monthWidth
            }
            'D' {
                if ($isEditing) { return $typeBuffer.PadRight(2, '_') }
                return ('{0:00}' -f $day)
            }
        }
    }

    # Render the field row with the focused field highlighted. When focus
    # is on the calendar grid, no field is highlighted in this row — the
    # active focus indicator is the highlighted cell in the grid itself.
    $renderFields = {
        $sb = New-Object System.Text.StringBuilder
        for ($i = 0; $i -lt 3; $i++) {
            if ($i -gt 0) { [void]$sb.Append('  ') }
            $text = & $fieldText $i
            if ($i -eq $focusedIdx) {
                if ($noColorOn) {
                    [void]$sb.Append("[$text]")
                } else {
                    $blink = if ($editing) { '5;' } else { '' }
                    [void]$sb.Append("`e[${blink}46;30m$text`e[0m")
                }
            } else {
                [void]$sb.Append($text)
            }
        }
        return $sb.ToString()
    }

    # Render the calendar grid (only used when -Calendar is set). Day-of-
    # week header is taken from the current culture; week start is Sunday
    # (fixed — culture's actual FirstDayOfWeek differs by region; pinning
    # to Sunday keeps the grid layout predictable across locales).
    $renderCalendar = {
        $lines = [System.Collections.Generic.List[string]]::new()
        $rawDayNames = @(0..6 | ForEach-Object { $dtfi.GetShortestDayName($_) })
        # Column width follows the widest day name in display cells, but is
        # never less than 2 (the natural width of a 1-or-2-digit day). Most
        # CJK locales return 1-char (2-cell) names that fit a 2-cell column;
        # zh-CN is the outlier — its CLDR `ShortestDayNames` are actually
        # 2-char (`周日`, `周一`), so the whole grid widens to 4 cells per
        # column to keep the header aligned over the digits.
        $dayCellWidth = 2
        foreach ($n in $rawDayNames) {
            $w = Get-DisplayWidth $n
            if ($w -gt $dayCellWidth) { $dayCellWidth = $w }
        }
        $abbrDayNames = @($rawDayNames | ForEach-Object { Add-DisplayPadding $_ $dayCellWidth })
        [void]$lines.Add('   ' + ($abbrDayNames -join ' '))
        $firstDow = [int](([DateTime]::new($year, $month, 1)).DayOfWeek)
        $daysInMonth = [DateTime]::DaysInMonth($year, $month)
        $cells = [System.Collections.Generic.List[string]]::new()
        $blankCell = ' ' * $dayCellWidth
        for ($i = 0; $i -lt $firstDow; $i++) { [void]$cells.Add($blankCell) }
        for ($d = 1; $d -le $daysInMonth; $d++) {
            $cell = "{0,$dayCellWidth}" -f $d
            $cellDate = [DateTime]::new($year, $month, $d)
            $excluded = (($null -ne $MinDate) -and ($cellDate -lt $MinDate.Date)) -or `
                        (($null -ne $MaxDate) -and ($cellDate -gt $MaxDate.Date))
            if ($d -eq $day) {
                if ($noColorOn) {
                    # In NoColor the bracket marker can mismatch the column
                    # width — accept the alignment cost rather than introduce
                    # an inconsistent marker that callers have to reason about.
                    $cell = "[$d]"
                    if ($d -lt 10) { $cell = "[ $d]" }
                } else {
                    $cell = "`e[46;30m$cell`e[0m"
                }
            } elseif ($excluded -and -not $noColorOn) {
                # Dim style (`\e[2m`) for dates outside [MinDate, MaxDate].
                # In NoColor the cell is left plain — the boundary stop in
                # the navigation helpers still prevents landing on it.
                $cell = "`e[2m$cell`e[0m"
            }
            [void]$cells.Add($cell)
        }
        # Pad trailing blanks so the last row is a full week — keeps the
        # box width stable across months with different day counts.
        while (($cells.Count % 7) -ne 0) { [void]$cells.Add($blankCell) }
        for ($r = 0; $r -lt $cells.Count; $r += 7) {
            $rowCells = $cells.GetRange($r, 7)
            [void]$lines.Add('   ' + ($rowCells -join ' '))
        }
        return $lines.ToArray()
    }

    try {
        $firstRender = $true
        $lastHeight = 0

        while ($running) {
            if (-not $firstRender -and $X -lt 0 -and $Y -lt 0) {
                Write-Host "`e[$($lastHeight)A" -NoNewline
            } elseif ($firstRender -and ($X -lt 0 -and $Y -lt 0)) {
                Write-Host ""
            }
            $firstRender = $false

            $header = @($Prompt)
            $body = [System.Collections.Generic.List[string]]::new()
            $fieldLine = & $renderFields
            [void]$body.Add($fieldLine)
            if ($Calendar) {
                # Single-space spacer — Write-TuiBox's [string[]] Mandatory
                # binding rejects empty strings as individual array elements.
                [void]$body.Add(' ')
                $calLines = & $renderCalendar
                foreach ($l in $calLines) { [void]$body.Add($l) }
            }

            $s = $script:_Strings
            $currentField = $fields[$focusedIdx]
            $footerLines = [System.Collections.Generic.List[string]]::new()
            if ($editing) {
                [void]$footerLines.Add("Enter=$($s.Footer_Confirm)   Esc=$($s.Footer_Cancel)")
            } elseif ($currentField -eq 'C') {
                [void]$footerLines.Add("$($g.ArrowLeft)$($g.ArrowRight)$($g.ArrowsUpDown) $($s.Footer_Move)   PgUp/PgDn $($s.Footer_Adjust)   Tab=$($s.Footer_Field)   Enter=$($s.Footer_Confirm)   Esc=$($s.Footer_Cancel)")
            } else {
                [void]$footerLines.Add("Tab=$($s.Footer_Field)   $($g.ArrowsUpDown) $($s.Footer_Adjust)   Enter=$($s.Footer_Confirm)   Esc=$($s.Footer_Cancel)")
            }
            $footer = @($footerLines)

            $newHeight = Write-TuiBox -Header $header -Body $body -Footer $footer `
                -Border:$Border -MinWidth $MinWidth -MaxWidth $MaxWidth -X $X -Y $Y `
                -SectionRules -Ascii:$asciiOn -PassThru

            if ($newHeight -lt $lastHeight -and $X -lt 0 -and $Y -lt 0) {
                $diff = $lastHeight - $newHeight
                for ($h = 0; $h -lt $diff; $h++) { Write-Host "`e[K" }
                Write-Host "`e[$($diff)A" -NoNewline
            }
            $lastHeight = $newHeight

            $key = [Console]::ReadKey($true)
            if (Test-ControlC $key) {
                throw [System.Management.Automation.PipelineStoppedException]::new()
            }

            $isShift = ($key.Modifiers -band [System.ConsoleModifiers]::Shift) -ne 0

            # Edit mode (Y or D field, user is typing a value). Only Enter,
            # Esc, Tab, Backspace, and digits are meaningful here. Enter
            # commits the buffer and stays on the field; Esc discards;
            # Tab commits and advances focus.
            if ($editing) {
                switch ($key.Key) {
                    'Enter' {
                        . $commitBuffer
                        $editing = $false
                    }
                    'Escape' {
                        $typeBuffer = ''
                        $editing = $false
                    }
                    'Tab' {
                        . $commitBuffer
                        $editing = $false
                        if ($isShift) {
                            $focusedIdx = ($focusedIdx - 1 + $fields.Count) % $fields.Count
                        } else {
                            $focusedIdx = ($focusedIdx + 1) % $fields.Count
                        }
                    }
                    'Backspace' {
                        if ($typeBuffer.Length -gt 0) {
                            $typeBuffer = $typeBuffer.Substring(0, $typeBuffer.Length - 1)
                        }
                    }
                    default {
                        if ([char]::IsDigit($key.KeyChar)) {
                            $maxLen = if ($currentField -eq 'Y') { 4 } else { 2 }
                            if ($typeBuffer.Length -lt $maxLen) {
                                $typeBuffer += $key.KeyChar
                            }
                        }
                    }
                }
                continue
            }

            # Tab cycles focus across Y → M → D → (Calendar) → Y.
            if ($key.Key -eq 'Tab') {
                if ($isShift) {
                    $focusedIdx = ($focusedIdx - 1 + $fields.Count) % $fields.Count
                } else {
                    $focusedIdx = ($focusedIdx + 1) % $fields.Count
                }
                continue
            }

            # Calendar-grid focus: arrows move the highlighted day across
            # weeks (and into adjacent months); PgUp/PgDn jump by a month.
            # Boundary stops at MinDate/MaxDate are enforced inside the move
            # helpers — the visual greying makes them self-evident.
            if ($currentField -eq 'C') {
                switch ($key.Key) {
                    'LeftArrow'  { . $moveCalendarDay -1 }
                    'RightArrow' { . $moveCalendarDay 1 }
                    'UpArrow'    { . $moveCalendarDay -7 }
                    'DownArrow'  { . $moveCalendarDay 7 }
                    'PageUp'     { . $moveCalendarMonth -1 }
                    'PageDown'   { . $moveCalendarMonth 1 }
                    'Enter' {
                        $candidate = & $currentDate
                        if ($null -ne $candidate) {
                            $okMin = ($null -eq $MinDate) -or ($candidate -ge $MinDate.Date)
                            $okMax = ($null -eq $MaxDate) -or ($candidate -le $MaxDate.Date)
                            if ($okMin -and $okMax) {
                                $result = $candidate
                                $running = $false
                            }
                        }
                    }
                    'Escape' {
                        $result = $null
                        $running = $false
                    }
                }
                continue
            }

            # Y/M/D focus, not editing. Left/Right is a shortcut for moving
            # within the Y/M/D group; Tab is the canonical way to also reach
            # the calendar grid.
            switch ($key.Key) {
                'LeftArrow'  { if ($focusedIdx -gt 0) { $focusedIdx-- } }
                'RightArrow' { if ($focusedIdx -lt 2) { $focusedIdx++ } }
                'UpArrow'    { . $adjustField 1 }
                'DownArrow'  { . $adjustField -1 }
                'Enter' {
                    $candidate = & $currentDate
                    if ($null -ne $candidate) {
                        # PowerShell unboxes [Nullable[DateTime]] params to a
                        # plain DateTime when bound (or $null when unbound),
                        # so the .HasValue/.Value pattern fails under strict
                        # mode. $null check is the canonical pattern here.
                        $okMin = ($null -eq $MinDate) -or ($candidate -ge $MinDate.Date)
                        $okMax = ($null -eq $MaxDate) -or ($candidate -le $MaxDate.Date)
                        if ($okMin -and $okMax) {
                            $result = $candidate
                            $running = $false
                        }
                        # Out-of-range Enter is silently blocked — the user
                        # can see the date in the fields and the constraint
                        # mismatch is self-evident.
                    }
                }
                'Escape' {
                    $result = $null
                    $running = $false
                }
                default {
                    # Digits start an edit on Y or D. Month is Up/Down only.
                    if ($key.KeyChar -ne [char]0 -and -not [char]::IsControl($key.KeyChar) -and [char]::IsDigit($key.KeyChar)) {
                        if ($currentField -eq 'Y' -or $currentField -eq 'D') {
                            $editing = $true
                            $typeBuffer = "$($key.KeyChar)"
                        }
                    }
                }
            }
        }
    } finally {
        if (-not $firstRender -and $X -lt 0 -and $Y -lt 0) {
            Write-Host "`e[$($lastHeight)A" -NoNewline
        }
        Write-Host "`e[J" -NoNewline
        Exit-RawConsole $raw
        if ($null -eq $result) { Write-Host "" }
    }

    return $result
}

function Read-Time {
    <#
    .SYNOPSIS
        Inline time picker with field navigation and direct digit input.
    .DESCRIPTION
        Renders HH:MM (with optional :SS and AM/PM) and lets the user
        change the time via arrow navigation, Up/Down adjustment, or direct
        typing. Same mode-split as Get-PaginatedSelection's search: arrows
        navigate fields and Up/Down adjust values in selection mode; typing
        digits flips to type mode and feeds the focused field with
        auto-advance when a field fills. Tab toggles modes; from type mode,
        arrows / Enter / Esc commit the buffer and return to selection
        mode without confirming or cancelling.
    .PARAMETER Prompt
        Header text. Default: "Enter time:".
    .PARAMETER InitialTime
        Starting value. Default: [TimeSpan]::Zero (00:00:00). Only the
        hour/minute/second components are read.
    .PARAMETER TwelveHour
        Switch. Display as a 12-hour clock with an AM/PM field appended.
        The returned TimeSpan is always in 24-hour terms.
    .PARAMETER ShowSeconds
        Switch. Include a seconds field. Without this switch the seconds
        component of the returned TimeSpan is always 0.
    .OUTPUTS
        [TimeSpan] of the chosen time-of-day (Days = 0), or $null on cancel.
    #>
    [CmdletBinding()]
    [OutputType([System.TimeSpan])]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = 'Enter time:',

        [System.TimeSpan]$InitialTime = [System.TimeSpan]::Zero,

        [switch]$TwelveHour,
        [switch]$ShowSeconds,

        [switch]$NoColor,
        [switch]$Ascii,
        [switch]$Border,
        [int]$MinWidth = 0,
        [int]$MaxWidth = 0,
        [int]$X = -1,
        [int]$Y = -1,
        [switch]$AltScreen
    )

    Assert-InteractiveHost 'Read-Time'

    $asciiOn   = if ($PSBoundParameters.ContainsKey('Ascii'))   { [bool]$Ascii }   else { $script:_AsciiMode }
    $noColorOn = if ($PSBoundParameters.ContainsKey('NoColor')) { [bool]$NoColor } else { $script:_NoColor }
    $g = Get-Glyphs $asciiOn

    # Internal state is always 24h regardless of display mode. Clamp the
    # incoming TimeSpan's hour/minute/second components to a single day.
    $totalHours = [Math]::Max(0, [Math]::Min(23, [int]$InitialTime.Hours))
    $minute = [Math]::Max(0, [Math]::Min(59, [int]$InitialTime.Minutes))
    $second = [Math]::Max(0, [Math]::Min(59, [int]$InitialTime.Seconds))

    # Positional field list. AM/PM (P) always comes last, after the optional
    # seconds field — matches the visual "HH:MM:SS AM" ordering.
    $fieldNames = [System.Collections.Generic.List[string]]::new()
    [void]$fieldNames.Add('H')
    [void]$fieldNames.Add('M')
    if ($ShowSeconds) { [void]$fieldNames.Add('S') }
    if ($TwelveHour)  { [void]$fieldNames.Add('P') }
    $lastFieldIdx = $fieldNames.Count - 1

    $focusedIdx = 0
    $inputMode = 'selection'
    $typeBuffer = ''

    $raw = Enter-RawConsole -AltScreen:$AltScreen

    $running = $true
    $result = $null

    # Commit the digit buffer into the focused field's value. Dot-sourced so
    # the assignments hit the loop's scope, not a child.
    $commitBuffer = {
        if ([string]::IsNullOrEmpty($typeBuffer)) { return }
        $n = $fieldNames[$focusedIdx]
        if ($n -in 'H','M','S') {
            $val = [int]$typeBuffer
            switch ($n) {
                'H' {
                    if ($TwelveHour) {
                        # Buffer holds a 12-hour clock value (1-12). Preserve
                        # the current AM/PM by reading $totalHours's >= 12
                        # state before recomputing.
                        $val = [Math]::Max(1, [Math]::Min(12, $val))
                        $isPM = ($totalHours -ge 12)
                        $totalHours = if ($val -eq 12) {
                            if ($isPM) { 12 } else { 0 }
                        } else {
                            if ($isPM) { $val + 12 } else { $val }
                        }
                    } else {
                        $totalHours = [Math]::Max(0, [Math]::Min(23, $val))
                    }
                }
                'M' { $minute = [Math]::Max(0, [Math]::Min(59, $val)) }
                'S' { $second = [Math]::Max(0, [Math]::Min(59, $val)) }
            }
        }
        $typeBuffer = ''
    }

    # Increment/decrement the focused field (selection-mode Up/Down).
    $adjustField = {
        param([int]$delta)
        $n = $fieldNames[$focusedIdx]
        switch ($n) {
            'H' { $totalHours = (($totalHours + $delta) % 24 + 24) % 24 }
            'M' { $minute     = (($minute + $delta) % 60 + 60) % 60 }
            'S' { $second     = (($second + $delta) % 60 + 60) % 60 }
            'P' {
                # AM/PM toggles by flipping 12 hours regardless of $delta's sign.
                if ($totalHours -ge 12) { $totalHours -= 12 } else { $totalHours += 12 }
            }
        }
    }

    # Render one field's text — the in-progress buffer when typing into it,
    # otherwise the field's current value formatted "00".
    $fieldText = {
        param([int]$idx)
        $n = $fieldNames[$idx]
        if ($idx -eq $focusedIdx -and $inputMode -eq 'type' -and $typeBuffer.Length -gt 0 -and $n -in 'H','M','S') {
            return $typeBuffer.PadRight(2, '_')
        }
        switch ($n) {
            'H' {
                if ($TwelveHour) {
                    $h = $totalHours % 12
                    if ($h -eq 0) { $h = 12 }
                    return ('{0:00}' -f $h)
                }
                return ('{0:00}' -f $totalHours)
            }
            'M' { return ('{0:00}' -f $minute) }
            'S' { return ('{0:00}' -f $second) }
            'P' { return $(if ($totalHours -ge 12) { 'PM' } else { 'AM' }) }
        }
    }

    # Render the whole time line with the focused field highlighted. Color
    # mode uses cyan bg; type mode adds blink to mark active editing. No-color
    # mode uses bracket markers — selection vs type is disambiguated by the
    # underscore padding inside the buffer rather than by changing the marker
    # shape (mode is also visible in the footer).
    $renderLine = {
        $sb = New-Object System.Text.StringBuilder
        for ($i = 0; $i -lt $fieldNames.Count; $i++) {
            $name = $fieldNames[$i]
            if ($i -gt 0) {
                if ($name -eq 'P') { [void]$sb.Append(' ') }
                else { [void]$sb.Append(':') }
            }
            $text = & $fieldText $i
            if ($i -eq $focusedIdx) {
                if ($noColorOn) {
                    [void]$sb.Append("[$text]")
                } else {
                    $blink = if ($inputMode -eq 'type') { '5;' } else { '' }
                    [void]$sb.Append("`e[${blink}46;30m$text`e[0m")
                }
            } else {
                [void]$sb.Append($text)
            }
        }
        return $sb.ToString()
    }

    try {
        $firstRender = $true
        $lastHeight = 0

        while ($running) {
            if (-not $firstRender -and $X -lt 0 -and $Y -lt 0) {
                Write-Host "`e[$($lastHeight)A" -NoNewline
            } elseif ($firstRender -and ($X -lt 0 -and $Y -lt 0)) {
                Write-Host ""
            }
            $firstRender = $false

            $header = @($Prompt)
            $body = @(& $renderLine)

            $s = $script:_Strings
            $footerLines = [System.Collections.Generic.List[string]]::new()
            if ($inputMode -eq 'type') {
                [void]$footerLines.Add("Tab/Enter/Esc/$($g.ArrowsUpDown)=$($s.Footer_BackToSelection)")
            } else {
                [void]$footerLines.Add("$($g.ArrowLeft)$($g.ArrowRight) $($s.Footer_Field)   $($g.ArrowsUpDown) $($s.Footer_Adjust)   Tab/Type=$($s.Footer_Edit)   Enter=$($s.Footer_Confirm)   Esc=$($s.Footer_Cancel)")
            }
            $footer = @($footerLines)

            $newHeight = Write-TuiBox -Header $header -Body $body -Footer $footer `
                -Border:$Border -MinWidth $MinWidth -MaxWidth $MaxWidth -X $X -Y $Y `
                -SectionRules -Ascii:$asciiOn -PassThru

            if ($newHeight -lt $lastHeight -and $X -lt 0 -and $Y -lt 0) {
                $diff = $lastHeight - $newHeight
                for ($h = 0; $h -lt $diff; $h++) { Write-Host "`e[K" }
                Write-Host "`e[$($diff)A" -NoNewline
            }
            $lastHeight = $newHeight

            $key = [Console]::ReadKey($true)
            if (Test-ControlC $key) {
                throw [System.Management.Automation.PipelineStoppedException]::new()
            }

            # Tab: toggle modes. Leaving type mode commits the pending buffer.
            if ($key.Key -eq 'Tab') {
                if ($inputMode -eq 'type') {
                    . $commitBuffer
                    $inputMode = 'selection'
                } else {
                    $inputMode = 'type'
                }
                continue
            }

            if ($inputMode -eq 'type') {
                if ($key.Key -eq 'Backspace') {
                    if ($typeBuffer.Length -gt 0) {
                        $typeBuffer = $typeBuffer.Substring(0, $typeBuffer.Length - 1)
                    }
                    continue
                }
                # Arrows / Enter exit type mode (commit pending buffer). Matches
                # Get-PaginatedSelection's "nav keys exit search mode" pattern.
                if ($key.Key -in 'UpArrow','DownArrow','LeftArrow','RightArrow','Enter') {
                    . $commitBuffer
                    $inputMode = 'selection'
                    continue
                }
                if ($key.Key -eq 'Escape') {
                    # Esc in type mode discards the buffer rather than committing —
                    # the user is signalling "I don't want this edit."
                    $typeBuffer = ''
                    $inputMode = 'selection'
                    continue
                }
                $name = $fieldNames[$focusedIdx]
                if ($name -eq 'P') {
                    # AM/PM field accepts a/p shortcuts directly; no buffer needed.
                    if ([char]::IsLetter($key.KeyChar)) {
                        $c = [char]::ToLower($key.KeyChar)
                        if ($c -eq 'a' -and $totalHours -ge 12) { $totalHours -= 12 }
                        elseif ($c -eq 'p' -and $totalHours -lt 12) { $totalHours += 12 }
                    }
                    continue
                }
                if ([char]::IsDigit($key.KeyChar)) {
                    if ($typeBuffer.Length -lt 2) {
                        $typeBuffer += $key.KeyChar
                        # Auto-advance when the buffer fills, mid-type — lets
                        # the user type "1430" straight through HH:MM.
                        if ($typeBuffer.Length -eq 2 -and $focusedIdx -lt $lastFieldIdx) {
                            . $commitBuffer
                            $focusedIdx++
                        }
                    } elseif ($focusedIdx -lt $lastFieldIdx) {
                        # Buffer already full — treat the extra digit as the
                        # start of the next field's value.
                        . $commitBuffer
                        $focusedIdx++
                        $typeBuffer = "$($key.KeyChar)"
                    }
                    # At the last field with a full buffer the keystroke is dropped.
                }
                continue
            }

            # Selection mode
            switch ($key.Key) {
                'LeftArrow'  { if ($focusedIdx -gt 0) { $focusedIdx-- } }
                'RightArrow' { if ($focusedIdx -lt $lastFieldIdx) { $focusedIdx++ } }
                'UpArrow'    { . $adjustField 1 }
                'DownArrow'  { . $adjustField -1 }
                'Enter' {
                    $result = [TimeSpan]::new($totalHours, $minute, $second)
                    $running = $false
                }
                'Escape' {
                    $result = $null
                    $running = $false
                }
                default {
                    # Any printable input from selection mode either enters
                    # type mode (digit) or applies an AM/PM shortcut directly
                    # (letter on the P field) — no need to bounce through
                    # type mode for the latter.
                    if ($key.KeyChar -ne [char]0 -and -not [char]::IsControl($key.KeyChar)) {
                        $name = $fieldNames[$focusedIdx]
                        if ($name -eq 'P' -and [char]::IsLetter($key.KeyChar)) {
                            $c = [char]::ToLower($key.KeyChar)
                            if ($c -eq 'a' -and $totalHours -ge 12) { $totalHours -= 12 }
                            elseif ($c -eq 'p' -and $totalHours -lt 12) { $totalHours += 12 }
                        } elseif ([char]::IsDigit($key.KeyChar) -and $name -in 'H','M','S') {
                            $inputMode = 'type'
                            $typeBuffer = "$($key.KeyChar)"
                        }
                    }
                }
            }
        }
    } finally {
        if (-not $firstRender -and $X -lt 0 -and $Y -lt 0) {
            Write-Host "`e[$($lastHeight)A" -NoNewline
        }
        Write-Host "`e[J" -NoNewline
        Exit-RawConsole $raw
        if ($null -eq $result) { Write-Host "" }
    }

    return $result
}

function Read-Timezone {
    <#
    .SYNOPSIS
        Interactive time-zone picker built on Get-PaginatedSelection.
    .DESCRIPTION
        Lists installed system time zones and returns the chosen
        [TimeZoneInfo]. The local zone is highlighted by default; commonly-
        used zones can be pinned to the top via -PreferredTimezones, marked
        with a star. Inherits Get-PaginatedSelection's fuzzy search (Tab to
        enter search mode, type to filter) and Esc cancel.
    .PARAMETER Prompt
        Header text. Default: "Select a time zone:".
    .PARAMETER Default
        Time-zone ID to highlight initially. Default: the local system zone.
        Silently ignored if the ID isn't installed.
    .PARAMETER PreferredTimezones
        Time-zone IDs to pin to the top of the list (in caller order),
        marked with a leading star. Unknown IDs are silently skipped — the
        caller doesn't have to special-case zones that exist on some
        platforms but not others.
    .PARAMETER PageSize
        Items per page passed through to Get-PaginatedSelection. Default: 12.
    .OUTPUTS
        [TimeZoneInfo] of the chosen zone, or $null if cancelled.
    #>
    [CmdletBinding()]
    [OutputType([System.TimeZoneInfo])]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = 'Select a time zone:',

        [string]$Default = [System.TimeZoneInfo]::Local.Id,

        [string[]]$PreferredTimezones,

        [int]$PageSize = 12,

        [switch]$NoColor,
        [switch]$Ascii,
        [switch]$Border,
        [int]$MinWidth = 0,
        [int]$MaxWidth = 0,
        [int]$X = -1,
        [int]$Y = -1,
        [switch]$AltScreen
    )

    Assert-InteractiveHost 'Read-Timezone'

    $allZones = [System.TimeZoneInfo]::GetSystemTimeZones()
    $zoneById = @{}
    foreach ($z in $allZones) { $zoneById[$z.Id] = $z }

    # Preserve caller order for pinned zones; drop unknown IDs silently.
    $preferred = [System.Collections.Generic.List[System.TimeZoneInfo]]::new()
    if ($PreferredTimezones) {
        foreach ($id in $PreferredTimezones) {
            if ($zoneById.ContainsKey($id)) { [void]$preferred.Add($zoneById[$id]) }
        }
    }
    $preferredIds = [System.Collections.Generic.HashSet[string]]::new([string[]]($preferred | ForEach-Object Id))
    $rest = $allZones | Where-Object { -not $preferredIds.Contains($_.Id) } | Sort-Object DisplayName

    $items = foreach ($z in @($preferred) + @($rest)) {
        $marker = if ($preferredIds.Contains($z.Id)) { '* ' } else { '  ' }
        [PSCustomObject]@{
            Display = "$marker$($z.Id) - $($z.DisplayName)"
            Zone    = $z
        }
    }
    $items = @($items)

    $initialIndex = 0
    if ($Default) {
        for ($i = 0; $i -lt $items.Count; $i++) {
            if ($items[$i].Zone.Id -eq $Default) { $initialIndex = $i; break }
        }
    }

    # Pass-through the layout/rendering switches so callers can position the
    # picker the same way they would any other widget in the library.
    $forwarded = @{
        Items           = $items
        Title           = $Prompt
        DisplayProperty = 'Display'
        InitialIndex    = $initialIndex
        PageSize        = $PageSize
        Searchable      = $true
        Wrap            = $true
        Border          = $Border
        MinWidth        = $MinWidth
        MaxWidth        = $MaxWidth
        X               = $X
        Y               = $Y
        AltScreen       = $AltScreen
    }
    if ($PSBoundParameters.ContainsKey('NoColor')) { $forwarded['NoColor'] = $NoColor }
    if ($PSBoundParameters.ContainsKey('Ascii'))   { $forwarded['Ascii']   = $Ascii }

    $selected = Get-PaginatedSelection @forwarded

    if ($null -eq $selected) { return $null }
    return $selected.Zone
}

# --- Templated input wrappers ------------------------------------------------
# Thin opinionated wrappers around Read-MaskedInput / Read-ValidatedInput for
# the most common interactive-input shapes. Each forwards the relevant param
# subset of the underlying widget and hard-codes the mask or pattern. Callers
# who need a non-default format should use the underlying widget directly.

# Shared validation patterns (module-private). Centralized so each wrapper
# and the equivalent demo path read the exact same regex.
$script:_IPv4Pattern = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
$script:_CIDRPattern = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/(?:[0-9]|[1-2][0-9]|3[0-2])$'
$script:_EmailPattern = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
# URL: requires a scheme (http/https/ftp) and a non-empty rest. Permissive on
# the path/query — anything non-whitespace counts as a valid trailing body.
# Strict RFC 3986 enforcement is an explicit non-goal; interactive callers
# almost always want "looks like a URL" not "passes a parser".
$script:_URLPattern = '^(?:https?|ftp)://[^\s]+$'

function Read-Phone {
    <#
    .SYNOPSIS
        Masked phone-number prompt (North American format).
    .DESCRIPTION
        Thin wrapper over Read-MaskedInput with the mask hard-coded to
        (###) ###-####. For other regional formats (E.164, UK, etc.) use
        Read-MaskedInput directly with the appropriate mask.
    .PARAMETER Prompt
        Label shown before the input. Default: 'Phone:'.
    .PARAMETER Placeholder
        Character displayed for empty digit slots. Default: '_'.
    .PARAMETER AllowIncomplete
        (Switch) Allow Enter before every slot is filled.
    .PARAMETER ReturnRaw
        (Switch) Return only the typed digits, without the formatting characters.
    .OUTPUTS
        [string] — the formatted phone number, or $null on cancel.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = 'Phone:',
        [string]$Placeholder = '_',
        [switch]$AllowIncomplete,
        [switch]$ReturnRaw,
        [switch]$NoColor
    )
    Read-MaskedInput -Mask '(###) ###-####' -Prompt $Prompt -Placeholder $Placeholder `
        -AllowIncomplete:$AllowIncomplete -ReturnRaw:$ReturnRaw -NoColor:$NoColor
}

function Read-Email {
    <#
    .SYNOPSIS
        Email prompt with live regex validation.
    .DESCRIPTION
        Thin wrapper over Read-ValidatedInput with a common-practical email
        pattern. RFC 5322 perfection is not a goal — the pattern accepts the
        same shapes most websites do.
    .OUTPUTS
        [string] — the validated address, or $null on cancel.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = 'Email:',
        [switch]$AllowEmpty,
        [switch]$NoColor
    )
    Read-ValidatedInput -Prompt $Prompt -Pattern $script:_EmailPattern `
        -AllowEmpty:$AllowEmpty -NoColor:$NoColor
}

function Read-IPv4 {
    <#
    .SYNOPSIS
        IPv4 address prompt with live regex validation.
    .DESCRIPTION
        Thin wrapper over Read-ValidatedInput. The pattern enforces valid
        octets (0-255) and standard dotted-quad format.
    .OUTPUTS
        [string] — the validated address, or $null on cancel.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = 'IPv4 address:',
        [switch]$AllowEmpty,
        [switch]$NoColor
    )
    Read-ValidatedInput -Prompt $Prompt -Pattern $script:_IPv4Pattern `
        -AllowEmpty:$AllowEmpty -NoColor:$NoColor
}

function Read-CIDR {
    <#
    .SYNOPSIS
        IPv4 CIDR-notation prompt with live regex validation.
    .DESCRIPTION
        Thin wrapper over Read-ValidatedInput. The pattern enforces valid
        IPv4 octets plus a /0..32 prefix length. IPv6 CIDR is out of scope
        for this wrapper — use Read-ValidatedInput with a custom pattern.
    .OUTPUTS
        [string] — the validated CIDR string, or $null on cancel.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = 'CIDR notation:',
        [switch]$AllowEmpty,
        [switch]$NoColor
    )
    Read-ValidatedInput -Prompt $Prompt -Pattern $script:_CIDRPattern `
        -AllowEmpty:$AllowEmpty -NoColor:$NoColor
}

function Read-URL {
    <#
    .SYNOPSIS
        URL prompt with live regex validation. Accepts http(s) and ftp.
    .DESCRIPTION
        Thin wrapper over Read-ValidatedInput. The pattern requires a
        scheme (http, https, or ftp) and a non-whitespace remainder.
        Strict RFC 3986 validation is an explicit non-goal — interactive
        callers almost always want "looks like a URL" not "passes a parser".
    .OUTPUTS
        [string] — the validated URL, or $null on cancel.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = 'URL:',
        [switch]$AllowEmpty,
        [switch]$NoColor
    )
    Read-ValidatedInput -Prompt $Prompt -Pattern $script:_URLPattern `
        -AllowEmpty:$AllowEmpty -NoColor:$NoColor
}

# --- Number wrappers ---------------------------------------------------------
# Thin opinionated wrappers around Read-Number for shapes that benefit from
# locale-aware defaults. Each forwards the relevant subset of Read-Number's
# parameters; callers who need a custom format should use Read-Number directly.
# Read-Temperature is now a shim over Read-Measurement -Family Temperature;
# its per-unit data lives in units/temperature.psd1.

function Get-CurrencyFormat {
    # Internal: derive the display format for an ISO 4217 currency code.
    # Returns @{ Prefix; Suffix; Digits }. Strategy: scan specific cultures
    # for one whose RegionInfo.ISOCurrencySymbol matches the requested
    # code, then read the symbol / decimal digits / placement from that
    # culture's NumberFormat. The CurrencyPositivePattern enumeration is:
    #   0 = $n   (symbol prefix, no space)
    #   1 = n$   (symbol suffix, no space)
    #   2 = $ n  (symbol prefix, space)
    #   3 = n $  (symbol suffix, space)
    # Unknown codes fall back to the code itself as a literal prefix and
    # 2 decimal places (the most common convention globally).
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$CurrencyCode
    )
    $code = $CurrencyCode.ToUpperInvariant()
    $matchedCulture = $null
    foreach ($ci in [System.Globalization.CultureInfo]::GetCultures([System.Globalization.CultureTypes]::SpecificCultures)) {
        try {
            $ri = [System.Globalization.RegionInfo]::new($ci.Name)
            if ($ri.ISOCurrencySymbol -eq $code) {
                $matchedCulture = $ci
                break
            }
        } catch { }
    }
    if ($null -eq $matchedCulture) {
        return @{ Prefix = "$code "; Suffix = ''; Digits = 2 }
    }
    $nf = $matchedCulture.NumberFormat
    $symbol = $nf.CurrencySymbol
    switch ($nf.CurrencyPositivePattern) {
        0 { return @{ Prefix = $symbol;     Suffix = '';          Digits = $nf.CurrencyDecimalDigits } }
        1 { return @{ Prefix = '';          Suffix = $symbol;     Digits = $nf.CurrencyDecimalDigits } }
        2 { return @{ Prefix = "$symbol ";  Suffix = '';          Digits = $nf.CurrencyDecimalDigits } }
        3 { return @{ Prefix = '';          Suffix = " $symbol";  Digits = $nf.CurrencyDecimalDigits } }
        default { return @{ Prefix = $symbol; Suffix = '';        Digits = $nf.CurrencyDecimalDigits } }
    }
}

function Format-ValueBar {
    # Internal: render a value-in-range as a fixed-width progress bar
    # string. Used by Read-Number -Bar (and transitively Read-Percentage
    # -Bar). Returns "[████████░░░░░░░░░░░░] " (Unicode/color) or
    # "[####------] " (ASCII/no-color). Filled cells are
    # round((Value-Min)/(Max-Min) * Width); ratio clamps to [0, 1] so
    # values outside [Min, Max] still render a sensible bar end. When
    # Min == Max, ratio is treated as 1 (fully filled — degenerate range
    # has no meaningful "progress" but a full bar is the saner default).
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][decimal]$Value,
        [Parameter(Mandatory)][decimal]$Min,
        [Parameter(Mandatory)][decimal]$Max,
        [Parameter(Mandatory)][ValidateRange(1, 200)][int]$Width,
        [switch]$Ascii,
        [switch]$NoColor
    )
    $range = [double]($Max - $Min)
    $ratio = if ($range -le 0) { 1.0 } else { [double]($Value - $Min) / $range }
    if ($ratio -lt 0.0) { $ratio = 0.0 }
    if ($ratio -gt 1.0) { $ratio = 1.0 }
    $filled = [int][Math]::Round($ratio * $Width)
    if ($filled -lt 0)     { $filled = 0 }
    if ($filled -gt $Width) { $filled = $Width }
    $empty = $Width - $filled
    $glyphs = Get-Glyphs ([bool]$Ascii)
    $filledStr = $glyphs.BarFill * $filled
    $emptyStr = $glyphs.BarEmpty * $empty
    if ($NoColor) {
        return "[$filledStr$emptyStr] "
    }
    # Green fill, dim gray empty; reset at the end so subsequent text
    # (prefix / numeric value) renders in the host's default style.
    return "[`e[92m$filledStr`e[90m$emptyStr`e[0m] "
}

function Read-Percentage {
    <#
    .SYNOPSIS
        Percentage prompt (0..100) with optional fractional return and bar.
    .DESCRIPTION
        Thin wrapper over Read-Number rendering a ' %' suffix. The on-screen
        range is always 0..100; that's also the default return value. Pass
        -AsFraction to receive the value divided by 100 (useful when piping
        into a multiplier downstream). -Bar / -BarWidth / -Ascii are
        forwarded to Read-Number; see its help for full bar semantics.
    .PARAMETER Prompt
        Label shown before the input. Default: 'Percentage:'.
    .PARAMETER Default
        Initial value in 0..100. Default: 0.
    .PARAMETER Precision
        Fractional decimal places (e.g. -Precision 1 accepts 12.5%).
        Default: 0 (integer percentages only).
    .PARAMETER AsFraction
        Return value/100 (so 75 → 0.75). On-screen display is unchanged.
    .PARAMETER Bar
        Show a live progress bar between the prompt and the numeric value
        (e.g. "Coverage: [██████████░░░░░░░░░░] 50 %"). Forwarded to
        Read-Number -Bar.
    .PARAMETER BarWidth
        Bar width in characters. Default: 20. Forwarded to Read-Number.
    .PARAMETER Ascii
        Force ASCII bar glyphs ('#'/'-'). Forwarded to Read-Number.
    .OUTPUTS
        [decimal] 0..100 by default, or 0..1 with -AsFraction; $null on Escape.
    #>
    [CmdletBinding()]
    [OutputType([decimal])]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = 'Percentage:',
        [decimal]$Default = 0,
        [ValidateRange(0, 6)][int]$Precision = 0,
        [switch]$AsFraction,
        [switch]$Bar,
        [ValidateRange(5, 80)][int]$BarWidth = 20,
        [switch]$Ascii,
        [switch]$NoColor
    )
    $forwarded = @{
        Prompt    = $Prompt
        Min       = [decimal]0
        Max       = [decimal]100
        Default   = $Default
        Precision = $Precision
        Suffix    = ' %'
        NoColor   = $NoColor
        Bar       = $Bar
        BarWidth  = $BarWidth
        Ascii     = $Ascii
    }
    $val = Read-Number @forwarded
    if ($null -eq $val) { return $null }
    if ($AsFraction) {
        return [Math]::Round($val / 100, $Precision + 2)
    }
    return $val
}

function Read-Temperature {
    <#
    .SYNOPSIS
        Temperature prompt with locale-derived unit default.
    .DESCRIPTION
        Thin shim over Read-Measurement -Family Temperature. When -Unit is
        omitted, picks Fahrenheit for regions that conventionally use it
        (US, BS, BZ, KY, PW, FM, MH, LR) and Celsius otherwise — both lists
        live in units/temperature.psd1, not in code. Kelvin is only
        selected on explicit request. Per-unit defaults for -Min / -Max /
        -Default cover the terrestrial weather / HVAC range and come from
        the same family file's UnitDefaults block; pass them explicitly to
        override (e.g. for body-temperature or scientific work).
    .PARAMETER Prompt
        Label shown before the input. Default: 'Temperature:'.
    .PARAMETER Unit
        Celsius, Fahrenheit, or Kelvin. Defaults to the region's convention.
    .PARAMETER Min
        Minimum value (in the chosen unit). Defaults per unit.
    .PARAMETER Max
        Maximum value (in the chosen unit). Defaults per unit.
    .PARAMETER Default
        Initial value (in the chosen unit). Defaults per unit.
    .PARAMETER Precision
        Decimal places. Default: 0.
    .OUTPUTS
        [decimal] in the chosen unit, or $null on Escape.
    #>
    [CmdletBinding()]
    [OutputType([decimal])]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = 'Temperature:',
        [ValidateSet('Celsius', 'Fahrenheit', 'Kelvin')]
        [string]$Unit,
        [decimal]$Min,
        [decimal]$Max,
        [decimal]$Default,
        [ValidateRange(0, 6)][int]$Precision = 0,
        [switch]$NoColor
    )
    # Family-file unit names are lowercase; the legacy -Unit values are
    # title-case. Bridge them here so callers do not need to change.
    $forward = @{
        Prompt         = $Prompt
        Family         = 'Temperature'
        DefaultsByUnit = $true
        ShowConversion = $false
        Precision      = $Precision
        NoColor        = $NoColor
    }
    if ($PSBoundParameters.ContainsKey('Unit') -and -not [string]::IsNullOrEmpty($Unit)) {
        $forward.OutputUnit = $Unit.ToLowerInvariant()
        $forward.InputUnit  = $Unit.ToLowerInvariant()
    }
    if ($PSBoundParameters.ContainsKey('Min'))     { $forward.Min = $Min }
    if ($PSBoundParameters.ContainsKey('Max'))     { $forward.Max = $Max }
    if ($PSBoundParameters.ContainsKey('Default')) { $forward.Default = $Default }
    return Read-Measurement @forward
}

function Read-Currency {
    <#
    .SYNOPSIS
        Currency-amount prompt with locale-derived format.
    .DESCRIPTION
        Thin wrapper over Read-Number that decorates the field with the
        chosen currency's symbol in its native position ('$1,234.56' for
        USD, '1.234,56 €' for EUR under de-DE, '¥1234' for JPY). When
        -Currency is omitted, defaults to the current region's currency via
        [RegionInfo]::CurrentRegion.ISOCurrencySymbol. Decimal precision
        defaults to the currency's NumberFormat.CurrencyDecimalDigits
        (2 for USD/EUR/GBP, 0 for JPY/KRW, 3 for BHD/KWD).

        Note: this widget *captures* a value in one currency; it does NOT
        convert between currencies. The thousands / decimal separators
        displayed follow the user's current culture (matching their
        keyboard expectations), not the currency's home culture — a French
        user entering USD sees '$' but separators in the French style.
    .PARAMETER Prompt
        Label shown before the input. Default: 'Amount:'.
    .PARAMETER Currency
        ISO 4217 currency code (USD, EUR, GBP, JPY, ...). Defaults to the
        current region's currency. Unknown codes fall back to using the
        code itself as a literal prefix and 2 decimal places.
    .PARAMETER Min
        Minimum amount. Default: 0.
    .PARAMETER Max
        Maximum amount. Default: 999,999,999.
    .PARAMETER Default
        Initial amount. Default: 0.
    .PARAMETER Precision
        Decimal places. Defaults to the currency's natural precision.
    .OUTPUTS
        [decimal] amount in the chosen currency, or $null on Escape.
    #>
    [CmdletBinding()]
    [OutputType([decimal])]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = 'Amount:',
        [string]$Currency,
        [decimal]$Min = 0,
        [decimal]$Max = 999999999,
        [decimal]$Default = 0,
        [ValidateRange(0, 6)][int]$Precision,
        [switch]$NoColor
    )
    if (-not $PSBoundParameters.ContainsKey('Currency') -or [string]::IsNullOrEmpty($Currency)) {
        try {
            $Currency = [System.Globalization.RegionInfo]::CurrentRegion.ISOCurrencySymbol
        } catch {
            $Currency = 'USD'
        }
    }
    $fmt = Get-CurrencyFormat -CurrencyCode $Currency
    if (-not $PSBoundParameters.ContainsKey('Precision')) {
        $Precision = $fmt.Digits
    }
    Read-Number -Prompt $Prompt -Min $Min -Max $Max -Default $Default `
        -Precision $Precision -Prefix $fmt.Prefix -Suffix $fmt.Suffix `
        -ThousandsSeparator -NoColor:$NoColor
}

# --- Measurement engine ------------------------------------------------------
# A generic "value-with-units" widget plus its loader. Each family file in
# units/<name>.psd1 contains the unit set, aliases, conversion ratios (or
# affine Scale/Offset for things like temperature), and region-based output
# preference. The engine walks whatever the loaded family gives it — no
# measurement family is hardcoded in the engine itself, so adding a new one
# is a data drop, not a code change. If a family file is missing,
# Read-Measurement degrades to plain numeric input rather than throwing.

function Import-MeasurementFamily {
    # Internal: load units/<Family>.psd1 from the module directory. Returns
    # the parsed hashtable, or $null if the file does not exist or fails to
    # load. Verbose-only on failure so a typo in -Family degrades to the
    # plain numeric fallback inside Read-Measurement rather than throwing.
    # Filename match is case-insensitive so callers can write -Family Length
    # against units/length.psd1 cross-platform (Linux/macOS file paths are
    # case-sensitive; matching the case-insensitive convention from .NET
    # culture/region lookups keeps -Family ergonomic).
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Family)
    $dir = Join-Path $PSScriptRoot 'units'
    if (-not (Test-Path -LiteralPath $dir)) {
        Write-Verbose "Measurement units directory not found at $dir; falling back to numeric-only."
        return $null
    }
    $match = Get-ChildItem -LiteralPath $dir -Filter '*.psd1' -ErrorAction SilentlyContinue |
        Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -ieq $Family } |
        Select-Object -First 1
    if ($null -eq $match) {
        Write-Verbose "Measurement family '$Family' not found in $dir; falling back to numeric-only."
        return $null
    }
    try {
        return Import-PowerShellDataFile -LiteralPath $match.FullName
    } catch {
        Write-Verbose "Measurement family '$Family' failed to load: $_; falling back."
        return $null
    }
}

function Get-MeasurementFamily {
    # Enumerate available family files (filename without extension). Useful
    # for callers building UI around the bundled families and for the test
    # suite. Returns @() when the units/ directory is missing.
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    $dir = Join-Path $PSScriptRoot 'units'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    Get-ChildItem -LiteralPath $dir -Filter '*.psd1' -ErrorAction SilentlyContinue |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }
}

function ConvertTo-MeasurementBase {
    # Internal: convert $Value (in $UnitName) to the family's base unit.
    # ToBase convention: base_value = (input + Offset) * Scale. A bare
    # numeric ToBase is shorthand for @{ Scale = N; Offset = 0 } — pure
    # ratios (length, mass) collapse to multiplication, affine units
    # (Fahrenheit, Kelvin) carry an Offset.
    [CmdletBinding()]
    [OutputType([decimal])]
    param(
        [Parameter(Mandatory)][decimal]$Value,
        [Parameter(Mandatory)][hashtable]$Family,
        [Parameter(Mandatory)][string]$UnitName
    )
    $unit = $Family.Units | Where-Object { $_.Name -eq $UnitName } | Select-Object -First 1
    if ($null -eq $unit) {
        throw "Unit '$UnitName' not defined in family '$($Family.Family)'."
    }
    $toBase = $unit.ToBase
    if ($toBase -is [hashtable]) {
        return ([decimal]$Value + [decimal]$toBase.Offset) * [decimal]$toBase.Scale
    }
    return [decimal]$Value * [decimal]$toBase
}

function ConvertFrom-MeasurementBase {
    # Internal: inverse of ConvertTo-MeasurementBase. For the affine form:
    # output = (base / Scale) - Offset. For the pure-ratio form: output =
    # base / Scale.
    [CmdletBinding()]
    [OutputType([decimal])]
    param(
        [Parameter(Mandatory)][decimal]$BaseValue,
        [Parameter(Mandatory)][hashtable]$Family,
        [Parameter(Mandatory)][string]$UnitName
    )
    $unit = $Family.Units | Where-Object { $_.Name -eq $UnitName } | Select-Object -First 1
    if ($null -eq $unit) {
        throw "Unit '$UnitName' not defined in family '$($Family.Family)'."
    }
    $toBase = $unit.ToBase
    if ($toBase -is [hashtable]) {
        return ([decimal]$BaseValue / [decimal]$toBase.Scale) - [decimal]$toBase.Offset
    }
    return [decimal]$BaseValue / [decimal]$toBase
}

function Get-MeasurementOutputUnit {
    # Internal: pick the default output unit for a family based on region.
    # ImperialRegions (when present) overrides .NET's IsMetric for the listed
    # ISO-3166 codes — matches how the original Read-Temperature classified
    # the eight Fahrenheit-using regions independent of locale metadata.
    # Falls back to the family Base when DefaultOutputUnit is omitted or
    # resolves to an empty string.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][hashtable]$Family)
    if (-not $Family.ContainsKey('DefaultOutputUnit')) { return $Family.Base }
    $regionCode = ''
    try { $regionCode = [System.Globalization.RegionInfo]::CurrentRegion.TwoLetterISORegionName } catch { }
    $isImperial = $false
    if ($Family.ContainsKey('ImperialRegions') -and $regionCode -in $Family.ImperialRegions) {
        $isImperial = $true
    } else {
        try { $isImperial = -not [System.Globalization.RegionInfo]::CurrentRegion.IsMetric } catch { }
    }
    $picked = if ($isImperial) { $Family.DefaultOutputUnit.Imperial } else { $Family.DefaultOutputUnit.Metric }
    if ([string]::IsNullOrEmpty($picked)) { return $Family.Base }
    return $picked
}

function ConvertTo-MeasurementValue {
    # Internal: parse a buffer into a base-unit [decimal] using a family's
    # aliases. Returns @{ Ok; Value; Reason; Components }.
    #
    # Grammar (informal):
    #   measurement   := (signed-number unit?)+
    #   signed-number := [-+]? digit+ (decimalSep digit+)?
    #   unit          := one of the family's aliases (case-sensitive, longest match wins)
    #
    # Bare numbers (no alias) are assigned $InputUnit if supplied, otherwise
    # the family's Base unit. Compound input like "12ft 3in" parses as two
    # number/unit pairs whose base contributions sum. Range is enforced by
    # the caller against -Min/-Max; this parser only flags 'empty',
    # 'unparseable', or 'unknown-unit'.
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Buffer,
        [Parameter(Mandatory)][hashtable]$Family,
        [string]$InputUnit,
        [System.Globalization.CultureInfo]$Culture = ([System.Globalization.CultureInfo]::CurrentCulture)
    )
    if ([string]::IsNullOrWhiteSpace($Buffer)) {
        return @{ Ok = $false; Value = [decimal]0; Reason = 'empty'; Components = @() }
    }

    # Alias -> unit lookup, sorted longest-first so "feet" wins over "ft"
    # and multi-char aliases beat single-char overlaps.
    $aliasMap = [ordered]@{}
    foreach ($u in $Family.Units) {
        $allAliases = @($u.Name) + @($u.Aliases)
        foreach ($a in $allAliases) {
            if (-not [string]::IsNullOrEmpty($a)) { $aliasMap[$a] = $u.Name }
        }
    }
    $aliasesByLength = @($aliasMap.Keys | Sort-Object { $_.Length } -Descending)

    $fallbackUnit = if ($InputUnit) { $InputUnit } else { $Family.Base }
    $dotChar = $Culture.NumberFormat.NumberDecimalSeparator

    $pos = 0
    $components = @()
    while ($pos -lt $Buffer.Length) {
        while ($pos -lt $Buffer.Length -and [char]::IsWhiteSpace($Buffer[$pos])) { $pos++ }
        if ($pos -ge $Buffer.Length) { break }

        $numStart = $pos
        if ($Buffer[$pos] -eq '-' -or $Buffer[$pos] -eq '+') { $pos++ }
        $sawDigit = $false
        while ($pos -lt $Buffer.Length -and [char]::IsDigit($Buffer[$pos])) { $pos++; $sawDigit = $true }
        if ($pos -lt $Buffer.Length -and ([string]$Buffer[$pos]) -eq $dotChar) {
            $pos++
            while ($pos -lt $Buffer.Length -and [char]::IsDigit($Buffer[$pos])) { $pos++; $sawDigit = $true }
        }
        if (-not $sawDigit) {
            return @{ Ok = $false; Value = [decimal]0; Reason = 'unparseable'; Components = $components }
        }
        $numText = $Buffer.Substring($numStart, $pos - $numStart)
        $parsedNum = [decimal]0
        if (-not [decimal]::TryParse($numText, [System.Globalization.NumberStyles]::Float, $Culture, [ref]$parsedNum)) {
            return @{ Ok = $false; Value = [decimal]0; Reason = 'unparseable'; Components = $components }
        }

        # Optional whitespace, then optional unit alias.
        while ($pos -lt $Buffer.Length -and [char]::IsWhiteSpace($Buffer[$pos])) { $pos++ }
        $matchedAlias = $null
        if ($pos -lt $Buffer.Length) {
            foreach ($a in $aliasesByLength) {
                if ($Buffer.Length - $pos -ge $a.Length -and
                    $Buffer.Substring($pos, $a.Length) -ceq $a) {
                    $matchedAlias = $a
                    $pos += $a.Length
                    break
                }
            }
            if ($null -eq $matchedAlias) {
                return @{ Ok = $false; Value = [decimal]0; Reason = 'unknown-unit'; Components = $components }
            }
        }
        $unitName = if ($matchedAlias) { $aliasMap[$matchedAlias] } else { $fallbackUnit }
        $components += @{ Number = $parsedNum; Unit = $unitName }
    }

    if ($components.Count -eq 0) {
        return @{ Ok = $false; Value = [decimal]0; Reason = 'empty'; Components = @() }
    }

    $baseSum = [decimal]0
    foreach ($c in $components) {
        $baseSum += ConvertTo-MeasurementBase -Value $c.Number -Family $Family -UnitName $c.Unit
    }
    return @{ Ok = $true; Value = $baseSum; Reason = ''; Components = $components }
}

function Read-Measurement {
    <#
    .SYNOPSIS
        Mixed-unit measurement input driven by data files in units/.
    .DESCRIPTION
        Generic numeric-with-units widget. The -Family parameter names a
        units/<family>.psd1 data file (Length, Temperature, Mass, ...);
        the engine knows nothing about specific units, only how to walk
        whatever the loaded family provides. Input like "12ft 3in",
        "5'11\"", or "100cm" is parsed via the family's aliases (longest
        match wins, case-sensitive); compound terms sum in the family's
        base unit; bare numbers fall back to -InputUnit (which itself
        defaults to -OutputUnit).
        When -ShowConversion is on, a live decorator shows the value
        converted into -OutputUnit between the prompt and the field. If
        the requested family file is missing, the widget silently degrades
        to plain Read-Number behavior.
    .PARAMETER Prompt
        Label shown before the input field.
    .PARAMETER Family
        Family name. Resolves to units/<Family>.psd1 in the module dir.
    .PARAMETER Min
        Lower bound (inclusive), expressed in -OutputUnit. When omitted and
        -DefaultsByUnit is set with a matching UnitDefaults entry, uses the
        family's per-unit Min.
    .PARAMETER Max
        Upper bound (inclusive), expressed in -OutputUnit. Same fallback
        chain as -Min.
    .PARAMETER Default
        Initial value, expressed in -OutputUnit.
    .PARAMETER OutputUnit
        Unit used for display, the conversion decorator, and -Min/-Max
        interpretation. Defaults to the family's region-derived choice
        via Get-MeasurementOutputUnit.
    .PARAMETER InputUnit
        Unit assumed for bare numbers (without an alias). Defaults to
        -OutputUnit, matching the "I'm typing in the unit I see" model.
    .PARAMETER DefaultsByUnit
        Pull Min / Max / Default from the family's UnitDefaults[OutputUnit]
        block instead of requiring them as arguments. Explicit -Min / -Max
        / -Default still win for partial overrides.
    .PARAMETER ShowConversion
        Render a live [~ value OutputUnit] decoration between the prompt
        and the input. On by default; pass -ShowConversion:$false to hide.
    .PARAMETER Precision
        Decimal places passed through to Read-Number. Defaults to 0.
    .PARAMETER Prefix
        Literal prefix forwarded to Read-Number.
    .PARAMETER Suffix
        Literal suffix forwarded to Read-Number.
    .PARAMETER NoColor
        Suppress color; forwarded to Read-Number.
    .PARAMETER Bar
        Render a live progress bar tracking the value between Min and Max
        (in base units). Forwarded to Read-Number.
    .PARAMETER BarWidth
        Bar width in characters. Forwarded to Read-Number.
    .PARAMETER Ascii
        Force ASCII glyphs for the bar and the conversion decorator.
    .EXAMPLE
        PS> Read-Measurement -Prompt 'Distance:' -Family Length -DefaultsByUnit
    .EXAMPLE
        PS> Read-Measurement -Prompt 'Height:' -Family Length `
                             -OutputUnit foot -Min 0 -Max 8 -Default 5.5
    .OUTPUTS
        [decimal] value expressed in -OutputUnit (so a caller asking for
        -OutputUnit foot gets feet back; asking for celsius gets celsius
        back). Internally the engine pivots through the family's base
        unit, but that's an implementation detail. Returns $null on Escape.
    #>
    [CmdletBinding()]
    [OutputType([decimal])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Prompt,
        [Parameter(Mandatory)][string]$Family,
        [decimal]$Min,
        [decimal]$Max,
        [decimal]$Default,
        [string]$OutputUnit,
        [string]$InputUnit,
        [switch]$DefaultsByUnit,
        [switch]$ShowConversion = $true,
        [ValidateRange(0, 6)][int]$Precision = 0,
        [string]$Prefix = '',
        [string]$Suffix = '',
        [switch]$NoColor,
        [switch]$Bar,
        [ValidateRange(5, 80)][int]$BarWidth = 20,
        [switch]$Ascii
    )

    $fam = Import-MeasurementFamily -Family $Family

    if ($null -eq $fam) {
        # Graceful fallback: family file missing or unparseable. Forward only
        # the numeric pass-throughs to Read-Number. -Min/-Max are required
        # by Read-Number, so if the caller didn't supply them in this branch
        # the error will surface there with the original Read-Number message.
        $forward = @{
            Prompt    = $Prompt
            Precision = $Precision
            Prefix    = $Prefix
            Suffix    = $Suffix
            NoColor   = $NoColor
            Bar       = $Bar
            BarWidth  = $BarWidth
            Ascii     = $Ascii
        }
        if ($PSBoundParameters.ContainsKey('Min'))     { $forward.Min = $Min }
        if ($PSBoundParameters.ContainsKey('Max'))     { $forward.Max = $Max }
        if ($PSBoundParameters.ContainsKey('Default')) { $forward.Default = $Default }
        return Read-Number @forward
    }

    if (-not $PSBoundParameters.ContainsKey('OutputUnit') -or [string]::IsNullOrEmpty($OutputUnit)) {
        $OutputUnit = Get-MeasurementOutputUnit -Family $fam
    }
    if (-not $PSBoundParameters.ContainsKey('InputUnit') -or [string]::IsNullOrEmpty($InputUnit)) {
        $InputUnit = $OutputUnit
    }

    # Resolve Min/Max/Default. Order: explicit caller arg > family's
    # UnitDefaults[OutputUnit] (when -DefaultsByUnit) > error / fallback.
    $unitDefaults = $null
    if ($DefaultsByUnit -and $fam.ContainsKey('UnitDefaults') -and $fam.UnitDefaults.ContainsKey($OutputUnit)) {
        $unitDefaults = $fam.UnitDefaults[$OutputUnit]
    }

    if (-not $PSBoundParameters.ContainsKey('Min')) {
        if ($null -ne $unitDefaults -and $unitDefaults.ContainsKey('Min')) {
            $Min = [decimal]$unitDefaults.Min
        } else {
            throw "Read-Measurement: -Min is required when -DefaultsByUnit is not set or family '$Family' has no UnitDefaults entry for '$OutputUnit'."
        }
    }
    if (-not $PSBoundParameters.ContainsKey('Max')) {
        if ($null -ne $unitDefaults -and $unitDefaults.ContainsKey('Max')) {
            $Max = [decimal]$unitDefaults.Max
        } else {
            throw "Read-Measurement: -Max is required when -DefaultsByUnit is not set or family '$Family' has no UnitDefaults entry for '$OutputUnit'."
        }
    }
    if (-not $PSBoundParameters.ContainsKey('Default')) {
        if ($null -ne $unitDefaults -and $unitDefaults.ContainsKey('Default')) {
            $Default = [decimal]$unitDefaults.Default
        } else {
            $Default = $Min
        }
    }

    # -Min/-Max/-Default are in OutputUnit; Read-Number works in base units.
    $baseMin     = ConvertTo-MeasurementBase -Value $Min     -Family $fam -UnitName $OutputUnit
    $baseMax     = ConvertTo-MeasurementBase -Value $Max     -Family $fam -UnitName $OutputUnit
    $baseDefault = ConvertTo-MeasurementBase -Value $Default -Family $fam -UnitName $OutputUnit
    if ($baseMin -gt $baseMax) {
        # Affine conversions can flip ordering (e.g. negative Scale would,
        # though no shipped family uses one). Swap so Read-Number doesn't
        # reject the range. With all current families this branch is dead.
        $tmp = $baseMin; $baseMin = $baseMax; $baseMax = $tmp
    }

    # Suffix resolution: a caller-supplied -Suffix always wins. Otherwise
    # fall back to the OutputUnit entry's Suffix property (e.g. temperature
    # units carry ' °C', ' °F', ' K'). This is what preserves the legacy
    # Read-Temperature display when the shim forwards through here.
    if (-not $PSBoundParameters.ContainsKey('Suffix') -or [string]::IsNullOrEmpty($Suffix)) {
        $unitEntry = $fam.Units | Where-Object { $_.Name -eq $OutputUnit } | Select-Object -First 1
        if ($null -ne $unitEntry -and $unitEntry.ContainsKey('Suffix')) {
            $Suffix = [string]$unitEntry.Suffix
        }
    }

    $culture = [System.Globalization.CultureInfo]::CurrentCulture

    # Closure scope (same gotcha as Read-Number -Bar's decorator and
    # Read-Percentage -Bar's pass-through): GetNewClosure() strips module
    # session state, so module-private functions cannot be called by name
    # from inside the closure body. Capture the function bodies up-front
    # via ${function:...} and dispatch with &.
    $parserFn   = ${function:ConvertTo-MeasurementValue}
    $toBaseFn   = ${function:ConvertTo-MeasurementBase}
    $fromBaseFn = ${function:ConvertFrom-MeasurementBase}

    $famLocal       = $fam
    $inputUnitLocal = $InputUnit
    $outputLocal    = $OutputUnit
    $minLocal       = $baseMin
    $maxLocal       = $baseMax
    $cultureLocal   = $culture

    $bufferParser = {
        param($buf)
        $r = & $parserFn -Buffer $buf -Family $famLocal -InputUnit $inputUnitLocal -Culture $cultureLocal
        if ($r.Ok) {
            if ($r.Value -lt $minLocal -or $r.Value -gt $maxLocal) {
                return @{ Ok = $false; Value = $r.Value; Reason = 'range' }
            }
        }
        return $r
    }.GetNewClosure()

    $forward = @{
        Prompt       = $Prompt
        Min          = $baseMin
        Max          = $baseMax
        Default      = $baseDefault
        Precision    = $Precision
        Prefix       = $Prefix
        Suffix       = $Suffix
        NoColor      = $NoColor
        Bar          = $Bar
        BarWidth     = $BarWidth
        Ascii        = $Ascii
        BufferParser = $bufferParser
    }

    if ($ShowConversion) {
        $asciiOn = if ($PSBoundParameters.ContainsKey('Ascii')) { [bool]$Ascii } else { $script:_AsciiMode }
        $asciiLocal = $asciiOn
        $decorator = {
            param($v)
            $converted = & $fromBaseFn -BaseValue ([decimal]$v) -Family $famLocal -UnitName $outputLocal
            $glyph = if ($asciiLocal) { '~' } else { [char]0x2248 }
            return ("[{0} {1:N2} {2}] " -f $glyph, $converted, $outputLocal)
        }.GetNewClosure()
        if (-not $Bar) {
            $forward.Decorator = $decorator
        }
    }

    $baseResult = Read-Number @forward
    if ($null -eq $baseResult) { return $null }
    return ConvertFrom-MeasurementBase -BaseValue ([decimal]$baseResult) -Family $fam -UnitName $OutputUnit
}

Export-ModuleMember -Function Write-TuiBox, Format-TuiColumn, Format-TuiWrap, Get-PaginatedSelection, Read-MaskedInput, Read-Password, Read-ValidatedInput, Read-Number, Read-Confirmation, Read-Choice, Show-Spinner, Write-Spinner, Set-SpinnerActivity, Invoke-NestedMenu, Measure-FuzzyMatch, Read-Date, Read-Time, Read-Timezone, Read-Phone, Read-Email, Read-IPv4, Read-CIDR, Read-URL, Read-Percentage, Read-Temperature, Read-Currency, Read-Measurement, Get-MeasurementFamily
