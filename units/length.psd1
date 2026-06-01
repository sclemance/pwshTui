@{
    Family = 'Length'
    Base   = 'meter'

    DefaultOutputUnit = @{
        Metric   = 'meter'
        Imperial = 'foot'
    }

    UnitDefaults = @{
        meter         = @{ Min = 0; Max = 10000;   Default = 1 }
        centimeter    = @{ Min = 0; Max = 100000;  Default = 100 }
        foot          = @{ Min = 0; Max = 32808;   Default = 3 }
        inch          = @{ Min = 0; Max = 393700;  Default = 36 }
        micrometer    = @{ Min = 0; Max = 1000000; Default = 100 }
        decameter     = @{ Min = 0; Max = 10000;   Default = 10 }
        'nautical-mile' = @{ Min = 0; Max = 12000; Default = 100 }
        fathom        = @{ Min = 0; Max = 6000;    Default = 6 }
        parsec        = @{ Min = 0; Max = 1000000; Default = 1 }
    }

    Units = @(
        @{ Name = 'meter';      Aliases = @('m','meters');                      ToBase = 1.0 }
        @{ Name = 'centimeter'; Aliases = @('cm','centimeters');                ToBase = 0.01 }
        @{ Name = 'millimeter'; Aliases = @('mm','millimeters');                ToBase = 0.001 }
        @{ Name = 'micrometer'; Aliases = @('µm','um','micrometers','micron','microns'); ToBase = 0.000001 }
        @{ Name = 'decameter';  Aliases = @('dam','decameters');                ToBase = 10.0 }
        @{ Name = 'kilometer';  Aliases = @('km','kilometers');                 ToBase = 1000.0 }
        @{ Name = 'inch';       Aliases = @('in','inches','"','″');             ToBase = 0.0254 }
        @{ Name = 'foot';       Aliases = @('ft','feet',"'",'′');               ToBase = 0.3048 }
        @{ Name = 'yard';       Aliases = @('yd','yards');                      ToBase = 0.9144 }
        @{ Name = 'mile';       Aliases = @('mi','miles');                      ToBase = 1609.344 }
        # International nautical mile (1929-): exactly 1852 m. ICAO/IMO standard.
        # 'NM' is the canonical symbol; 'nmi' is the ICAO form. Hyphenated long
        # form keeps the alias single-token so the substring matcher does not
        # need to handle whitespace inside the alias.
        @{ Name = 'nautical-mile'; Aliases = @('NM','nmi','nautical-miles');    ToBase = 1852.0 }
        # International fathom: 6 feet exactly = 1.8288 m. Maritime depth unit.
        # 'ftm' wins over 'ft' via longest-match-first so "5ftm" parses as
        # fathoms, "5ft" as feet.
        @{ Name = 'fathom';     Aliases = @('ftm','fathoms');                   ToBase = 1.8288 }
        # 1 parsec = 648000/π au exactly (IAU 2015); ≈ 3.0856775814913673e16 m.
        # Far beyond meter UnitDefaults' Max — only meaningful with -OutputUnit parsec.
        @{ Name = 'parsec';     Aliases = @('pc','parsecs');                    ToBase = 30856775814913673 }
    )
}
