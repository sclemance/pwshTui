BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'pwshTui.psd1'
    Import-Module $modulePath -Force
}

Describe 'Format-TuiWrap' {
    Context 'Basic wrapping' {
        It 'wraps text into lines no wider than the width' {
            $lines = @(Format-TuiWrap -Text 'The quick brown fox jumps over the lazy dog' -Width 20)
            $lines.Count | Should -BeGreaterThan 1
            foreach ($l in $lines) { $l.Length | Should -BeLessOrEqual 20 }
        }
        It 'keeps short text on a single line' {
            $lines = @(Format-TuiWrap -Text 'short' -Width 20)
            $lines.Count | Should -Be 1
            $lines[0] | Should -BeExactly 'short'
        }
        It 'returns an empty array for empty input' {
            (@(Format-TuiWrap -Text '' -Width 20)).Count | Should -Be 0
        }
        It 'returns an empty array for non-positive width' {
            (@(Format-TuiWrap -Text 'hello world' -Width 0)).Count | Should -Be 0
        }
    }

    Context 'Hanging indent' {
        It 'indents only continuation lines' {
            $lines = @(Format-TuiWrap -Text 'The quick brown fox jumps over the lazy dog' -Width 20 -HangingIndent 4)
            $lines[0] | Should -Not -Match '^\s'
            $lines[1] | Should -Match '^    '
        }
    }

    Context 'Long words' {
        It 'hard-splits a word longer than the width' {
            $lines = @(Format-TuiWrap -Text 'supercalifragilisticexpialidocious' -Width 10)
            $lines.Count | Should -BeGreaterThan 1
            foreach ($l in $lines) { $l.Length | Should -BeLessOrEqual 10 }
        }
    }

    Context 'MaxLines clamping' {
        It 'caps the returned line count' {
            $lines = @(Format-TuiWrap -Text 'one two three four five six seven eight nine ten eleven' -Width 8 -MaxLines 3)
            $lines.Count | Should -Be 3
        }
        It 'ellipsizes the last kept line when content is dropped' {
            $lines = @(Format-TuiWrap -Text 'one two three four five six seven eight nine ten eleven' -Width 8 -MaxLines 2)
            $lines[-1] | Should -Match "$([char]0x2026)$"
        }
    }
}
