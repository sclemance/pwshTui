BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'pwshTui.psd1'
    Import-Module $modulePath -Force

    # Display width of a string as the module measures it (CJK = 2 cells, ANSI
    # = 0). Re-derived here rather than calling the non-exported Get-DisplayWidth.
    function Measure-Cells([string]$s) {
        $clean = $s -replace "$([char]27)\[[0-9;]*[A-Za-z]", ''
        $w = 0
        foreach ($ch in $clean.ToCharArray()) {
            $cp = [int][char]$ch
            $wide = ($cp -ge 0x1100 -and $cp -le 0x115F) -or
                    ($cp -ge 0x2E80 -and $cp -le 0x303E) -or
                    ($cp -ge 0x3041 -and $cp -le 0x33FF) -or
                    ($cp -ge 0x3400 -and $cp -le 0x4DBF) -or
                    ($cp -ge 0x4E00 -and $cp -le 0x9FFF) -or
                    ($cp -ge 0xAC00 -and $cp -le 0xD7A3) -or
                    ($cp -ge 0xFF00 -and $cp -le 0xFF60)
            $w += ($wide ? 2 : 1)
        }
        return $w
    }
    $esc = [char]27
}

Describe 'Format-TuiColumn' {
    Context 'Padding to exact width' {
        It 'left-justifies by default' {
            Format-TuiColumn -Text 'Theme' -Width 12 | Should -BeExactly 'Theme       '
        }
        It 'right-justifies' {
            Format-TuiColumn -Text '42' -Width 6 -Justify Right | Should -BeExactly '    42'
        }
        It 'centers with the extra cell on the right' {
            Format-TuiColumn -Text 'hi' -Width 7 -Justify Center | Should -BeExactly '  hi   '
        }
        It 'pads with a custom char' {
            Format-TuiColumn -Text 'x' -Width 4 -PadChar '.' | Should -BeExactly 'x...'
        }
        It 'returns text unchanged when it already fills the width' {
            Format-TuiColumn -Text 'abcd' -Width 4 | Should -BeExactly 'abcd'
        }
    }

    Context 'Edge widths' {
        It 'returns empty for width 0' {
            Format-TuiColumn -Text 'anything' -Width 0 | Should -BeExactly ''
        }
        It 'returns empty for negative width' {
            Format-TuiColumn -Text 'anything' -Width -3 | Should -BeExactly ''
        }
        It 'accepts empty text' {
            Format-TuiColumn -Text '' -Width 3 | Should -BeExactly '   '
        }
    }

    Context 'Truncation' {
        It 'truncates over-width text with an ellipsis to exact width' {
            $r = Format-TuiColumn -Text 'VeryLongValue' -Width 6
            Measure-Cells $r | Should -Be 6
            $r | Should -Match "$([char]0x2026)"
        }
        It 'keeps inline ANSI but still measures to width' {
            $styled = "${esc}[31mRedAndLong${esc}[0m"
            $r = Format-TuiColumn -Text $styled -Width 5
            Measure-Cells $r | Should -Be 5
        }
    }

    Context 'Display-width awareness (CJK = 2 cells)' {
        It 'pads a CJK string to the right cell count' {
            $cjk = [string][char]0x65E5 + [char]0x672C   # 2 chars, 4 cells
            $r = Format-TuiColumn -Text $cjk -Width 10
            Measure-Cells $r | Should -Be 10
        }
        It 'truncates CJK on a cell boundary to width' {
            $cjk = -join (0..9 | ForEach-Object { [char]0x65E5 })   # 10 wide chars
            $r = Format-TuiColumn -Text $cjk -Width 7
            Measure-Cells $r | Should -Be 7
        }
    }
}
