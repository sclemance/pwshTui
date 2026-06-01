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

Describe 'Temperature family file (replaces the old $script:_FahrenheitRegions / Get-DefaultTemperatureUnit data)' {
    BeforeAll {
        $script:tempFam = InModuleScope pwshTui { Import-MeasurementFamily -Family Temperature }
    }

    It 'lists US in ImperialRegions' {
        $script:tempFam.ImperialRegions | Should -Contain 'US'
    }

    It 'lists Liberia in ImperialRegions' {
        $script:tempFam.ImperialRegions | Should -Contain 'LR'
    }

    It 'does not list Canada' {
        $script:tempFam.ImperialRegions | Should -Not -Contain 'CA'
    }

    It 'does not list the United Kingdom' {
        $script:tempFam.ImperialRegions | Should -Not -Contain 'GB'
    }

    It 'maps Metric default to celsius and Imperial default to fahrenheit' {
        # Kelvin stays opt-in: it is never picked by Get-MeasurementOutputUnit.
        $script:tempFam.DefaultOutputUnit.Metric   | Should -Be 'celsius'
        $script:tempFam.DefaultOutputUnit.Imperial | Should -Be 'fahrenheit'
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

Describe 'Format-ValueBar' {
    Context 'Cell math (0..100 range mirrors the old percentage cases)' {
        It 'fills exactly Width cells at the top of the range' {
            $s = InModuleScope pwshTui { Format-ValueBar -Value 100 -Min 0 -Max 100 -Width 10 -Ascii -NoColor }
            $s | Should -Be '[##########] '
        }

        It 'fills zero cells at the bottom of the range' {
            $s = InModuleScope pwshTui { Format-ValueBar -Value 0 -Min 0 -Max 100 -Width 10 -Ascii -NoColor }
            $s | Should -Be '[----------] '
        }

        It 'fills half the cells at the midpoint' {
            $s = InModuleScope pwshTui { Format-ValueBar -Value 50 -Min 0 -Max 100 -Width 10 -Ascii -NoColor }
            $s | Should -Be '[#####-----] '
        }

        It 'rounds to nearest cell (75% of 10 → 8 not 7)' {
            $s = InModuleScope pwshTui { Format-ValueBar -Value 75 -Min 0 -Max 100 -Width 10 -Ascii -NoColor }
            ($s.Substring(1, 10) -replace '-', '').Length | Should -Be 8
        }

        It 'clamps values below Min to empty' {
            $s = InModuleScope pwshTui { Format-ValueBar -Value -25 -Min 0 -Max 100 -Width 10 -Ascii -NoColor }
            $s | Should -Be '[----------] '
        }

        It 'clamps values above Max to full' {
            $s = InModuleScope pwshTui { Format-ValueBar -Value 150 -Min 0 -Max 100 -Width 10 -Ascii -NoColor }
            $s | Should -Be '[##########] '
        }
    }

    Context 'Non-percentage ranges' {
        It 'fills proportionally for a Min/Max that does not start at 0' {
            # Value 8 in [1..65535] → ratio ~0.0001 → 0 filled cells for width 10
            $s = InModuleScope pwshTui { Format-ValueBar -Value 8 -Min 1 -Max 65535 -Width 10 -Ascii -NoColor }
            $s | Should -Be '[----------] '
        }

        It 'fills proportionally at the midpoint of a non-zero-anchored range' {
            # Value 50 in [0..100], but also 5 in [-5..15] → both are halfway
            $s = InModuleScope pwshTui { Format-ValueBar -Value 5 -Min -5 -Max 15 -Width 10 -Ascii -NoColor }
            $s | Should -Be '[#####-----] '
        }

        It 'handles negative-only ranges' {
            # Value -10 in [-100..0] → ratio = 90/100 = 0.9 → 9 cells filled
            $s = InModuleScope pwshTui { Format-ValueBar -Value -10 -Min -100 -Max 0 -Width 10 -Ascii -NoColor }
            ($s.Substring(1, 10) -replace '-', '').Length | Should -Be 9
        }

        It 'returns a full bar when Min == Max (degenerate range)' {
            $s = InModuleScope pwshTui { Format-ValueBar -Value 7 -Min 7 -Max 7 -Width 6 -Ascii -NoColor }
            $s | Should -Be '[######] '
        }
    }

    Context 'Glyph and color variants' {
        It 'uses Unicode glyphs by default' {
            $s = InModuleScope pwshTui { Format-ValueBar -Value 50 -Min 0 -Max 100 -Width 4 -NoColor }
            $s | Should -Match '█'
            $s | Should -Match '░'
        }

        It 'embeds ANSI color codes when -NoColor is not set' {
            $s = InModuleScope pwshTui { Format-ValueBar -Value 50 -Min 0 -Max 100 -Width 4 }
            $s | Should -Match "`e\["
        }

        It 'embeds no ANSI escapes when -NoColor is set' {
            $s = InModuleScope pwshTui { Format-ValueBar -Value 50 -Min 0 -Max 100 -Width 4 -NoColor }
            $s | Should -Not -Match "`e\["
        }

        It 'uses ASCII glyphs only when -Ascii is set' {
            $s = InModuleScope pwshTui { Format-ValueBar -Value 50 -Min 0 -Max 100 -Width 4 -Ascii -NoColor }
            $s | Should -Not -Match '█'
            $s | Should -Not -Match '░'
            $s | Should -Match '#'
            $s | Should -Match '-'
        }
    }
}

Describe 'Read-Percentage -Bar (pass-through to Read-Number)' {
    It 'does not pass -Bar to Read-Number when the wrapper -Bar is absent' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]50 }
            Read-Percentage -Default 50 | Out-Null
            Should -Invoke Read-Number -Times 1 -ParameterFilter {
                -not $Bar.IsPresent
            }
        }
    }

    It 'forwards -Bar to Read-Number when set' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]50 }
            Read-Percentage -Default 50 -Bar | Out-Null
            Should -Invoke Read-Number -Times 1 -ParameterFilter {
                $Bar.IsPresent -and $Min -eq 0 -and $Max -eq 100
            }
        }
    }

    It 'forwards -BarWidth to Read-Number' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]100 }
            Read-Percentage -Bar -BarWidth 30 -Ascii -NoColor | Out-Null
            Should -Invoke Read-Number -Times 1 -ParameterFilter {
                $BarWidth -eq 30 -and $Ascii.IsPresent
            }
        }
    }
}

Describe 'Read-Temperature (migrated onto Read-Measurement)' {
    # Read-Temperature is now a shim over Read-Measurement -Family Temperature.
    # The chain is Read-Temperature → Read-Measurement → Read-Number; mocking
    # Read-Number at the bottom of the chain still pins down what hits the
    # screen. Bounds and defaults are converted from the legacy unit-specific
    # values into the family's base (Celsius), so the parameters passed to
    # Read-Number are *Celsius equivalents* of the original ranges.

    Context 'Per-unit defaults (final Read-Number call)' {
        It 'Celsius: Min=-100, Max=150, Default=20, Suffix=" °C"' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]20 }
                Read-Temperature -Unit Celsius | Out-Null
                Should -Invoke Read-Number -Times 1 -ParameterFilter {
                    $Suffix -eq ' °C' -and $Min -eq -100 -and $Max -eq 150 -and $Default -eq 20
                }
            }
        }

        It 'Fahrenheit: bounds converted to base celsius, Suffix=" °F"' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]20 }
                Read-Temperature -Unit Fahrenheit | Out-Null
                # (-148, 302, 68) °F → (-100, 150, 20) °C, modulo the
                # 0.55555556 rounding in the family file.
                Should -Invoke Read-Number -Times 1 -ParameterFilter {
                    $Suffix -eq ' °F' -and
                    [Math]::Abs([double]($Min - (-100))) -lt 1e-5 -and
                    [Math]::Abs([double]($Max - 150))    -lt 1e-5 -and
                    [Math]::Abs([double]($Default - 20)) -lt 1e-5
                }
            }
        }

        It 'Kelvin: bounds converted to base celsius (exact, no rounding), Suffix=" K"' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]19.85 }
                Read-Temperature -Unit Kelvin | Out-Null
                # 173 K → -100.15 °C; 423 K → 149.85 °C; 293 K → 19.85 °C.
                # The conversion is integer-exact because Scale=1, Offset=-273.15.
                Should -Invoke Read-Number -Times 1 -ParameterFilter {
                    $Suffix -eq ' K' -and
                    $Min -eq ([decimal]-100.15) -and
                    $Max -eq ([decimal]149.85)  -and
                    $Default -eq ([decimal]19.85)
                }
            }
        }
    }

    Context 'Return value (preserves legacy Read-Temperature unit contract)' {
        It 'returns the value in -Unit (Fahrenheit in → Fahrenheit out)' {
            InModuleScope pwshTui {
                # Mock Read-Number to return a base celsius value; the
                # measurement engine converts back to the requested unit.
                Mock Read-Number { return [decimal]20 }  # 20 °C = 68 °F
                $r = Read-Temperature -Unit Fahrenheit
                [Math]::Abs([double]($r - 68)) | Should -BeLessThan 1e-5
            }
        }

        It 'returns Kelvin when -Unit Kelvin (0 °C round-trips to 273.15 K)' {
            InModuleScope pwshTui {
                Mock Read-Number { return [decimal]0 }
                $r = Read-Temperature -Unit Kelvin
                $r | Should -Be ([decimal]273.15)
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

    Context 'Default unit selection (forwarding to Read-Measurement)' {
        It 'omits -OutputUnit when -Unit is not supplied, letting Read-Measurement pick by region' {
            InModuleScope pwshTui {
                Mock Read-Measurement { return [decimal]20 }
                Read-Temperature | Out-Null
                Should -Invoke Read-Measurement -Times 1 -ParameterFilter {
                    $Family -eq 'Temperature' -and
                    $DefaultsByUnit.IsPresent -and
                    [string]::IsNullOrEmpty($OutputUnit)
                }
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
