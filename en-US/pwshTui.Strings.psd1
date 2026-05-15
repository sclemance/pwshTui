# Localized UI strings for pwshTui (en-US — fallback culture).
# Loaded by Import-LocalizedData at module import based on $PSUICulture.
# PowerShell walks the culture hierarchy: e.g. en-CA → en-US → invariant,
# so add new locales as <culture>/pwshTui.Strings.psd1.
ConvertFrom-StringData @'
Footer_Move      = Move
Footer_Select    = Select
Footer_Confirm   = Confirm
Footer_Cancel    = Cancel
Footer_Exit      = Exit
Footer_Toggle    = Toggle
Footer_Expand    = Expand
Footer_Back      = Back
Footer_PrevPage  = Prev page
Footer_NextPage  = Next page
Footer_Selected  = selected
Footer_Search    = Search
Status_NoMatches = (No matches found)
Status_NoItems   = No items to select.
Status_Cancelled = (cancelled)
Status_DoneIn    = done in
'@
