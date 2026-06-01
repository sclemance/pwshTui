BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'pwshTui.psd1'
    Import-Module $modulePath -Force
}

# Read-Number itself is interactive (reads from the console) so the input loop
# is exercised via the demo. The pure helpers below — Format-NumberValue,
# ConvertTo-NumberValue, Get-AcceleratedStep — carry the formatting, parsing,
# and acceleration logic and ARE unit-testable. They're module-private; reach
# them through InModuleScope.

Describe 'Format-NumberValue' {
    Context 'Precision' {
        It 'renders an integer with no decimal places by default' {
            InModuleScope pwshTui {
                Format-NumberValue -Value 42 -Precision 0
            } | Should -Be '42'
        }

        It 'renders fixed decimal places when Precision > 0' {
            InModuleScope pwshTui {
                Format-NumberValue -Value 3.1 -Precision 2
            } | Should -Be '3.10'
        }

        It 'rounds the displayed value to the requested precision' {
            InModuleScope pwshTui {
                Format-NumberValue -Value 1.2345 -Precision 2
            } | Should -Be '1.23'
        }
    }

    Context 'ThousandsSeparator under explicit culture' {
        It 'inserts the en-US comma separator when requested' {
            $enUS = [System.Globalization.CultureInfo]::new('en-US')
            InModuleScope pwshTui -Parameters @{ Culture = $enUS } {
                param($Culture)
                Format-NumberValue -Value 1234567 -Precision 0 `
                    -ThousandsSeparator -Culture $Culture
            } | Should -Be '1,234,567'
        }

        It 'inserts the de-DE dot separator when requested' {
            $deDE = [System.Globalization.CultureInfo]::new('de-DE')
            InModuleScope pwshTui -Parameters @{ Culture = $deDE } {
                param($Culture)
                Format-NumberValue -Value 1234567 -Precision 0 `
                    -ThousandsSeparator -Culture $Culture
            } | Should -Be '1.234.567'
        }

        It 'combines thousands separator with precision' {
            $enUS = [System.Globalization.CultureInfo]::new('en-US')
            InModuleScope pwshTui -Parameters @{ Culture = $enUS } {
                param($Culture)
                Format-NumberValue -Value 12345.67 -Precision 2 `
                    -ThousandsSeparator -Culture $Culture
            } | Should -Be '12,345.67'
        }

        It 'omits the separator when -ThousandsSeparator is absent' {
            $enUS = [System.Globalization.CultureInfo]::new('en-US')
            InModuleScope pwshTui -Parameters @{ Culture = $enUS } {
                param($Culture)
                Format-NumberValue -Value 1234567 -Precision 0 -Culture $Culture
            } | Should -Be '1234567'
        }
    }
}

Describe 'ConvertTo-NumberValue' {
    BeforeAll {
        $script:enUS = [System.Globalization.CultureInfo]::new('en-US')
        $script:deDE = [System.Globalization.CultureInfo]::new('de-DE')
    }

    Context 'Empty / unparseable input' {
        It 'flags empty buffer as Ok=false Reason=empty' {
            $r = InModuleScope pwshTui -Parameters @{ Culture = $script:enUS } {
                param($Culture)
                ConvertTo-NumberValue -Buffer '' -Precision 0 -Culture $Culture
            }
            $r.Ok | Should -BeFalse
            $r.Reason | Should -Be 'empty'
        }

        It 'flags garbage as unparseable' {
            $r = InModuleScope pwshTui -Parameters @{ Culture = $script:enUS } {
                param($Culture)
                ConvertTo-NumberValue -Buffer 'abc' -Precision 0 -Culture $Culture
            }
            $r.Ok | Should -BeFalse
            $r.Reason | Should -Be 'unparseable'
        }
    }

    Context 'Range checking' {
        It 'rejects values below Min' {
            $r = InModuleScope pwshTui -Parameters @{ Culture = $script:enUS } {
                param($Culture)
                ConvertTo-NumberValue -Buffer '5' -Precision 0 -Min 10 -Max 100 -Culture $Culture
            }
            $r.Ok | Should -BeFalse
            $r.Reason | Should -Be 'range'
            $r.Value | Should -Be 5
        }

        It 'rejects values above Max' {
            $r = InModuleScope pwshTui -Parameters @{ Culture = $script:enUS } {
                param($Culture)
                ConvertTo-NumberValue -Buffer '200' -Precision 0 -Min 0 -Max 100 -Culture $Culture
            }
            $r.Ok | Should -BeFalse
            $r.Reason | Should -Be 'range'
        }

        It 'accepts values at the inclusive boundaries' {
            $low = InModuleScope pwshTui -Parameters @{ Culture = $script:enUS } {
                param($Culture)
                ConvertTo-NumberValue -Buffer '0' -Precision 0 -Min 0 -Max 100 -Culture $Culture
            }
            $high = InModuleScope pwshTui -Parameters @{ Culture = $script:enUS } {
                param($Culture)
                ConvertTo-NumberValue -Buffer '100' -Precision 0 -Min 0 -Max 100 -Culture $Culture
            }
            $low.Ok | Should -BeTrue
            $high.Ok | Should -BeTrue
        }
    }

    Context 'Precision' {
        It 'rejects a decimal point when Precision=0' {
            $r = InModuleScope pwshTui -Parameters @{ Culture = $script:enUS } {
                param($Culture)
                ConvertTo-NumberValue -Buffer '3.5' -Precision 0 -Culture $Culture
            }
            $r.Ok | Should -BeFalse
            $r.Reason | Should -Be 'precision'
        }

        It 'accepts up to Precision decimals' {
            $r = InModuleScope pwshTui -Parameters @{ Culture = $script:enUS } {
                param($Culture)
                ConvertTo-NumberValue -Buffer '3.14' -Precision 2 -Culture $Culture
            }
            $r.Ok | Should -BeTrue
            $r.Value | Should -Be 3.14
        }

        It 'rejects more decimals than Precision allows' {
            $r = InModuleScope pwshTui -Parameters @{ Culture = $script:enUS } {
                param($Culture)
                ConvertTo-NumberValue -Buffer '3.145' -Precision 2 -Culture $Culture
            }
            $r.Ok | Should -BeFalse
            $r.Reason | Should -Be 'precision'
        }
    }

    Context 'Thousands separator handling' {
        It 'strips en-US commas before parsing' {
            $r = InModuleScope pwshTui -Parameters @{ Culture = $script:enUS } {
                param($Culture)
                ConvertTo-NumberValue -Buffer '10,000,000' -Precision 0 `
                    -Min 0 -Max 1e9 -Culture $Culture
            }
            $r.Ok | Should -BeTrue
            $r.Value | Should -Be 10000000
        }

        It 'strips de-DE dots before parsing' {
            $r = InModuleScope pwshTui -Parameters @{ Culture = $script:deDE } {
                param($Culture)
                ConvertTo-NumberValue -Buffer '10.000.000' -Precision 0 `
                    -Min 0 -Max 1e9 -Culture $Culture
            }
            $r.Ok | Should -BeTrue
            $r.Value | Should -Be 10000000
        }

        It 'parses a de-DE comma as the decimal mark' {
            $r = InModuleScope pwshTui -Parameters @{ Culture = $script:deDE } {
                param($Culture)
                ConvertTo-NumberValue -Buffer '1,5' -Precision 2 -Culture $Culture
            }
            $r.Ok | Should -BeTrue
            $r.Value | Should -Be 1.5
        }
    }

    Context 'Negative numbers' {
        It 'parses a negative value when Min < 0' {
            $r = InModuleScope pwshTui -Parameters @{ Culture = $script:enUS } {
                param($Culture)
                ConvertTo-NumberValue -Buffer '-25' -Precision 0 -Min -100 -Max 100 -Culture $Culture
            }
            $r.Ok | Should -BeTrue
            $r.Value | Should -Be -25
        }
    }
}

Describe 'Get-AcceleratedStep' {
    Context 'Single tap (HoldMs = 0)' {
        It 'moves by exactly BaseStep regardless of range' {
            $r = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 50 -Direction 1 -Min 0 -Max 1000000 `
                    -BaseStep 1 -Precision 0 -HoldMs 0
            }
            $r | Should -Be 51
        }

        It 'moves down by BaseStep on Direction=-1' {
            $r = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 50 -Direction -1 -Min 0 -Max 100 `
                    -BaseStep 1 -Precision 0 -HoldMs 0
            }
            $r | Should -Be 49
        }

        It 'honors a non-1 BaseStep on a single tap' {
            $r = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 0 -Direction 1 -Min 0 -Max 1000 `
                    -BaseStep 5 -Precision 0 -HoldMs 0
            }
            $r | Should -Be 5
        }
    }

    Context 'Clamping' {
        It 'clamps to Max' {
            $r = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 99 -Direction 1 -Min 0 -Max 100 `
                    -BaseStep 50 -Precision 0 -HoldMs 0
            }
            $r | Should -Be 100
        }

        It 'clamps to Min' {
            $r = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 5 -Direction -1 -Min 0 -Max 100 `
                    -BaseStep 50 -Precision 0 -HoldMs 0
            }
            $r | Should -Be 0
        }

        It 'returns Current clamped when Min == Max' {
            $r = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 7 -Direction 1 -Min 7 -Max 7 `
                    -BaseStep 1 -Precision 0 -HoldMs 1000
            }
            $r | Should -Be 7
        }
    }

    Context 'Acceleration grows with HoldMs' {
        It 'produces a larger step at 1000ms than at 0ms (mid-range, big range)' {
            $tap = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 500000 -Direction 1 -Min 0 -Max 1000000 `
                    -BaseStep 1 -Precision 0 -HoldMs 0
            }
            $held = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 500000 -Direction 1 -Min 0 -Max 1000000 `
                    -BaseStep 1 -Precision 0 -HoldMs 1000
            }
            ($held - 500000) | Should -BeGreaterThan ($tap - 500000)
        }

        It 'caps the step at maxFactor (range / (baseStep * 30)) once fully held' {
            # range = 1000, BaseStep = 1 → maxFactor ≈ 33 → step capped near 33
            $held = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 500 -Direction 1 -Min 0 -Max 1000 `
                    -BaseStep 1 -Precision 0 -HoldMs 5000
            }
            ($held - 500) | Should -BeLessOrEqual 34
        }

        It 'stays granular at 1s of hold on a million-range field' {
            # 10^(1000/1000) = 10x. Avoids the "skips straight to tens of
            # thousands within a second" feel the previous 2^(t/250) curve
            # produced (factor was 16 at 1s and accelerating fast).
            $held = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 500000 -Direction 1 -Min 0 -Max 1000000 `
                    -BaseStep 1 -Precision 0 -HoldMs 1000
            }
            ($held - 500000) | Should -BeLessOrEqual 15
            ($held - 500000) | Should -BeGreaterOrEqual 5
        }

        It 'is still granular at 2s (around 100x) on a million-range field' {
            $held = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 500000 -Direction 1 -Min 0 -Max 1000000 `
                    -BaseStep 1 -Precision 0 -HoldMs 2000
            }
            ($held - 500000) | Should -BeLessOrEqual 150
            ($held - 500000) | Should -BeGreaterOrEqual 50
        }

        It 'reaches useful speed by 4s on a million-range field (around 10000x)' {
            $held = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 500000 -Direction 1 -Min 0 -Max 1000000 `
                    -BaseStep 1 -Precision 0 -HoldMs 4000
            }
            ($held - 500000) | Should -BeGreaterOrEqual 5000
        }
    }

    Context 'Proximity dampening' {
        It 'dampens the step when near the upper limit (held arrow)' {
            # Use range=1000 so the held-mode minStep floor (range*0.0001 = 0.1
            # → clamped to BaseStep=1) doesn't mask the dampener. At mid-range
            # the factor cap is ~50; near the limit dampener^2 drops it below
            # the floor.
            $mid = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 500 -Direction 1 -Min 0 -Max 1000 `
                    -BaseStep 1 -Precision 0 -HoldMs 1500
            }
            $nearTop = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 999 -Direction 1 -Min 0 -Max 1000 `
                    -BaseStep 1 -Precision 0 -HoldMs 1500
            }
            ($mid - 500) | Should -BeGreaterThan ($nearTop - 999)
        }

        It 'closes the last million on a billion-range field in a reasonable step (no 38-minute crawl)' {
            # Regression: the original squared-dampener + 5%-of-range zone
            # produced step ≈ 16 here, which meant ~38 minutes to traverse
            # the last 1M units at 30Hz. The speed-scaled zone + linear
            # falloff should make this step ≥ ~100k so the brake completes
            # in ~1 second total.
            $next = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 998909312 -Direction 1 -Min 0 -Max 1000000000 `
                    -BaseStep 1 -Precision 0 -HoldMs 10000
            }
            ($next - 998909312) | Should -BeGreaterOrEqual 100000
        }

        It 'closes ~33% of remaining distance per tick inside the dampened zone (geometric brake)' {
            # The speed-scaled dampen zone (3 * factor * baseStep) makes
            # the dampened-zone closing rate independent of range — each
            # tick reduces remaining distance by ~1/3, so braking from any
            # held speed takes ~20 ticks regardless of how big the range is.
            $first = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 998909312 -Direction 1 -Min 0 -Max 1000000000 `
                    -BaseStep 1 -Precision 0 -HoldMs 10000
            }
            $secondDistance = 1000000000 - $first
            $firstDistance = 1000000000 - 998909312
            # Should have closed roughly a third (allow 20%..50%)
            $closedRatio = 1.0 - ($secondDistance / $firstDistance)
            $closedRatio | Should -BeGreaterThan 0.20
            $closedRatio | Should -BeLessThan 0.50
        }

        It 'never collapses below BaseStep even at the limit (still moves on tap)' {
            # 1 unit from Max, single tap. Dampener at maximum, but BaseStep floor
            # guarantees movement.
            $r = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 999999 -Direction 1 -Min 0 -Max 1000000 `
                    -BaseStep 1 -Precision 0 -HoldMs 0
            }
            $r | Should -Be 1000000
        }
    }

    Context 'Precision quantization' {
        It 'produces a value at the configured precision (no extra decimals)' {
            $r = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 0.0 -Direction 1 -Min 0.0 -Max 10.0 `
                    -BaseStep 0.01 -Precision 2 -HoldMs 0
            }
            $r | Should -Be 0.01
            # Round-trip through decimal scale check
            ([decimal]::GetBits($r))[3] | Should -BeGreaterOrEqual 0
        }

        It 'quantizes a held step to the precision quantum' {
            # With Precision=2, accelerated steps should land on .01 multiples
            $r = InModuleScope pwshTui {
                Get-AcceleratedStep -Current 5.00 -Direction 1 -Min 0.0 -Max 10.0 `
                    -BaseStep 0.01 -Precision 2 -HoldMs 500
            }
            # Multiply by 100 — result should be an integer (no .001-style residue)
            (($r * 100) - [Math]::Floor([double]($r * 100))) | Should -Be 0
        }
    }

    Context 'Direction validation' {
        It 'throws on Direction = 0' {
            { InModuleScope pwshTui {
                Get-AcceleratedStep -Current 0 -Direction 0 -Min 0 -Max 10 `
                    -BaseStep 1 -Precision 0 -HoldMs 0
            } } | Should -Throw
        }

        It 'throws on Direction = 2' {
            { InModuleScope pwshTui {
                Get-AcceleratedStep -Current 0 -Direction 2 -Min 0 -Max 10 `
                    -BaseStep 1 -Precision 0 -HoldMs 0
            } } | Should -Throw
        }
    }
}

# Read-Number's -Bar switch is the new generalized progress-bar feature
# (Read-Percentage -Bar now pass-through to it). The interactive widget is
# untestable directly, but we can build the decorator the same way the
# widget does internally (capturing -Min/-Max/-BarWidth/-Ascii/-NoColor
# into a closure) and verify the rendered output for an arbitrary range
# matches the underlying Format-ValueBar helper.

Describe 'Read-Number -Bar (non-percentage ranges)' {
    It 'a port-number range (1..65535) at midpoint renders ~half-full bar' {
        # 32768 in [1..65535] → ratio (32767/65534) ≈ 0.4999 → 10/20 cells
        $s = InModuleScope pwshTui {
            Format-ValueBar -Value 32768 -Min 1 -Max 65535 -Width 20 -Ascii -NoColor
        }
        ($s.Substring(1, 20) -replace '-', '').Length | Should -Be 10
    }

    It 'a temperature range (-50..150 °C) at 100°C renders ~3/4 full' {
        # 100 in [-50..150] → ratio = 150/200 = 0.75 → 15/20 cells
        $s = InModuleScope pwshTui {
            Format-ValueBar -Value 100 -Min -50 -Max 150 -Width 20 -Ascii -NoColor
        }
        ($s.Substring(1, 20) -replace '-', '').Length | Should -Be 15
    }

    It 'a billion-scale range renders accurately at small absolute values' {
        # 250M in [0..1B] → ratio = 0.25 → 5/20 cells
        $s = InModuleScope pwshTui {
            Format-ValueBar -Value 250000000 -Min 0 -Max 1000000000 -Width 20 -Ascii -NoColor
        }
        ($s.Substring(1, 20) -replace '-', '').Length | Should -Be 5
    }
}
