BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'pwshTui.psd1'
    Import-Module $modulePath -Force
}

Describe 'Measure-FuzzyMatch' {

    Context 'Empty / whitespace inputs' {
        It 'returns 0 when target is whitespace' {
            Measure-FuzzyMatch -SearchTerm 'abc' -TargetText '   ' | Should -Be 0
        }
        It 'returns 0 when search is whitespace' {
            Measure-FuzzyMatch -SearchTerm '   ' -TargetText 'abc' | Should -Be 0
        }
        It 'returns 0 when normalized search becomes empty (punctuation only)' {
            Measure-FuzzyMatch -SearchTerm '!!!' -TargetText 'hello' | Should -Be 0
        }
    }

    Context 'Fast paths (spaced form)' {
        It 'returns 1000 for an exact match' {
            Measure-FuzzyMatch -SearchTerm 'server' -TargetText 'server' | Should -Be 1000
        }
        It 'returns 900 for a prefix match' {
            Measure-FuzzyMatch -SearchTerm 'serv' -TargetText 'server01' | Should -Be 900
        }
        It 'returns 800 for a substring match' {
            Measure-FuzzyMatch -SearchTerm 'ver' -TargetText 'server01' | Should -Be 800
        }
        It 'is case-insensitive' {
            Measure-FuzzyMatch -SearchTerm 'SERVER' -TargetText 'server' | Should -Be 1000
        }
    }

    Context 'Fast paths (compact form)' {
        It 'matches identifier-style queries against kebab-case targets' {
            Measure-FuzzyMatch -SearchTerm 'myserver' -TargetText 'my-server-01' | Should -Be 900
        }
        It 'matches identifier-style queries against dot-separated targets' {
            Measure-FuzzyMatch -SearchTerm 'userprofile' -TargetText 'user.profile.name' | Should -Be 900
        }
        It 'matches against snake_case targets' {
            Measure-FuzzyMatch -SearchTerm 'username' -TargetText 'user_name_field' | Should -Be 900
        }
    }

    Context 'No match' {
        It 'returns 0 when no shared characters' {
            Measure-FuzzyMatch -SearchTerm 'abc' -TargetText 'xyz' | Should -Be 0
        }
    }

    Context 'Algorithm: Subsequence' {
        It 'scores abbreviations highly' {
            $score = Measure-FuzzyMatch -SearchTerm 'fzmgr' -TargetText 'fuzzy match manager' -Algorithm Subsequence
            $score | Should -BeGreaterThan 400
        }
        It 'returns 0 when characters are not in order' {
            # Transposition - "srever" has 'r' before 'e' but "server" has 'e' before 'r'
            Measure-FuzzyMatch -SearchTerm 'srever' -TargetText 'server' -Algorithm Subsequence | Should -Be 0
        }
        It 'awards word-boundary bonus on space-separated targets' {
            $atBoundary = Measure-FuzzyMatch -SearchTerm 'fmm' -TargetText 'fuzzy match manager' -Algorithm Subsequence
            $atBoundary | Should -BeGreaterThan 0
        }
    }

    Context 'Algorithm: JaroWinkler' {
        It 'scores transpositions highly' {
            Measure-FuzzyMatch -SearchTerm 'srever' -TargetText 'server' -Algorithm JaroWinkler |
                Should -BeGreaterThan 500
        }
        It 'awards prefix boost for shared leading characters' {
            $withPrefix = Measure-FuzzyMatch -SearchTerm 'configurtion' -TargetText 'configuration' -Algorithm JaroWinkler
            $withPrefix | Should -BeGreaterThan 600
        }
    }

    Context 'Algorithm: Legacy' {
        It 'returns 1000 for exact match' {
            Measure-FuzzyMatch -SearchTerm 'server' -TargetText 'server' -Algorithm Legacy | Should -Be 1000
        }
        It 'handles singular/plural variants' {
            $score = Measure-FuzzyMatch -SearchTerm 'servers' -TargetText 'server farm' -Algorithm Legacy
            $score | Should -BeGreaterThan 0
        }
    }

    Context 'Auto-mode intent biasing' {
        It 'preserves typo signal (high length ratio)' {
            # srever -> server: ratio ~1.0, JW should win cleanly
            Measure-FuzzyMatch -SearchTerm 'srever' -TargetText 'server' | Should -BeGreaterThan 500
        }
        It 'preserves long-string typo signal' {
            # configurtion -> configuration: ratio 0.92, JW should win over Sub
            Measure-FuzzyMatch -SearchTerm 'configurtion' -TargetText 'configuration' |
                Should -BeGreaterThan 600
        }
        It 'recognizes vowel-sparse abbreviation intent' {
            # cfg is purely consonants, sparse intent should not be hurt
            $score = Measure-FuzzyMatch -SearchTerm 'cfg' -TargetText 'configuration'
            $score | Should -BeGreaterThan 0
        }
    }

    Context 'Word-aware normalization' {
        It 'splits camelCase into word boundaries' {
            # request is a substring of "xml http request" after camelCase split
            Measure-FuzzyMatch -SearchTerm 'request' -TargetText 'XMLHttpRequest' | Should -Be 800
        }
        It 'splits PascalCase acronym + word transitions (ACRONYMWord)' {
            # URLBuilder -> "url builder", so "url" is a prefix
            Measure-FuzzyMatch -SearchTerm 'url' -TargetText 'URLBuilder' | Should -Be 900
        }
        It 'treats hyphens as word boundaries' {
            Measure-FuzzyMatch -SearchTerm 'ser' -TargetText 'my-server-01' | Should -Be 800
        }
        It 'treats dots as word boundaries' {
            Measure-FuzzyMatch -SearchTerm 'ser' -TargetText 'my.server.01' | Should -Be 800
        }
        It 'treats slashes as word boundaries' {
            Measure-FuzzyMatch -SearchTerm 'auth' -TargetText 'src/auth/server.ts' | Should -Be 800
        }
        It 'treats underscores as word boundaries' {
            Measure-FuzzyMatch -SearchTerm 'name' -TargetText 'user_name_field' | Should -Be 800
        }
    }

    Context 'Score ranges' {
        It 'never exceeds 1000' {
            $cases = @(
                @{ s = 'server'; t = 'server' }
                @{ s = 'srv'; t = 'server' }
                @{ s = 'pwsh'; t = 'PowerShell' }
            )
            foreach ($c in $cases) {
                Measure-FuzzyMatch -SearchTerm $c.s -TargetText $c.t | Should -BeLessOrEqual 1000
            }
        }
        It 'is never negative' {
            $cases = @(
                @{ s = 'xyz'; t = 'abc' }
                @{ s = 'a'; t = 'b' }
                @{ s = '!!!'; t = '???' }
            )
            foreach ($c in $cases) {
                Measure-FuzzyMatch -SearchTerm $c.s -TargetText $c.t | Should -BeGreaterOrEqual 0
            }
        }
    }
}
