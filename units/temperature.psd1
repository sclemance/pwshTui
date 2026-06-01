@{
    Family            = 'Temperature'
    Base              = 'celsius'

    DefaultOutputUnit = @{
        Metric   = 'celsius'
        Imperial = 'fahrenheit'
    }

    # Regions that conventionally use Fahrenheit for everyday temperature.
    # (Liberia partially uses both; the rest exclusively use Fahrenheit.)
    # Overrides .NET's IsMetric so this list matches the historical
    # Read-Temperature behavior.
    ImperialRegions = @('US', 'BS', 'BZ', 'KY', 'PW', 'FM', 'MH', 'LR')

    # Per-unit defaults for Read-Measurement -DefaultsByUnit. Mirror the
    # historical Read-Temperature defaults so existing callers see the
    # same UX. Values are in the unit named by the key.
    UnitDefaults = @{
        celsius    = @{ Min = -100; Max = 150; Default = 20  }
        fahrenheit = @{ Min = -148; Max = 302; Default = 68  }
        kelvin     = @{ Min = 173;  Max = 423; Default = 293 }
    }

    # ToBase convention: base_value = (input + Offset) * Scale.
    # 5/9 is approximated to 0.55555556 — accepts ~3e-8 rounding for the
    # closed-form formulas. Aliases are case-sensitive; the degree sign
    # is literal UTF-8.
    Units = @(
        @{ Name = 'celsius';    Aliases = @('°C','C','degC');   ToBase = 1.0;
           Suffix = ' °C' }
        @{ Name = 'fahrenheit'; Aliases = @('°F','F','degF');
           ToBase = @{ Scale = 0.55555556; Offset = -32.0 };
           Suffix = ' °F' }
        @{ Name = 'kelvin';     Aliases = @('K');
           ToBase = @{ Scale = 1.0; Offset = -273.15 };
           Suffix = ' K' }
    )
}
