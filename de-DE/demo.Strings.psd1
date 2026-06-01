# Lokalisierte Zeichenketten für die pwshTui-Demo (de-DE).
# Deckt Deutsch (Deutschland/Österreich/Schweiz) via Kulturkette ab.
ConvertFrom-StringData @'
Menu_Group_SelectionMenus     = Auswahl & Menüs
Menu_Group_InputPrompts       = Eingaben
Menu_Group_DateTime           = Datum & Uhrzeit
Menu_Group_AsyncLayout        = Asynchron & Layout
Menu_ToggleRenderMode         = Anzeigemodus umschalten (aktuell: {0})
Menu_ChangeLanguage           = Sprache ändern (aktuell: {0})
Menu_ExitDemo                 = Demo beenden

Menu_Paginated                = Paginierte Auswahl (suchbar)
Menu_PaginatedJump            = Paginierte Auswahl (-InitialIndex Sprung zu #25)
Menu_MultiSelect              = Paginierte Mehrfachauswahl (Leertaste schaltet um)
Menu_Nested                   = Verschachteltes Menü
Menu_NestedDeep               = Verschachteltes Menü (-InitialPath Deep-Link)
Menu_NestedBordered           = Verschachteltes Menü (umrahmt + AltScreen)

Menu_MaskedInput              = Maskierte Eingabe (Telefon, MAC)
Menu_PasswordInput            = Passworteingabe (SecureString, Bestätigung, PIN)
Menu_ValidatedInput           = Validierte Eingabe (IPv4, CIDR, E-Mail)
Menu_Confirmation             = Ja/Nein-Bestätigung
Menu_ChoiceSelector           = Auswahlfeld (einfach + mehrfach)
Menu_NumberInput              = Zahleneingabe (Einheiten, Trennzeichen, beschleunigende Pfeile)
Menu_TemplatedWrappers        = Vorlagen-Wrapper (Telefon, E-Mail, IPv4, CIDR, URL)

Menu_DateInline               = Read-Date (Inline-Felder)
Menu_DateCalendar             = Read-Date -Calendar (mit Monatsraster)
Menu_Time24                   = Read-Time (24-Stunden)
Menu_Time12                   = Read-Time -TwelveHour -ShowSeconds
Menu_Timezone                 = Read-Timezone (mit bevorzugter Liste)

Menu_Spinner                  = Show-Spinner (Braille-Standard)
Menu_SpinnerTimer             = Show-Spinner mit -ShowTimer
Menu_SpinnerStyles            = Show-Spinner — alle sechs Stile
Menu_SpinnerClosure           = Show-Spinner — Closure-Erfassung
Menu_UIBox                    = Write-TuiBox (eigenständig)

Title_Demo                    = pwshTui-Demo [{0} | {1}]
Title_SelectSystemObject      = Systemobjekt auswählen
Title_JumpedToItem25          = Sprung zu Element 25
Title_PickMultiple            = Mehrere Objekte wählen
Title_AdminPortal             = Admin-Portal
Title_BorderedMenu            = Umrahmtes Menü
Title_SystemStatus            = Systemstatus

Header_Paginated              = Get-PaginatedSelection (suchbar)
Header_PaginatedJump          = Get-PaginatedSelection (-InitialIndex springt zu einem bestimmten Element)
Header_MultiSelect            = Get-PaginatedSelection -MultiSelect
Header_NestedMenu             = Invoke-NestedMenu
Header_NestedMenuDeep         = Invoke-NestedMenu -InitialPath (Deep-Link zu Power Saver)
Header_NestedMenuBordered     = Invoke-NestedMenu (umrahmt, positioniert, AltScreen)
Header_MaskedInput            = Read-MaskedInput
Header_Password               = Read-Password
Header_ValidatedInput         = Read-ValidatedInput
Header_Confirmation           = Read-Confirmation
Header_Choice                 = Read-Choice
Header_Number                 = Read-Number (Einheiten, Trennzeichen, beschleunigende Pfeile)
Header_Spinner                = Show-Spinner (Braille-Standard)
Header_SpinnerTimer           = Show-Spinner -ShowTimer
Header_SpinnerStyles          = Show-Spinner — alle sechs Stile, jeweils 1,5 s
Header_SpinnerClosure         = Show-Spinner — Closures funktionieren einfach
Header_UIBox                  = Write-TuiBox (eigenständig)
Header_Date                   = Read-Date (inline)
Header_DateCalendar           = Read-Date -Calendar (mit Monatsraster)
Header_Time                   = Read-Time (24-Stunden)
Header_TimeTwelve             = Read-Time -TwelveHour -ShowSeconds
Header_TemplatedWrappers      = Eingabe-Vorlagen-Wrapper (Telefon, E-Mail, IPv4, CIDR, URL)
Header_Timezone               = Read-Timezone

Hint_Paginated                = Tippen zum Fuzzy-Suchen; Pfeile zum Navigieren; Enter zum Auswählen; Esc zum Abbrechen.
Hint_MultiSelect              = Leertaste schaltet um (Auswahlmodus); Tab wechselt zum Suchmodus; Tippen filtert; Pfeile kehren in den Auswahlmodus zurück (erste Zeile markiert); Enter bestätigt; Esc bricht ab.
Hint_NestedBordered           = Zeichne Menü mit -Border -MinWidth 40 -X 5 -Y 15 -AltScreen...
Hint_Password1                = Tippen zur Eingabe; Backspace löscht; Enter sendet; Esc bricht ab.
Hint_Password2                = Stärkeanzeige erscheint live rechts neben der maskierten Eingabe.
Hint_Confirmation             = J/N für Sofortantwort; Links/Rechts/Tab bewegt die Markierung; Enter bestätigt; Esc bricht ab.
Hint_Choice                   = Pfeiltasten oder Ziffer 1-N zum Bewegen; Enter zum Bestätigen; Esc zum Abbrechen.
Hint_ChoiceMulti              = Mehrfachauswahl: Leertaste schaltet um, Ziffern bewegen den Fokus, Enter gibt das Array zurück.
Hint_Number1                  = Hoch/Runter zum Verstellen, halten zum Beschleunigen (Kurve skaliert mit der Spanne und bremst nahe den Grenzen ab). PgUp/PgDn springen um 10*Step.
Hint_Number2                  = Ziffern direkt eintippen; Backspace/Entf bearbeiten den Puffer; Enter bestätigt, wenn im Bereich; Esc bricht ab.
Hint_Spinner                  = Führe einen 2-Sekunden-Sleep aus...
Hint_SpinnerTimer             = Führe einen 3,5-Sekunden-Sleep mit Live-Zeitanzeige aus...
Hint_SpinnerStylesAscii       = ASCII-Modus ist an — -Ascii erzwingt Style=Ascii unabhängig von -Style, daher rendern alle vier als das Ascii-Glyph unten. ASCII deaktivieren, um jeden Stil wie benannt zu sehen.
Hint_SpinnerClosure           = Aufrufende Scope hält $magicNumber = {0}. Der Scriptblock nutzt sie ohne -ArgumentList.
Hint_Date                     = ← → bewegt Felder, ↑ ↓ passt den fokussierten Wert an, Ziffern füllen das Feld, Tab schaltet Modi um.
Hint_DateCalendar1            = Gleiches Eingabemodell wie der Inline-Picker; das Raster ist schreibgeschützter Kontext für den fokussierten Tag.
Hint_DateCalendar2            = Begrenzt auf heute..heute+1 Jahr; Enter ist außerhalb dieses Bereichs blockiert.
Hint_Time                     = Vier Ziffern eintippen, um HH:MM in einem Rutsch zu füllen (1430 → 14:30); Pfeile für Feldnavigation + Hoch/Runter zum Anpassen.
Hint_TimeTwelve               = 12-Stunden-Uhr mit AM/PM (a/p-Shortcuts) und Sekundenfeld. Interne Speicherung bleibt 24-Stunden.
Hint_Templated                = Jeder Wrapper kodiert fest eine Maske oder Regex für eine der gängigen Eingabeformen. Esc überspringt zur nächsten.
Hint_Timezone1                = Lokale Zone standardmäßig markiert; häufige Zonen oben angeheftet mit führendem "*".
Hint_Timezone2                = Erbt die Suche der paginierten Auswahl — Tab zum Filtern.

Prompt_PhoneNumber            = Telefonnummer:
Prompt_MacAddress             = MAC-Adresse:
Prompt_Password               = Passwort:
Prompt_NewPassword            = Neues Passwort:
Prompt_Retype                 = Wiederholen:
Prompt_PIN                    = PIN (verborgene Länge):
Prompt_IPv4                   = IPv4-Adresse:
Prompt_CIDR                   = CIDR-Notation:
Prompt_Email                  = E-Mail-Adresse:
Prompt_DeleteFile             = Datei löschen?
Prompt_PickColor              = Farbe wählen:
Prompt_PickToppings           = Beläge wählen:
Prompt_PickDate               = Datum wählen:
Prompt_ScheduleFor            = Planen für:
Prompt_StartTime              = Startzeit:
Prompt_Alarm                  = Alarm:
Prompt_Phone                  = Telefon:
Prompt_EmailShort             = E-Mail:
Prompt_IPv4Short              = IPv4-Adresse:
Prompt_CIDRShort              = CIDR-Notation:
Prompt_URL                    = URL:
Prompt_Port                   = Port:
Prompt_Coverage               = Abdeckung:
Prompt_Temperature            = Temperatur:
Prompt_Budget                 = Budget:
Prompt_Amount                 = Betrag:

Activity_Working              = Arbeite
Activity_Querying             = Abfrage
Activity_Computing            = Berechne
Activity_StylePrefix          = Stil: {0}

Result_YouSelected            = Ausgewählt: {0}
Result_YouSelectedWithID      = Ausgewählt: {0} (ID: {1})
Result_SelectionCancelled     = Auswahl abgebrochen.
Result_Cancelled              = Abgebrochen.
Result_CancelledNull          = Abgebrochen (Rückgabe $null).
Result_CancelledOrExhausted   = Abgebrochen oder Versuche aufgebraucht.
Result_ConfirmedNoSelections  = Bestätigt ohne Auswahl.
Result_SelectedItems          = {0} Element(e) ausgewählt:
Result_Captured               = Erfasst: {0}
Result_CapturedPlainText      = Klartext erfasst: {0}
Result_CapturedSecureString   = SecureString erfasst, Länge {0}.
Result_ConfirmedSecureString  = SecureString bestätigt, Länge {0}.
Result_Strength               = Stärke: {0} (Score {1}/6, {2} Zeichenklassen)
Result_ConfirmedYes           = Bestätigt: Ja
Result_ConfirmedNo            = Bestätigt: Nein
Result_CapturedNone           = Erfasst: (keine)
Result_AllStylesShown         = Alle Stile gezeigt.
Result_ScriptblockReturned    = Scriptblock gab zurück: {0} (erwartet: 84)
Result_Done                   = Fertig.
Result_MenuCancelled          = Menü abgebrochen.
Result_CapturedAction         = Aktion erfasst: {0}
Result_SelectedTimezone       = Ausgewählt: {0}
Result_TimezoneDisplay        = Anzeige:  {0}
Result_LocalNow               = Lokal jetzt:   {0}
Result_InSelected             = In Ausgewählter: {0}
Result_SelectedDate           = Ausgewählt: {0}
Result_SelectedTime           = Ausgewählt: {0}

Common_PressAnyKey            = [ Beliebige Taste drücken, um zum Menü zurückzukehren ]
Common_Thanks                 = Danke, dass Sie pwshTui ausprobiert haben.
Common_CouldNotLoadLocale     = Konnte Sprache "{0}" nicht laden.
Common_DemoBox                = Demo-Box
Common_BodyCPU                = CPU: 12 %
Common_BodyRAM                = RAM: 4,2 GB
Common_BodyDisk               = Disk: 80 % voll
'@
