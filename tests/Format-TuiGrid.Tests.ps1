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

    $sample = @(
        [pscustomobject]@{ Service = 'nginx';    Status = 'Running'; CPU = 0.4 }
        [pscustomobject]@{ Service = 'postgres'; Status = 'Running'; CPU = 12.7 }
        [pscustomobject]@{ Service = 'redis';    Status = 'Stopped'; CPU = 0 }
    )
}

Describe 'Format-TuiGrid' {
    Context 'Frame structure' {
        It 'brackets the content with a top and bottom border' {
            $f = Format-TuiGrid -Rows $sample
            $f[0]   | Should -Match '^┌─+(┬─+)*┐$'
            $f[-1]  | Should -Match '^└─+(┴─+)*┘$'
        }
        It 'rules under the header and between every data row' {
            $f = Format-TuiGrid -Rows $sample
            # top, header, rule, r0, rule, r1, rule, r2, bottom = 9 lines
            $f.Count | Should -Be 9
            ($f | Where-Object { $_ -match '┼' }).Count | Should -Be 3   # header + 2 inter-row
        }
        It 'omits the header and its rule under -NoHeader' {
            $f = Format-TuiGrid -Rows $sample -NoHeader
            # top, r0, rule, r1, rule, r2, bottom = 7 lines
            $f.Count | Should -Be 7
        }
        It 'wraps cells in vertical rules with single-space padding' {
            $f = Format-TuiGrid -Rows $sample
            $f[1] | Should -Match '^│ '
            $f[1] | Should -Match ' │$'
        }
    }

    Context 'Width agreement' {
        It 'returns every line at exactly the same display width' {
            $f = Format-TuiGrid -Rows $sample
            ($f | ForEach-Object { Measure-Cells $_ } | Sort-Object -Unique).Count | Should -Be 1
        }
        It 'holds with a footer and double lines' {
            $foot = [pscustomobject]@{ Service = 'TOTAL'; CPU = 13.1 }
            $f = Format-TuiGrid -Rows $sample -Footer $foot -GridStyle Double
            ($f | ForEach-Object { Measure-Cells $_ } | Sort-Object -Unique).Count | Should -Be 1
        }
        It 'holds with CJK cell content' {
            $cjk = @(
                [pscustomobject]@{ Name = 'a';    Note = 'x' }
                [pscustomobject]@{ Name = '東京'; Note = 'yy' }
            )
            $f = Format-TuiGrid -Rows $cjk
            ($f | ForEach-Object { Measure-Cells $_ } | Sort-Object -Unique).Count | Should -Be 1
        }
    }

    Context 'Justification' {
        It 'auto-right-justifies a numeric column' {
            $f = Format-TuiGrid -Rows $sample
            # CPU column (last) holds only numbers; '0.4' should be right-padded.
            $f[3] | Should -Match '0\.4 │$'
        }
        It 'leaves a non-numeric column left-justified' {
            $f = Format-TuiGrid -Rows $sample
            $f[3] | Should -Match '^│ nginx'
        }
        It 'accepts short-form justify letters l/r/c' {
            $f = Format-TuiGrid -Rows $sample -Columns @(
                @{ Name = 'Service'; Justify = 'r' }) -NoHeader
            $f[1] | Should -Match '^│ +nginx │$'
        }
    }

    Context 'Columns, widths, footer' {
        It 'selects and orders the named columns' {
            $f = Format-TuiGrid -Rows $sample -Columns @('Status', 'Service')
            $f[1] | Should -Match '^│ Status'
            $f[1] | Should -Not -Match 'CPU'
        }
        It 'pins a fixed Width and truncates overflow with an ellipsis' {
            $f = Format-TuiGrid -Rows $sample -Columns @(
                @{ Name = 'Service'; Width = 5 }) -NoHeader
            # 'postgres' (8 cells) overflows the 5-wide column and is ellipsized.
            ($f -join "`n") | Should -Match "$([char]0x2026)"
        }
        It 'draws a footer below its own rule and tolerates missing columns' {
            $foot = [pscustomobject]@{ Service = 'TOTAL' }
            $f = Format-TuiGrid -Rows $sample -Footer $foot
            $f[-2] | Should -Match '^│ TOTAL'   # footer is the line above the bottom border
        }
    }

    Context 'Grid style and ASCII' {
        It 'uses double-line glyphs under -GridStyle Double' {
            $f = Format-TuiGrid -Rows $sample -GridStyle Double
            $f[0]  | Should -Match '^╔'
            ($f | Where-Object { $_ -match '╬' }).Count | Should -BeGreaterThan 0
        }
        It 'collapses to ASCII glyphs under -Ascii' {
            $f = Format-TuiGrid -Rows $sample -Ascii
            $f[0]  | Should -Match '^\+-+(\+-+)*\+$'
            $f[1]  | Should -Match '^\| '
        }
        It 'collapses Double to the same ASCII set' {
            $f = Format-TuiGrid -Rows $sample -GridStyle Double -Ascii
            $f[0] | Should -Match '^\+'
            $f[0] | Should -Not -Match '╔'
        }
    }

    Context 'Fit to width' {
        It 'shrinks the widest column so the grid fits -MaxWidth' {
            $wide = @([pscustomobject]@{ A = 'x'; B = ('y' * 200) })
            $f = Format-TuiGrid -Rows $wide -MaxWidth 30 -NoHeader
            (Measure-Cells $f[0]) | Should -BeLessOrEqual 30
        }
    }

    Context 'Input shapes and edges' {
        It 'accepts pipeline input' {
            $f = $sample | Format-TuiGrid
            $f.Count | Should -Be 9
        }
        It 'reads cells from dictionary rows' {
            $f = @{ a = 1; b = 'x' }, @{ a = 22; b = 'yy' } | Format-TuiGrid -Columns @('a', 'b')
            ($f | Where-Object { $_ -match 'yy' }).Count | Should -Be 1
        }
        It 'returns an empty array for no input' {
            @(Format-TuiGrid -Rows @()).Count | Should -Be 0
        }
        It 'skips null rows' {
            $f = Format-TuiGrid -Rows @($sample[0], $null, $sample[1])
            # top, header, rule, r0, rule, r1, bottom = 7 lines (2 data rows)
            $f.Count | Should -Be 7
        }
    }
}

Describe 'Write-TuiGrid' {
    It 'returns the rendered line count under -PassThru' {
        $n = $sample | Write-TuiGrid -PassThru 6>$null
        $n | Should -Be 9
    }
    It 'returns nothing without -PassThru' {
        $out = $sample | Write-TuiGrid 6>$null
        $out | Should -BeNullOrEmpty
    }
    It 'renders nothing for empty input' {
        $n = Write-TuiGrid -Rows @() -PassThru 6>$null
        $n | Should -BeNullOrEmpty
    }
}
