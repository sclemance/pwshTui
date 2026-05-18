# Chaînes localisées pour la démo pwshTui (fr-FR).
# Couvre français / canadien / belge / suisse via la chaîne de cultures.
ConvertFrom-StringData @'
Menu_Group_SelectionMenus     = Sélection et menus
Menu_Group_InputPrompts       = Saisies
Menu_Group_DateTime           = Date et heure
Menu_Group_AsyncLayout        = Asynchrone et mise en page
Menu_ToggleRenderMode         = Mode de rendu (actuellement : {0})
Menu_ChangeLanguage           = Changer la langue (actuellement : {0})
Menu_ExitDemo                 = Quitter la démo

Menu_Paginated                = Sélection paginée (recherche)
Menu_PaginatedJump            = Sélection paginée (-InitialIndex saut à #25)
Menu_MultiSelect              = Multi-sélection paginée (Espace bascule)
Menu_Nested                   = Menu imbriqué
Menu_NestedDeep               = Menu imbriqué (-InitialPath lien direct)
Menu_NestedBordered           = Menu imbriqué (bordé + AltScreen)

Menu_MaskedInput              = Saisie masquée (téléphone, MAC)
Menu_PasswordInput            = Mot de passe (SecureString, confirmation, NIP)
Menu_ValidatedInput           = Saisie validée (IPv4, CIDR, courriel)
Menu_Confirmation             = Confirmation Oui/Non
Menu_ChoiceSelector           = Sélecteur de choix (simple + multi)
Menu_TemplatedWrappers        = Encapsuleurs (Téléphone, Courriel, IPv4, CIDR, URL)

Menu_DateInline               = Read-Date (champs en ligne)
Menu_DateCalendar             = Read-Date -Calendar (avec grille mensuelle)
Menu_Time24                   = Read-Time (24 heures)
Menu_Time12                   = Read-Time -TwelveHour -ShowSeconds
Menu_Timezone                 = Read-Timezone (avec liste préférée)

Menu_Spinner                  = Show-Spinner (Braille par défaut)
Menu_SpinnerTimer             = Show-Spinner avec -ShowTimer
Menu_SpinnerStyles            = Show-Spinner — les six styles
Menu_SpinnerClosure           = Show-Spinner — capture de fermeture
Menu_UIBox                    = Write-TuiBox (autonome)

Title_Demo                    = Démo pwshTui [{0} | {1}]
Title_SelectSystemObject      = Sélectionner un objet système
Title_JumpedToItem25          = Saut à l'élément 25
Title_PickMultiple            = Choisir plusieurs objets
Title_AdminPortal             = Portail d'administration
Title_BorderedMenu            = Menu bordé
Title_SystemStatus            = État du système

Header_Paginated              = Get-PaginatedSelection (recherche)
Header_PaginatedJump          = Get-PaginatedSelection (-InitialIndex saute à un élément spécifique)
Header_MultiSelect            = Get-PaginatedSelection -MultiSelect
Header_NestedMenu             = Invoke-NestedMenu
Header_NestedMenuDeep         = Invoke-NestedMenu -InitialPath (lien direct vers Power Saver)
Header_NestedMenuBordered     = Invoke-NestedMenu (bordé, positionné, AltScreen)
Header_MaskedInput            = Read-MaskedInput
Header_Password               = Read-Password
Header_ValidatedInput         = Read-ValidatedInput
Header_Confirmation           = Read-Confirmation
Header_Choice                 = Read-Choice
Header_Spinner                = Show-Spinner (Braille par défaut)
Header_SpinnerTimer           = Show-Spinner -ShowTimer
Header_SpinnerStyles          = Show-Spinner — les six styles, 1,5 s chacun
Header_SpinnerClosure         = Show-Spinner — les fermetures fonctionnent
Header_UIBox                  = Write-TuiBox (autonome)
Header_Date                   = Read-Date (en ligne)
Header_DateCalendar           = Read-Date -Calendar (avec grille mensuelle)
Header_Time                   = Read-Time (24 heures)
Header_TimeTwelve             = Read-Time -TwelveHour -ShowSeconds
Header_TemplatedWrappers      = Encapsuleurs de saisie (Téléphone, Courriel, IPv4, CIDR, URL)
Header_Timezone               = Read-Timezone

Hint_Paginated                = Tapez pour rechercher ; flèches pour naviguer ; Entrée pour choisir ; Échap pour annuler.
Hint_MultiSelect              = Espace bascule (mode sélection) ; Tab passe en mode recherche ; tapez pour filtrer ; les flèches retournent en mode sélection avec la première ligne surlignée ; Entrée confirme ; Échap annule.
Hint_NestedBordered           = Affichage d'un menu avec -Border -MinWidth 40 -X 5 -Y 15 -AltScreen...
Hint_Password1                = Tapez pour saisir ; Retour arrière supprime ; Entrée soumet ; Échap annule.
Hint_Password2                = L'indicateur de force apparaît en direct à droite de la saisie masquée.
Hint_Confirmation             = O/N pour réponse instantanée ; Gauche/Droite/Tab pour déplacer ; Entrée pour confirmer ; Échap pour annuler.
Hint_Choice                   = Flèches ou chiffre 1-N pour déplacer ; Entrée pour confirmer ; Échap pour annuler.
Hint_ChoiceMulti              = Multi-sélection : Espace bascule, chiffres déplacent le focus, Entrée renvoie le tableau.
Hint_Spinner                  = Exécution d'une pause de 2 secondes...
Hint_SpinnerTimer             = Exécution d'une pause de 3,5 secondes avec compteur en direct...
Hint_SpinnerStylesAscii       = Le mode ASCII est activé — -Ascii impose Style=Ascii quel que soit -Style, donc les quatre s'affichent comme le glyphe Ascii ci-dessous. Désactivez ASCII pour voir chaque style nommé.
Hint_SpinnerClosure           = La portée appelante contient $magicNumber = {0}. Le scriptblock l'utilisera sans -ArgumentList.
Hint_Date                     = ← → déplacent les champs, ↑ ↓ ajustent la valeur ciblée, tapez des chiffres pour remplir le champ, Tab bascule les modes.
Hint_DateCalendar1            = Même modèle d'entrée que le sélecteur en ligne ; la grille est un contexte en lecture seule affichant le jour ciblé.
Hint_DateCalendar2            = Limité de aujourd'hui à aujourd'hui+1 an ; Entrée est bloquée hors de cette plage.
Hint_Time                     = Tapez quatre chiffres pour remplir HH:MM d'un coup (1430 → 14:30) ; flèches pour naviguer + Haut/Bas pour ajuster.
Hint_TimeTwelve               = Horloge 12 heures avec AM/PM (raccourcis a/p) et un champ de secondes. Le stockage interne reste en 24 heures.
Hint_Templated                = Chaque encapsuleur code en dur un masque ou une regex pour l'une des formes de saisie courantes. Échap saute à la suivante.
Hint_Timezone1                = Le fuseau local est surligné par défaut ; les fuseaux courants sont en haut avec un "*".
Hint_Timezone2                = Hérite de la recherche de la sélection paginée — Tab pour filtrer.

Prompt_PhoneNumber            = Numéro de téléphone :
Prompt_MacAddress             = Adresse MAC :
Prompt_Password               = Mot de passe :
Prompt_NewPassword            = Nouveau mot de passe :
Prompt_Retype                 = Retaper :
Prompt_PIN                    = NIP (longueur masquée) :
Prompt_IPv4                   = Adresse IPv4 :
Prompt_CIDR                   = Notation CIDR :
Prompt_Email                  = Adresse courriel :
Prompt_DeleteFile             = Supprimer le fichier ?
Prompt_PickColor              = Choisir une couleur :
Prompt_PickToppings           = Choisir des garnitures :
Prompt_PickDate               = Choisir une date :
Prompt_ScheduleFor            = Planifier pour :
Prompt_StartTime              = Heure de début :
Prompt_Alarm                  = Alarme :
Prompt_Phone                  = Téléphone :
Prompt_EmailShort             = Courriel :
Prompt_IPv4Short              = Adresse IPv4 :
Prompt_CIDRShort              = Notation CIDR :
Prompt_URL                    = URL :

Activity_Working              = Traitement
Activity_Querying             = Requête
Activity_Computing            = Calcul
Activity_StylePrefix          = Style : {0}

Result_YouSelected            = Vous avez sélectionné : {0}
Result_YouSelectedWithID      = Vous avez sélectionné : {0} (ID : {1})
Result_SelectionCancelled     = Sélection annulée.
Result_Cancelled              = Annulé.
Result_CancelledNull          = Annulé (retour $null).
Result_CancelledOrExhausted   = Annulé ou tentatives épuisées.
Result_ConfirmedNoSelections  = Confirmé sans sélection.
Result_SelectedItems          = {0} élément(s) sélectionné(s) :
Result_Captured               = Capturé : {0}
Result_CapturedPlainText      = Texte en clair capturé : {0}
Result_CapturedSecureString   = SecureString capturé de longueur {0}.
Result_ConfirmedSecureString  = SecureString confirmé de longueur {0}.
Result_Strength               = Force : {0} (score {1}/6, {2} classes de caractères)
Result_ConfirmedYes           = Confirmé : Oui
Result_ConfirmedNo            = Confirmé : Non
Result_CapturedNone           = Capturé : (aucun)
Result_AllStylesShown         = Tous les styles affichés.
Result_ScriptblockReturned    = Le scriptblock a retourné : {0} (attendu : 84)
Result_Done                   = Terminé.
Result_MenuCancelled          = Menu annulé.
Result_CapturedAction         = Action capturée : {0}
Result_SelectedTimezone       = Sélectionné : {0}
Result_TimezoneDisplay        = Affichage :  {0}
Result_LocalNow               = Heure locale :   {0}
Result_InSelected             = Dans le sélectionné : {0}
Result_SelectedDate           = Sélectionné : {0}
Result_SelectedTime           = Sélectionné : {0}

Common_PressAnyKey            = [ Appuyez sur une touche pour revenir au menu ]
Common_Thanks                 = Merci d'avoir essayé pwshTui.
Common_CouldNotLoadLocale     = Impossible de charger la locale "{0}".
Common_DemoBox                = Boîte de démo
Common_BodyCPU                = Processeur : 12 %
Common_BodyRAM                = RAM : 4,2 Go
Common_BodyDisk               = Disque : 80 % plein
'@
