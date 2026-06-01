@{
    Family = 'Length'
    Base   = 'meter'

    DefaultOutputUnit = @{
        Metric   = 'meter'
        Imperial = 'foot'
    }

    UnitDefaults = @{
        meter      = @{ Min = 0; Max = 10000;  Default = 1 }
        centimeter = @{ Min = 0; Max = 100000; Default = 100 }
        foot       = @{ Min = 0; Max = 32808;  Default = 3 }
        inch       = @{ Min = 0; Max = 393700; Default = 36 }
    }

    Units = @(
        @{ Name = 'meter';      Aliases = @('m','meters');             ToBase = 1.0 }
        @{ Name = 'centimeter'; Aliases = @('cm','centimeters');       ToBase = 0.01 }
        @{ Name = 'millimeter'; Aliases = @('mm','millimeters');       ToBase = 0.001 }
        @{ Name = 'kilometer';  Aliases = @('km','kilometers');        ToBase = 1000.0 }
        @{ Name = 'inch';       Aliases = @('in','inches','"','″');    ToBase = 0.0254 }
        @{ Name = 'foot';       Aliases = @('ft','feet',"'",'′');      ToBase = 0.3048 }
        @{ Name = 'yard';       Aliases = @('yd','yards');             ToBase = 0.9144 }
        @{ Name = 'mile';       Aliases = @('mi','miles');             ToBase = 1609.344 }
    )
}
