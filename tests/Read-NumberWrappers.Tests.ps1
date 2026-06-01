BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'pwshTui.psd1'
    Import-Module $modulePath -Force
}

# Read-Percentage / Read-Temperature / Read-Currency are thin wrappers over
# Read-Number. The interactive loop is exercised by Read-Number's own demo
# path. These tests pin down the wiring: that the right Suffix / Prefix /
# Precision / Min / Max / Default get forwarded to Read-Number based on the
# wrapper's per-unit / per-currency defaults.

Describe 'Get-CurrencyFormat' {
    Context 'Common currencies' {
        It 'returns 2 decimal places for USD' {
            $fmt = InModuleScope pwshTui { Get-CurrencyFormat -CurrencyCode 'USD' }
            $fmt.Digits | Should -Be 2
        }

        It 'returns 0 decimal places for JPY' {
            $fmt = InModuleScope pwshTui { Get-CurrencyFormat -CurrencyCode 'JPY' }
            $fmt.Digits | Should -Be 0
        }

        It 'returns 3 decimal places for BHD' {
            $fmt = InModuleScope pwshTui { Get-CurrencyFormat -CurrencyCode 'BHD' }
            $fmt.Digits | Should -Be 3
        }

        It 'returns a non-empty prefix or suffix for USD' {
            $fmt = InModuleScope pwshTui { Get-CurrencyFormat -CurrencyCode 'USD' }
            ($fmt.Prefix.Length + $fmt.Suffix.Length) | Should -BeGreaterThan 0
        }

        It 'normalizes lowercase codes' {
            $upper = InModuleScope pwshTui { Get-CurrencyFormat -CurrencyCode 'USD' }
            $lower = InModuleScope pwshTui { Get-CurrencyFormat -CurrencyCode 'usd' }
            $lower.Digits | Should -Be $upper.Digits
            $lower.Prefix | Should -Be $upper.Prefix
            $lower.Suffix | Should -Be $upper.Suffix
        }
    }

    Context 'Unknown currency code' {
        It 'falls back to literal-prefix and 2 decimal places' {
            $fmt = InModuleScope pwshTui { Get-CurrencyFormat -CurrencyCode 'XYZ' }
            $fmt.Digits | Should -Be 2
            $fmt.Prefix | Should -Be 'XYZ '
            $fmt.Suffix | Should -Be ''
        }
    }
}

Describe '_FahrenheitRegions list' {
    It 'includes the United States' {
        InModuleScope pwshTui { $script:_FahrenheitRegions } | Should -Contain 'US'
    }

    It 'includes Liberia' {
        InModuleScope pwshTui { $script:_FahrenheitRegions } | Should -Contain 'LR'
    }

    It 'does not include Canada' {
        InModuleScope pwshTui { $script:_FahrenheitRegions } | Should -Not -Contain 'CA'
    }

    It 'does not include the United Kingdom' {
        InModuleScope pwshTui { $script:_FahrenheitRegions } | Should -Not -Contain 'GB'
    }
}

Describe 'Get-DefaultTemperatureUnit' {
    It 'returns one of the three valid units' {
        $u = InModuleScope pwshTui { Get-DefaultTemperatureUnit }
        $u | Should -BeIn @('Celsius', 'Fahrenheit', 'Kelvin')
    }

    It 'never returns Kelvin (Kelvin is opt-in only)' {
        $u = InModuleScope pwshTui { Get-DefaultTemperatureUnit }
        $u | Should -Not -Be 'Kelvin'
    }
}

Describe 'Read-Percentage' {
    It 'forwards Min=0 Max=100 with %% suffix to Read-Number' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]75 }
            $r = Read-Percentage
            $r | Should -Be 75
            Should -Invoke Read-Number -Times 1 -ParameterFilter {
                $Min -eq 0 -and $Max -eq 100 -and $Suffix -eq ' %'
            }
        }
    }

    It 'returns the value unchanged by default' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]42 }
            (Read-Percentage) | Should -Be 42
        }
    }

    It 'returns value/100 when -AsFraction is set' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]75 }
            (Read-Percentage -AsFraction) | Should -Be ([decimal]0.75)
        }
    }

    It 'returns 0 fractional precisely (no IEEE drift)' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]0 }
            (Read-Percentage -AsFraction) | Should -Be ([decimal]0)
        }
    }

    It 'returns $null on Read-Number cancel' {
        InModuleScope pwshTui {
            Mock Read-Number { return $null }
            (Read-Percentage) | Should -BeNullOrEmpty
        }
    }

    It 'forwards -Precision to Read-Number' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]12.5 }
            Read-Percentage -Precision 1 | Out-Null
            Should -Invoke Read-Number -Times 1 -ParameterFilter { $Precision -eq 1 }
        }
    }
}

Describe 'Format-PercentageBar' {
    Context 'Cell math' {
        It 'fills exactly Width cells at 100%' {
            $s = InModuleScope pwshTui { Format-PercentageBar -Value 100 -Width 10 -Ascii -NoColor }
            $s | Should -Be '[##########] '
        }

        It 'fills zero cells at 0%' {
            $s = InModuleScope pwshTui { Format-PercentageBar -Value 0 -Width 10 -Ascii -NoColor }
            $s | Should -Be '[----------] '
        }

        It 'fills half the cells at 50%' {
            $s = InModuleScope pwshTui { Format-PercentageBar -Value 50 -Width 10 -Ascii -NoColor }
            $s | Should -Be '[#####-----] '
        }

        It 'rounds to nearest cell (75% of 10 → 8 not 7)' {
            $s = InModuleScope pwshTui { Format-PercentageBar -Value 75 -Width 10 -Ascii -NoColor }
            ($s.Substring(1, 10) -replace '-', '').Length | Should -Be 8
        }

        It 'clamps negative values to empty' {
            $s = InModuleScope pwshTui { Format-PercentageBar -Value -25 -Width 10 -Ascii -NoColor }
            $s | Should -Be '[----------] '
        }

        It 'clamps values above 100 to full' {
            $s = InModuleScope pwshTui { Format-PercentageBar -Value 150 -Width 10 -Ascii -NoColor }
            $s | Should -Be '[##########] '
        }
    }

    Context 'Glyph and color variants' {
        It 'uses Unicode glyphs by default' {
            $s = InModuleScope pwshTui { Format-PercentageBar -Value 50 -Width 4 -NoColor }
            $s | Should -Match '█'   # full block somewhere in the bar
            $s | Should -Match '░'   # light shade somewhere in the bar
        }

        It 'embeds ANSI color codes when -NoColor is not set' {
            $s = InModuleScope pwshTui { Format-PercentageBar -Value 50 -Width 4 }
            $s | Should -Match "`e\["       # at least one ANSI CSI escape
        }

        It 'embeds no ANSI escapes when -NoColor is set' {
            $s = InModuleScope pwshTui { Format-PercentageBar -Value 50 -Width 4 -NoColor }
            $s | Should -Not -Match "`e\["
        }

        It 'uses ASCII glyphs only when -Ascii is set' {
            $s = InModuleScope pwshTui { Format-PercentageBar -Value 50 -Width 4 -Ascii -NoColor }
            $s | Should -Not -Match '█'
            $s | Should -Not -Match '░'
            $s | Should -Match '#'
            $s | Should -Match '-'
        }
    }
}

Describe 'Read-Percentage -Bar' {
    It 'does not pass a Decorator when -Bar is absent' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]50 }
            Read-Percentage -Default 50 | Out-Null
            Should -Invoke Read-Number -Times 1 -ParameterFilter {
                $null -eq $Decorator
            }
        }
    }

    It 'passes a scriptblock Decorator to Read-Number when -Bar is set' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]50 }
            Read-Percentage -Default 50 -Bar | Out-Null
            Should -Invoke Read-Number -Times 1 -ParameterFilter {
                $Decorator -is [scriptblock]
            }
        }
    }

    It 'the forwarded Decorator produces a bar string when invoked' {
        # Pester's Mock can capture the parameters that were passed; pull the
        # Decorator scriptblock out and exercise it directly to confirm it's
        # actually wired to Format-PercentageBar correctly.
        InModuleScope pwshTui {
            $script:_capturedDecorator = $null
            Mock Read-Number {
                $script:_capturedDecorator = $Decorator
                return [decimal]50
            }
            Read-Percentage -Default 50 -Bar -BarWidth 10 -Ascii -NoColor | Out-Null
            $script:_capturedDecorator | Should -Not -BeNullOrEmpty
            $rendered = & $script:_capturedDecorator ([decimal]50)
            $rendered | Should -Be '[#####-----] '
        }
    }

    It 'honors -BarWidth' {
        InModuleScope pwshTui {
            $script:_capturedDecorator = $null
            Mock Read-Number {
                $script:_capturedDecorator = $Decorator
                return [decimal]100
            }
            Read-Percentage -Bar -BarWidth 30 -Ascii -NoColor | Out-Null
            $rendered = & $script:_capturedDecorator ([decimal]100)
            # 30 fill chars between the brackets
            $rendered | Should -Be ('[' + ('#' * 30) + '] ')
        }
    }
}

Describe 'Read-Temperature' {
    Context 'Per-unit defaults' {
        It 'forwards Celsius defaults and " °C" suffix' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]20 }
                Read-Temperature -Unit Celsius | Out-Null
                Should -Invoke Read-Number -Times 1 -ParameterFilter {
                    $Suffix -eq ' °C' -and $Min -eq -100 -and $Max -eq 150 -and $Default -eq 20
                }
            }
        }

        It 'forwards Fahrenheit defaults and " °F" suffix' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]68 }
                Read-Temperature -Unit Fahrenheit | Out-Null
                Should -Invoke Read-Number -Times 1 -ParameterFilter {
                    $Suffix -eq ' °F' -and $Min -eq -148 -and $Max -eq 302 -and $Default -eq 68
                }
            }
        }

        It 'forwards Kelvin defaults and " K" suffix (no degree sign)' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]293 }
                Read-Temperature -Unit Kelvin | Out-Null
                Should -Invoke Read-Number -Times 1 -ParameterFilter {
                    $Suffix -eq ' K' -and $Min -eq 173 -and $Max -eq 423 -and $Default -eq 293
                }
            }
        }
    }

    Context 'Caller overrides' {
        It 'honors explicit -Min / -Max / -Default over per-unit defaults' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]37 }
                Read-Temperature -Unit Celsius -Min 35 -Max 42 -Default 37 | Out-Null
                Should -Invoke Read-Number -Times 1 -ParameterFilter {
                    $Min -eq 35 -and $Max -eq 42 -and $Default -eq 37
                }
            }
        }

        It 'partial override is allowed (only -Max specified)' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]20 }
                Read-Temperature -Unit Celsius -Max 60 | Out-Null
                Should -Invoke Read-Number -Times 1 -ParameterFilter {
                    $Min -eq -100 -and $Max -eq 60 -and $Default -eq 20
                }
            }
        }
    }

    Context 'Default unit selection' {
        It 'uses the region-derived default when -Unit is omitted' {
            InModuleScope pwshTui {
                Mock Get-DefaultTemperatureUnit { 'Fahrenheit' }
                Mock Read-Number { return [decimal]68 }
                Read-Temperature | Out-Null
                Should -Invoke Read-Number -Times 1 -ParameterFilter { $Suffix -eq ' °F' }
            }
        }
    }
}

Describe 'Read-Currency' {
    Context 'Known currencies (precision)' {
        It 'forwards 2 decimal places for USD' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]9.99 }
                Read-Currency -Currency USD | Out-Null
                Should -Invoke Read-Number -Times 1 -ParameterFilter { $Precision -eq 2 }
            }
        }

        It 'forwards 0 decimal places for JPY' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]1000 }
                Read-Currency -Currency JPY | Out-Null
                Should -Invoke Read-Number -Times 1 -ParameterFilter { $Precision -eq 0 }
            }
        }

        It 'forwards 3 decimal places for BHD' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]1.234 }
                Read-Currency -Currency BHD | Out-Null
                Should -Invoke Read-Number -Times 1 -ParameterFilter { $Precision -eq 3 }
            }
        }
    }

    Context 'Symbol placement' {
        It 'sets a non-empty Prefix OR Suffix (never both empty) for USD' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]0 }
                Read-Currency -Currency USD | Out-Null
                Should -Invoke Read-Number -Times 1 -ParameterFilter {
                    ($Prefix.Length + $Suffix.Length) -gt 0
                }
            }
        }
    }

    Context 'Always uses thousands separator' {
        It 'always passes -ThousandsSeparator (so 1,234,567 reads naturally)' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]0 }
                Read-Currency -Currency USD | Out-Null
                Should -Invoke Read-Number -Times 1 -ParameterFilter {
                    $ThousandsSeparator.IsPresent
                }
            }
        }
    }

    Context 'Caller overrides' {
        It 'honors explicit -Precision over the currency default' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]100 }
                Read-Currency -Currency JPY -Precision 2 | Out-Null
                Should -Invoke Read-Number -Times 1 -ParameterFilter { $Precision -eq 2 }
            }
        }
    }

    Context 'Unknown currency' {
        It 'falls back to literal-prefix on unknown ISO codes' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]0 }
                Read-Currency -Currency 'XYZ' | Out-Null
                Should -Invoke Read-Number -Times 1 -ParameterFilter {
                    $Prefix -eq 'XYZ ' -and $Precision -eq 2
                }
            }
        }
    }
}
