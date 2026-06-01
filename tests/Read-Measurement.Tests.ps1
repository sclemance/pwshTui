BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'pwshTui.psd1'
    Import-Module $modulePath -Force
}

# Read-Measurement is a thin shim over Read-Number. Most of the substance is
# in the engine helpers (Import-/Get-MeasurementFamily, ConvertTo/-From-
# MeasurementBase, Get-MeasurementOutputUnit, ConvertTo-MeasurementValue),
# which are module-private and tested directly via InModuleScope.

Describe 'Import-MeasurementFamily' {
    It 'returns a hashtable for a bundled family (case-insensitive)' {
        $fam = InModuleScope pwshTui { Import-MeasurementFamily -Family Length }
        $fam | Should -Not -BeNullOrEmpty
        $fam.Family | Should -Be 'Length'
        $fam.Base | Should -Be 'meter'
    }

    It 'matches family names case-insensitively against the filename' {
        # Linux/macOS file paths are case-sensitive; -Family Length must
        # still find units/length.psd1.
        $upper = InModuleScope pwshTui { Import-MeasurementFamily -Family LENGTH }
        $upper | Should -Not -BeNullOrEmpty
        $upper.Family | Should -Be 'Length'
    }

    It 'returns $null for an unknown family' {
        $r = InModuleScope pwshTui { Import-MeasurementFamily -Family DefinitelyNotARealFamily }
        $r | Should -BeNullOrEmpty
    }
}

Describe 'Get-MeasurementFamily' {
    It 'lists the bundled length family' {
        Get-MeasurementFamily | Should -Contain 'length'
    }
}

Describe 'ConvertTo-MeasurementBase' {
    BeforeAll {
        $script:lengthFam = InModuleScope pwshTui { Import-MeasurementFamily -Family Length }
    }

    It 'pure-ratio: 1 foot equals 0.3048 meter' {
        $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
            param($Fam)
            ConvertTo-MeasurementBase -Value 1 -Family $Fam -UnitName foot
        }
        $r | Should -Be ([decimal]0.3048)
    }

    It 'pure-ratio: 100 cm equals 1 m' {
        $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
            param($Fam)
            ConvertTo-MeasurementBase -Value 100 -Family $Fam -UnitName centimeter
        }
        $r | Should -Be ([decimal]1.00)
    }

    It 'affine: 32 °F equals 0 °C (synthetic temperature family)' {
        # Affine support is engine-level; the bundled length family has no
        # affine units, so we synthesize a tiny family inline.
        $tempFam = @{
            Family = 'TestTemp'
            Base   = 'celsius'
            Units  = @(
                @{ Name = 'celsius';    Aliases = @('C'); ToBase = 1.0 }
                @{ Name = 'fahrenheit'; Aliases = @('F');
                   ToBase = @{ Scale = ([double](5 / 9)); Offset = -32.0 } }
            )
        }
        $r = InModuleScope pwshTui -Parameters @{ Fam = $tempFam } {
            param($Fam)
            ConvertTo-MeasurementBase -Value 32 -Family $Fam -UnitName fahrenheit
        }
        [Math]::Abs($r) | Should -BeLessThan 1e-6
    }

    It 'affine: 212 °F equals 100 °C' {
        $tempFam = @{
            Family = 'TestTemp'; Base = 'celsius'
            Units  = @(
                @{ Name = 'celsius';    Aliases = @('C'); ToBase = 1.0 }
                @{ Name = 'fahrenheit'; Aliases = @('F');
                   ToBase = @{ Scale = ([double](5 / 9)); Offset = -32.0 } }
            )
        }
        $r = InModuleScope pwshTui -Parameters @{ Fam = $tempFam } {
            param($Fam)
            ConvertTo-MeasurementBase -Value 212 -Family $Fam -UnitName fahrenheit
        }
        [Math]::Abs($r - 100) | Should -BeLessThan 1e-6
    }

    It 'throws on an unknown unit name' {
        {
            InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementBase -Value 1 -Family $Fam -UnitName not-a-real-unit
            }
        } | Should -Throw
    }
}

Describe 'ConvertFrom-MeasurementBase' {
    BeforeAll {
        $script:lengthFam = InModuleScope pwshTui { Import-MeasurementFamily -Family Length }
    }

    It 'round-trips 1 foot through base and back' {
        $base = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
            param($Fam)
            ConvertTo-MeasurementBase -Value 1 -Family $Fam -UnitName foot
        }
        $rt = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam; B = $base } {
            param($Fam, $B)
            ConvertFrom-MeasurementBase -BaseValue $B -Family $Fam -UnitName foot
        }
        [Math]::Abs($rt - 1) | Should -BeLessThan 1e-9
    }

    It '0 °C reads back as 32 °F (affine inverse)' {
        $tempFam = @{
            Family = 'TestTemp'; Base = 'celsius'
            Units  = @(
                @{ Name = 'celsius';    Aliases = @('C'); ToBase = 1.0 }
                @{ Name = 'fahrenheit'; Aliases = @('F');
                   ToBase = @{ Scale = ([double](5 / 9)); Offset = -32.0 } }
            )
        }
        $r = InModuleScope pwshTui -Parameters @{ Fam = $tempFam } {
            param($Fam)
            ConvertFrom-MeasurementBase -BaseValue 0 -Family $Fam -UnitName fahrenheit
        }
        [Math]::Abs($r - 32) | Should -BeLessThan 1e-6
    }
}

Describe 'Get-MeasurementOutputUnit' {
    It 'returns Base when DefaultOutputUnit is absent' {
        $fam = @{ Family = 'Tiny'; Base = 'widget'; Units = @(@{ Name='widget'; Aliases=@(); ToBase = 1.0 }) }
        $r = InModuleScope pwshTui -Parameters @{ Fam = $fam } {
            param($Fam)
            Get-MeasurementOutputUnit -Family $Fam
        }
        $r | Should -Be 'widget'
    }

    It 'returns Metric or Imperial depending on the current region' {
        $fam = InModuleScope pwshTui { Import-MeasurementFamily -Family Length }
        $r = InModuleScope pwshTui -Parameters @{ Fam = $fam } {
            param($Fam)
            Get-MeasurementOutputUnit -Family $Fam
        }
        $r | Should -BeIn @('meter', 'foot')
    }

    It 'picks Imperial when ImperialRegions matches the current region' {
        # Use a region likely to NOT match real ImperialRegions, then prove
        # the function reads ImperialRegions: synthesize one containing the
        # current region's two-letter code.
        $regionCode = [System.Globalization.RegionInfo]::CurrentRegion.TwoLetterISORegionName
        $fam = @{
            Family = 'Fake'; Base = 'm'
            DefaultOutputUnit = @{ Metric = 'm'; Imperial = 'imp' }
            ImperialRegions = @($regionCode)
            Units = @(
                @{ Name='m';   Aliases=@(); ToBase = 1.0 }
                @{ Name='imp'; Aliases=@(); ToBase = 1.0 }
            )
        }
        $r = InModuleScope pwshTui -Parameters @{ Fam = $fam } {
            param($Fam)
            Get-MeasurementOutputUnit -Family $Fam
        }
        $r | Should -Be 'imp'
    }
}

Describe 'ConvertTo-MeasurementValue (parser)' {
    BeforeAll {
        $script:lengthFam = InModuleScope pwshTui { Import-MeasurementFamily -Family Length }
    }

    Context 'Single-unit input' {
        It '"12.5ft" parses to 3.81 m' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '12.5ft' -Family $Fam
            }
            $r.Ok | Should -BeTrue
            [Math]::Abs($r.Value - 3.81) | Should -BeLessThan 1e-9
        }

        It '"100cm" parses to 1 m' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '100cm' -Family $Fam
            }
            $r.Ok | Should -BeTrue
            [Math]::Abs($r.Value - 1) | Should -BeLessThan 1e-9
        }

        It 'bare "5" with no -InputUnit falls back to the family Base (meter)' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '5' -Family $Fam
            }
            $r.Ok | Should -BeTrue
            $r.Value | Should -Be 5
        }

        It 'bare "5" with -InputUnit foot resolves to 1.524 m' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '5' -Family $Fam -InputUnit foot
            }
            $r.Ok | Should -BeTrue
            [Math]::Abs($r.Value - 1.524) | Should -BeLessThan 1e-9
        }

        It '"feet" beats "ft" via longest-match-wins alias resolution' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '3feet' -Family $Fam
            }
            $r.Ok | Should -BeTrue
            [Math]::Abs($r.Value - (3 * 0.3048)) | Should -BeLessThan 1e-9
        }

        It '"500µm" parses to 5e-4 m (micrometer with micro sign)' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '500µm' -Family $Fam
            }
            $r.Ok | Should -BeTrue
            [Math]::Abs($r.Value - 0.0005) | Should -BeLessThan 1e-9
        }

        It '"500um" (ASCII-friendly micrometer alias) parses the same as 500µm' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '500um' -Family $Fam
            }
            $r.Ok | Should -BeTrue
            [Math]::Abs($r.Value - 0.0005) | Should -BeLessThan 1e-9
        }

        It '"3dam" parses to 30 m (decameter)' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '3dam' -Family $Fam
            }
            $r.Ok | Should -BeTrue
            $r.Value | Should -Be 30
        }

        It '"1pc" round-trips through base back to 1 parsec' {
            $base = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                (ConvertTo-MeasurementValue -Buffer '1pc' -Family $Fam).Value
            }
            $back = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam; B = $base } {
                param($Fam, $B)
                ConvertFrom-MeasurementBase -BaseValue $B -Family $Fam -UnitName parsec
            }
            $back | Should -Be ([decimal]1)
        }

        It '"1NM" parses to 1852 m (international nautical mile)' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '1NM' -Family $Fam
            }
            $r.Ok | Should -BeTrue
            $r.Value | Should -Be 1852
        }

        It '"100nmi" parses to 185200 m (ICAO alias)' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '100nmi' -Family $Fam
            }
            $r.Ok | Should -BeTrue
            $r.Value | Should -Be 185200
        }

        It '"6ftm" parses to 10.9728 m (fathom — longest-match beats ft)' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '6ftm' -Family $Fam
            }
            $r.Ok | Should -BeTrue
            [Math]::Abs([double]($r.Value - 10.9728)) | Should -BeLessThan 1e-9
        }

        It 'compound "1nmi 5ftm" sums nautical mile + fathom to 1861.144 m' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '1nmi 5ftm' -Family $Fam
            }
            $r.Ok | Should -BeTrue
            # 1852 + 5*1.8288 = 1861.144
            [Math]::Abs([double]($r.Value - 1861.144)) | Should -BeLessThan 1e-9
        }
    }

    Context 'Compound input' {
        It '"12ft 3in" sums to 3.7338 m' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '12ft 3in' -Family $Fam
            }
            $r.Ok | Should -BeTrue
            [Math]::Abs($r.Value - 3.7338) | Should -BeLessThan 1e-9
        }

        It '"5''11"" (apostrophe + double-quote aliases) parses to 1.8034 m' {
            $buf = "5'11`""
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam; B = $buf } {
                param($Fam, $B)
                ConvertTo-MeasurementValue -Buffer $B -Family $Fam
            }
            $r.Ok | Should -BeTrue
            [Math]::Abs($r.Value - 1.8034) | Should -BeLessThan 1e-9
        }

        It '"1m 50cm" parses to 1.5 m' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '1m 50cm' -Family $Fam
            }
            $r.Ok | Should -BeTrue
            [Math]::Abs($r.Value - 1.5) | Should -BeLessThan 1e-9
        }
    }

    Context 'Rejection' {
        It 'empty buffer reports Reason=empty' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '' -Family $Fam
            }
            $r.Ok | Should -BeFalse
            $r.Reason | Should -Be 'empty'
        }

        It 'garbage "abc" reports Reason=unparseable' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer 'abc' -Family $Fam
            }
            $r.Ok | Should -BeFalse
            $r.Reason | Should -Be 'unparseable'
        }

        It 'unknown unit "12xyz" reports Reason=unknown-unit' {
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '12xyz' -Family $Fam
            }
            $r.Ok | Should -BeFalse
            $r.Reason | Should -Be 'unknown-unit'
        }

        It 'trailing non-numeric junk after a valid prefix rejects the whole buffer' {
            # "12ft 3in $" parses the first two components, then attempts a
            # third starting at "$" — which is neither a digit nor a sign,
            # so the signed-number sub-parser fails. The user-visible result
            # is the same as 'unknown-unit': the buffer turns red and Enter
            # is blocked. We accept either Reason since both are valid
            # rejection paths.
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '12ft 3in $' -Family $Fam
            }
            $r.Ok | Should -BeFalse
            $r.Reason | Should -BeIn @('unparseable', 'unknown-unit')
        }

        It 'a number with an unknown alias attached rejects as unknown-unit' {
            # Distinguishes the "found a number but the alias is wrong" path
            # from the "did not even find a number" path tested above.
            $r = InModuleScope pwshTui -Parameters @{ Fam = $script:lengthFam } {
                param($Fam)
                ConvertTo-MeasurementValue -Buffer '12ft 3junk' -Family $Fam
            }
            $r.Ok | Should -BeFalse
            $r.Reason | Should -Be 'unknown-unit'
        }
    }
}

Describe 'Read-Measurement (forwarding)' {
    It 'falls through to Read-Number with numeric pass-throughs when the family is missing' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]42 }
            $r = Read-Measurement -Prompt 'X:' -Family NoSuchFamily -Min 0 -Max 100 -Default 10
            $r | Should -Be 42
            Should -Invoke Read-Number -Times 1 -ParameterFilter {
                $Min -eq 0 -and $Max -eq 100 -and $Default -eq 10 -and `
                ($null -eq $BufferParser) -and ($null -eq $Decorator)
            }
        }
    }

    It 'forwards a BufferParser closure to Read-Number when the family loads' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]1.8034 }
            # OutputUnit=meter so the base-to-OutputUnit conversion on the
            # return value is a no-op and we can pin down the exact decimal.
            $r = Read-Measurement -Prompt 'X:' -Family Length -OutputUnit meter `
                -Min 0 -Max 100 -Default 0
            $r | Should -Be ([decimal]1.8034)
            Should -Invoke Read-Number -Times 1 -ParameterFilter {
                $null -ne $BufferParser
            }
        }
    }

    It 'converts the base value returned by Read-Number into -OutputUnit' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]1.8034 }  # base meters
            $r = Read-Measurement -Prompt 'X:' -Family Length -OutputUnit foot `
                -Min 0 -Max 100 -Default 0
            # 1.8034 m / 0.3048 m/ft ≈ 5.9166 ft
            [Math]::Abs([double]($r - 5.9166666667)) | Should -BeLessThan 1e-6
        }
    }

    It '-DefaultsByUnit pulls Min/Max/Default from the family file (converted to base)' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]1 }
            Read-Measurement -Prompt 'X:' -Family Length -OutputUnit foot -DefaultsByUnit | Out-Null
            # foot defaults: Min=0, Max=32808, Default=3 → in meters:
            # 0, 32808 * 0.3048 = 9999.8784, 3 * 0.3048 = 0.9144
            Should -Invoke Read-Number -Times 1 -ParameterFilter {
                $Min -eq ([decimal]0) -and
                [Math]::Abs([double]($Max - 9999.8784)) -lt 1e-6 -and
                [Math]::Abs([double]($Default - 0.9144)) -lt 1e-6
            }
        }
    }

    It 'forwards a Decorator scriptblock by default (-ShowConversion is on)' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]1.524 }
            Read-Measurement -Prompt 'X:' -Family Length -OutputUnit foot `
                -Min 0 -Max 100 -Default 0 | Out-Null
            Should -Invoke Read-Number -Times 1 -ParameterFilter {
                $null -ne $Decorator
            }
        }
    }

    It '-ShowConversion:$false omits the Decorator' {
        InModuleScope pwshTui {
            Mock Read-Number { return [decimal]1.524 }
            Read-Measurement -Prompt 'X:' -Family Length -OutputUnit foot `
                -Min 0 -Max 100 -Default 0 -ShowConversion:$false | Out-Null
            Should -Invoke Read-Number -Times 1 -ParameterFilter {
                $null -eq $Decorator
            }
        }
    }
}
