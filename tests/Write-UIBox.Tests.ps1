BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'pwshTui.psd1'
    Import-Module $modulePath -Force
}

Describe 'Write-UIBox' {

    # Write-UIBox writes to the host via Write-Host (information stream 6).
    # Suppressing stream 6 keeps test output clean; we assert on the return value
    # (frame line count) which is sufficient to verify layout decisions.

    Context 'Frame count without border' {
        It 'returns body-line count for body only' {
            $count = Write-UIBox -Body @('one') 6>$null
            $count | Should -Be 1
        }
        It 'returns header + body + footer with no separators' {
            $count = Write-UIBox -Header @('h') -Body @('b') -Footer @('f') 6>$null
            $count | Should -Be 3
        }
        It 'handles multi-line sections' {
            $count = Write-UIBox -Header @('h1','h2') -Body @('b1','b2','b3') -Footer @('f1') 6>$null
            $count | Should -Be 6
        }
    }

    Context 'Frame count with border' {
        It 'returns top + body + bottom = body+2' {
            $count = Write-UIBox -Body @('one') -Border 6>$null
            $count | Should -Be 3
        }
        It 'adds a separator between header and body' {
            $count = Write-UIBox -Header @('h') -Body @('b') -Border 6>$null
            # top + header + rule + body + bottom
            $count | Should -Be 5
        }
        It 'adds a separator between body and footer' {
            $count = Write-UIBox -Body @('b') -Footer @('f') -Border 6>$null
            # top + body + rule + footer + bottom
            $count | Should -Be 5
        }
        It 'returns the full 7-row layout for header + body + footer' {
            $count = Write-UIBox -Header @('h') -Body @('b') -Footer @('f') -Border 6>$null
            # top + header + rule + body + rule + footer + bottom
            $count | Should -Be 7
        }
        It 'scales with multi-line sections' {
            $count = Write-UIBox -Header @('h1','h2') -Body @('b1','b2','b3') -Footer @('f1','f2') -Border 6>$null
            # top + 2 header + rule + 3 body + rule + 2 footer + bottom
            $count | Should -Be 11
        }
    }

    Context 'Truncation does not change frame count' {
        It 'still returns body-line count when a body line is truncated' {
            $longLine = 'x' * 200
            $count = Write-UIBox -Body @($longLine) -Border -MaxWidth 20 6>$null
            $count | Should -Be 3  # top + 1 truncated body + bottom
        }
        It 'preserves frame count for an ANSI-styled long line' {
            $ansiLong = "`e[36m> `e[46;30m" + ('y' * 200) + "`e[0m"
            $count = Write-UIBox -Body @($ansiLong) -Border -MaxWidth 20 6>$null
            $count | Should -Be 3
        }
    }
}
