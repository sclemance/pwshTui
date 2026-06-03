BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'pwshTui.psd1'
    Import-Module $modulePath -Force

    # Get-DisplayWidth and Get-VisibleSubstring each carry their OWN inline copy
    # of the East-Asian wide-range table (a deliberate hot-path perf choice — see
    # the comment at Get-VisibleSubstring). These tests pin the two copies to the
    # same classification so they can never silently drift: if they disagreed,
    # measured width would differ from truncated width and aligned columns would
    # shear. The check exploits the fact that a single character fits in a
    # 1-cell budget iff Get-DisplayWidth rates it exactly 1 cell.
    function Test-CharAgreement {
        param([int]$Cp)
        & (Get-Module pwshTui) {
            param($cp)
            $c     = [char]::ConvertFromUtf32($cp)
            $w     = Get-DisplayWidth $c
            $fits1 = Get-VisibleSubstring $c 1
            [pscustomobject]@{ Cp = $cp; Width = $w; Fits1 = $fits1; Char = $c }
        } $Cp
    }
}

Describe 'Get-DisplayWidth / Get-VisibleSubstring agreement' {

    Context 'Per-codepoint: a char fits a 1-cell budget iff its width is 1' {
        # Boundaries of every wide range (just inside / just outside), so a future
        # edit to one table that misses the other is caught at the seam.
        $boundaries = @(
            0x10FF,0x1100,0x115F,0x1160,   # Hangul Jamo
            0x2E7F,0x2E80,0x303E,0x303F,   # CJK Radicals / Kangxi
            0x3040,0x3041,0x33FF,0x3400,   # Hiragana/Katakana .. CJK Ext A start
            0x4DBF,0x4E00,0x9FFF,0xA000,   # CJK Unified
            0xABFF,0xAC00,0xD7A3,0xD7A4,   # Hangul Syllables
            0xF8FF,0xF900,0xFAFF,0xFB00,   # CJK Compatibility Ideographs
            0xFF00,0xFF60,0xFF61,          # Fullwidth Forms
            0x1F300,0x1F64F,0x1F900,0x1F9FF, # emoji blocks
            0x20000,0x3FFFD,               # CJK Ext B+ (astral)
            0x41,0x7E,0x20AC,0x2026        # ASCII + a couple narrow non-ASCII
        )
        It 'agrees on codepoint U+<cp>' -ForEach $boundaries {
            $r = Test-CharAgreement $_
            if ($r.Width -eq 1) {
                $r.Fits1 | Should -BeExactly $r.Char -Because ("U+{0:X4} is 1 cell so it must fit a 1-cell slice" -f $_)
            } else {
                $r.Fits1 | Should -BeExactly '' -Because ("U+{0:X4} is {1} cells so it must NOT fit a 1-cell slice" -f $_, $r.Width)
            }
        }
    }

    Context 'Per-codepoint: randomized fuzz across the BMP and astral planes' {
        It 'agrees on a fuzz sample' {
            $rng = [Random]::new(20260603)  # fixed seed → reproducible failures
            foreach ($n in 1..600) {
                # Mix BMP (skip surrogate range 0xD800-0xDFFF) and astral.
                $cp = if ($n % 5 -eq 0) { $rng.Next(0x10000, 0x3FFFE) } else { $rng.Next(0x20, 0xFFFE) }
                if ($cp -ge 0xD800 -and $cp -le 0xDFFF) { continue }
                $r = Test-CharAgreement $cp
                if ($r.Width -eq 1) {
                    $r.Fits1 | Should -BeExactly $r.Char -Because ("U+{0:X4}" -f $cp)
                } else {
                    $r.Fits1 | Should -BeExactly '' -Because ("U+{0:X4} width={1}" -f $cp, $r.Width)
                }
            }
        }
    }

    Context 'Whole-string: slicing at the measured width is a no-op' {
        It 'returns the full string when the budget equals its display width' {
            $samples = @(
                'plain ascii',
                "wide 日本語 mix",
                "emoji 🎉 tail",
                "fullwidth ＡＢＣ here",
                "$([char]27)[31mstyled$([char]27)[0m"
            )
            foreach ($s in $samples) {
                & (Get-Module pwshTui) {
                    param($s)
                    $w   = Get-DisplayWidth $s
                    $cut = Get-VisibleSubstring $s $w
                    # Slicing at exactly the measured width must not drop anything.
                    (Get-DisplayWidth $cut) | Should -Be $w
                    (Get-VisibleSubstring $s 10000) | Should -BeExactly $s
                } $s
            }
        }
    }
}
