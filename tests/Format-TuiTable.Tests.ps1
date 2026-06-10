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
        [pscustomobject]@{ Id = 1;   Name = 'init'; CPU = 0.5 }
        [pscustomobject]@{ Id = 200; Name = 'sshd'; CPU = 12.25 }
        [pscustomobject]@{ Id = 9;   Name = 'cron'; CPU = 3 }
    )
}

Describe 'Format-TuiTable' {
    Context 'Auto-derived columns' {
        It 'emits a header row plus one row per record' {
            $rows = Format-TuiTable -Rows $sample
            $rows.Count | Should -Be 4   # header + 3 data
        }
        It 'derives headers from object property names' {
            $rows = Format-TuiTable -Rows $sample
            $rows[0] | Should -Match 'Id'
            $rows[0] | Should -Match 'Name'
            $rows[0] | Should -Match 'CPU'
        }
        It 'auto-sizes a column to its widest cell' {
            # Id column must be wide enough for "200" (3 cells).
            $rows = Format-TuiTable -Rows $sample -Separator '|'
            $rows[1] | Should -Match '^1  \|'   # "1" padded to width 3
            $rows[2] | Should -Match '^200\|'
        }
    }

    Context 'Width agreement' {
        It 'returns every row at exactly the same display width' {
            $rows = Format-TuiTable -Rows $sample -HeaderRule
            $widths = $rows | ForEach-Object { Measure-Cells $_ }
            ($widths | Sort-Object -Unique).Count | Should -Be 1
        }
        It 'keeps width agreement with CJK cell content' {
            $cjk = @(
                [pscustomobject]@{ Name = 'a';    Label = 'x' }
                [pscustomobject]@{ Name = '東京'; Label = 'yy' }
            )
            $rows = Format-TuiTable -Rows $cjk -HeaderRule
            $widths = $rows | ForEach-Object { Measure-Cells $_ }
            ($widths | Sort-Object -Unique).Count | Should -Be 1
        }
    }

    Context 'Header rule' {
        It 'inserts a rule of full table width after the header' {
            $rows = Format-TuiTable -Rows $sample -HeaderRule
            $rows[1] | Should -Match '^─+$'
            (Measure-Cells $rows[1]) | Should -Be (Measure-Cells $rows[0])
        }
        It 'omits the rule with -NoHeader' {
            $rows = Format-TuiTable -Rows $sample -NoHeader -HeaderRule
            $rows.Count | Should -Be 3   # data only, no header, no rule
            $rows[0] | Should -Not -Match '^─+$'
        }
    }

    Context 'Explicit column spec' {
        It 'selects and orders the named columns only' {
            $rows = Format-TuiTable -Rows $sample -Columns @('Name', 'Id') -Separator '|'
            $rows[0] | Should -Match '^Name\|'
            $rows[0] | Should -Match '\|Id'
            $rows[0] | Should -Not -Match 'CPU'
        }
        It 'applies a per-column justify to cells and header' {
            $rows = Format-TuiTable -Rows $sample -Columns @(
                @{ Name = 'Id'; Justify = 'Right' }) -NoHeader
            $rows[0] | Should -BeExactly '  1'
            $rows[1] | Should -BeExactly '200'
        }
        It 'renames a column via Header' {
            $rows = Format-TuiTable -Rows $sample -Columns @(
                @{ Name = 'CPU'; Header = 'Load' })
            $rows[0] | Should -Match 'Load'
        }
        It 'pins a column to a fixed Width and truncates overflow' {
            $wide = @([pscustomobject]@{ Name = 'a-very-long-name' })
            $rows = @(Format-TuiTable -Rows $wide -Columns @(
                @{ Name = 'Name'; Width = 6 }) -NoHeader)
            (Measure-Cells $rows[0]) | Should -Be 6
            $rows[0] | Should -Match "$([char]0x2026)"   # ellipsis
        }
    }

    Context 'Separator' {
        It 'defaults to a vertical bar fenced by spaces' {
            $rows = Format-TuiTable -Rows $sample
            $rows[0] | Should -Match ' │ '
        }
        It 'honours a custom separator' {
            $rows = Format-TuiTable -Rows $sample -Separator ' :: '
            $rows[0] | Should -Match ' :: '
        }
        It 'uses ASCII glyphs under -Ascii' {
            $rows = Format-TuiTable -Rows $sample -Ascii -HeaderRule
            $rows[0] | Should -Match ' \| '
            $rows[1] | Should -Match '^-+$'
        }
    }

    Context 'Input shapes and edges' {
        It 'accepts pipeline input' {
            $rows = $sample | Format-TuiTable
            $rows.Count | Should -Be 4
        }
        It 'reads cells from dictionary rows' {
            $rows = @{ a = 1; b = 'x' }, @{ a = 22; b = 'yy' } |
                Format-TuiTable -Columns @('a', 'b') -Separator '|'
            $rows[1] | Should -Match 'x'
            $rows[2] | Should -Match 'yy'
        }
        It 'renders null cells as empty' {
            $r = @([pscustomobject]@{ A = 'x'; B = $null })
            $rows = @(Format-TuiTable -Rows $r -Columns @('A', 'B') -NoHeader -Separator '|')
            $rows[0] | Should -BeExactly 'x|'
        }
        It 'returns an empty array for no input' {
            $rows = Format-TuiTable -Rows @()
            @($rows).Count | Should -Be 0
        }
        It 'skips null rows' {
            $rows = Format-TuiTable -Rows @($sample[0], $null, $sample[1])
            $rows.Count | Should -Be 3   # header + 2 non-null
        }
    }
}
