BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'pwshTui.psd1'
    Import-Module $modulePath -Force
}

Describe 'Write-TuiBox' {

    # Write-TuiBox writes to the host via Write-Host (information stream 6).
    # Suppressing stream 6 keeps test output clean; we assert on the return value
    # (frame line count) which is sufficient to verify layout decisions.

    Context 'Frame count without border' {
        It 'returns body-line count for body only' {
            $count = Write-TuiBox -Body @('one') -PassThru 6>$null
            $count | Should -Be 1
        }
        It 'returns header + body + footer with no separators' {
            $count = Write-TuiBox -Header @('h') -Body @('b') -Footer @('f') -PassThru 6>$null
            $count | Should -Be 3
        }
        It 'handles multi-line sections' {
            $count = Write-TuiBox -Header @('h1','h2') -Body @('b1','b2','b3') -Footer @('f1') -PassThru 6>$null
            $count | Should -Be 6
        }
    }

    Context 'Frame count with border' {
        It 'returns top + body + bottom = body+2' {
            $count = Write-TuiBox -Body @('one') -Border -PassThru 6>$null
            $count | Should -Be 3
        }
        It 'adds a separator between header and body' {
            $count = Write-TuiBox -Header @('h') -Body @('b') -Border -PassThru 6>$null
            # top + header + rule + body + bottom
            $count | Should -Be 5
        }
        It 'adds a separator between body and footer' {
            $count = Write-TuiBox -Body @('b') -Footer @('f') -Border -PassThru 6>$null
            # top + body + rule + footer + bottom
            $count | Should -Be 5
        }
        It 'returns the full 7-row layout for header + body + footer' {
            $count = Write-TuiBox -Header @('h') -Body @('b') -Footer @('f') -Border -PassThru 6>$null
            # top + header + rule + body + rule + footer + bottom
            $count | Should -Be 7
        }
        It 'scales with multi-line sections' {
            $count = Write-TuiBox -Header @('h1','h2') -Body @('b1','b2','b3') -Footer @('f1','f2') -Border -PassThru 6>$null
            # top + 2 header + rule + 3 body + rule + 2 footer + bottom
            $count | Should -Be 11
        }
    }

    Context 'Truncation does not change frame count' {
        It 'still returns body-line count when a body line is truncated' {
            $longLine = 'x' * 200
            $count = Write-TuiBox -Body @($longLine) -Border -MaxWidth 20 -PassThru 6>$null
            $count | Should -Be 3  # top + 1 truncated body + bottom
        }
        It 'preserves frame count for an ANSI-styled long line' {
            $ansiLong = "`e[36m> `e[46;30m" + ('y' * 200) + "`e[0m"
            $count = Write-TuiBox -Body @($ansiLong) -Border -MaxWidth 20 -PassThru 6>$null
            $count | Should -Be 3
        }
    }

    Context 'Note section' {
        It 'fences the note with rules between body and footer (SectionRules)' {
            # body3 + rule + note2 + rule + footer1
            $count = Write-TuiBox -Body @('b1','b2','b3') -Note @('n1','n2') -Footer @('f') `
                                  -SectionRules -PassThru 6>$null
            $count | Should -Be 8
        }
        It 'adds no rules for a note without SectionRules or Border' {
            # body1 + note1 + footer1
            $count = Write-TuiBox -Body @('b') -Note @('n') -Footer @('f') -PassThru 6>$null
            $count | Should -Be 3
        }
        It 'uses tee connectors around the note under Border' {
            # top + body + tee + note + tee + footer + bottom
            $count = Write-TuiBox -Body @('b') -Note @('n') -Footer @('f') -Border -PassThru 6>$null
            $count | Should -Be 7
        }
        It 'closes the note band with its own lower rule when no footer follows' {
            # body1 + rule + note1 + rule
            $count = Write-TuiBox -Body @('b') -Note @('n') -SectionRules -PassThru 6>$null
            $count | Should -Be 4
        }
        It 'ignores an empty note' {
            $count = Write-TuiBox -Body @('b') -Note @() -Footer @('f') -SectionRules -PassThru 6>$null
            $count | Should -Be 3  # body + rule + footer, no note band
        }
        It 'renders a single blank-line note (reserved band) rather than dropping it' {
            # @('') is falsy under `if ($Note)`; the band must still render so a
            # reserved (blank) help band keeps its rules. body + rule + note + rule + footer
            $count = Write-TuiBox -Body @('b') -Note @('') -Footer @('f') -SectionRules -PassThru 6>$null
            $count | Should -Be 5
        }
    }
}
