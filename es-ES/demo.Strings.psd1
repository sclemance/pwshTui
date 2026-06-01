# Cadenas localizadas para la demo de pwshTui (es-ES).
# Cubre español (España) y variantes latinoamericanas via la cadena de culturas.
ConvertFrom-StringData @'
Menu_Group_SelectionMenus     = Selección y menús
Menu_Group_InputPrompts       = Entradas
Menu_Group_DateTime           = Fecha y hora
Menu_Group_AsyncLayout        = Asíncrono y diseño
Menu_ToggleRenderMode         = Cambiar modo de renderizado (actual: {0})
Menu_ChangeLanguage           = Cambiar idioma (actual: {0})
Menu_ExitDemo                 = Salir de la demo

Menu_Paginated                = Selección paginada (con búsqueda)
Menu_PaginatedJump            = Selección paginada (-InitialIndex salto a #25)
Menu_MultiSelect              = Multi-selección paginada (Espacio alterna)
Menu_Nested                   = Menú anidado
Menu_NestedDeep               = Menú anidado (-InitialPath enlace directo)
Menu_NestedBordered           = Menú anidado (con borde + AltScreen)

Menu_MaskedInput              = Entrada con máscara (teléfono, MAC)
Menu_PasswordInput            = Entrada de contraseña (SecureString, confirmar, PIN)
Menu_ValidatedInput           = Entrada validada (IPv4, CIDR, correo)
Menu_Confirmation             = Confirmación Sí/No
Menu_ChoiceSelector           = Selector de opciones (simple + múltiple)
Menu_NumberInput              = Entrada numérica (unidades, separadores, flechas aceleradas)
Menu_NumberWrappers           = Envoltorios numéricos (Porcentaje, Temperatura, Moneda)
Menu_Measurement              = Medida (entrada multi-unidad vía units/*.psd1)
Menu_TemplatedWrappers        = Envoltorios con plantilla (Teléfono, Correo, IPv4, CIDR, URL)

Menu_DateInline               = Read-Date (campos en línea)
Menu_DateCalendar             = Read-Date -Calendar (con cuadrícula mensual)
Menu_Time24                   = Read-Time (24 horas)
Menu_Time12                   = Read-Time -TwelveHour -ShowSeconds
Menu_Timezone                 = Read-Timezone (con lista preferida)

Menu_Spinner                  = Show-Spinner (Braille por defecto)
Menu_SpinnerTimer             = Show-Spinner con -ShowTimer
Menu_SpinnerStyles            = Show-Spinner — los seis estilos
Menu_SpinnerClosure           = Show-Spinner — captura de cierre
Menu_UIBox                    = Write-TuiBox (independiente)

Title_Demo                    = Demo pwshTui [{0} | {1}]
Title_SelectSystemObject      = Seleccionar un objeto del sistema
Title_JumpedToItem25          = Saltado al elemento 25
Title_PickMultiple            = Elegir varios objetos
Title_AdminPortal             = Portal de administración
Title_BorderedMenu            = Menú con borde
Title_SystemStatus            = Estado del sistema

Header_Paginated              = Get-PaginatedSelection (con búsqueda)
Header_PaginatedJump          = Get-PaginatedSelection (-InitialIndex salta a un elemento específico)
Header_MultiSelect            = Get-PaginatedSelection -MultiSelect
Header_NestedMenu             = Invoke-NestedMenu
Header_NestedMenuDeep         = Invoke-NestedMenu -InitialPath (enlace directo a Power Saver)
Header_NestedMenuBordered     = Invoke-NestedMenu (con borde, posicionado, AltScreen)
Header_MaskedInput            = Read-MaskedInput
Header_Password               = Read-Password
Header_ValidatedInput         = Read-ValidatedInput
Header_Confirmation           = Read-Confirmation
Header_Choice                 = Read-Choice
Header_Number                 = Read-Number (unidades, separadores, flechas aceleradas)
Header_NumberWrappers         = Read-Percentage / Read-Temperature / Read-Currency
Header_Measurement            = Read-Measurement (entrada multi-unidad basada en archivos de datos)
Header_Spinner                = Show-Spinner (Braille por defecto)
Header_SpinnerTimer           = Show-Spinner -ShowTimer
Header_SpinnerStyles          = Show-Spinner — los seis estilos, 1,5 s cada uno
Header_SpinnerClosure         = Show-Spinner — los cierres funcionan
Header_UIBox                  = Write-TuiBox (independiente)
Header_Date                   = Read-Date (en línea)
Header_DateCalendar           = Read-Date -Calendar (con cuadrícula mensual)
Header_Time                   = Read-Time (24 horas)
Header_TimeTwelve             = Read-Time -TwelveHour -ShowSeconds
Header_TemplatedWrappers      = Envoltorios de entrada con plantilla (Teléfono, Correo, IPv4, CIDR, URL)
Header_Timezone               = Read-Timezone

Hint_Paginated                = Escriba para búsqueda difusa; flechas para navegar; Entrar para elegir; Esc para cancelar.
Hint_MultiSelect              = Espacio alterna (modo selección); Tab cambia a modo búsqueda; escriba para filtrar; las flechas vuelven a modo selección con la primera fila resaltada; Entrar confirma; Esc cancela.
Hint_NestedBordered           = Dibujando un menú con -Border -MinWidth 40 -X 5 -Y 15 -AltScreen...
Hint_Password1                = Escriba para entrar; Retroceso borra; Entrar envía; Esc cancela.
Hint_Password2                = El indicador de fuerza aparece en vivo a la derecha de la entrada con máscara.
Hint_Confirmation             = S/N para respuesta instantánea; Izq./Der./Tab para mover; Entrar para confirmar; Esc para cancelar.
Hint_Choice                   = Flechas o dígito 1-N para mover; Entrar para confirmar; Esc para cancelar.
Hint_ChoiceMulti              = Multi-selección: Espacio alterna, dígitos mueven el foco, Entrar devuelve el array.
Hint_Number1                  = Arriba/Abajo para ajustar, mantener para acelerar (la curva se adapta al rango y se ralentiza cerca de los límites). RePág/AvPág saltan 10*Step.
Hint_Number2                  = Escriba dígitos para editar directamente; Retroceso/Supr modifican el búfer; Entrar confirma si está en rango; Esc cancela.
Hint_NumberWrappers           = Valores por defecto según la configuración regional: unidad de temperatura derivada de la región, símbolo monetario del código ISO. Use -Unit / -Currency para anular.
Hint_Measurement              = Escriba una medida como "5'11\"", "1m 80cm" o "100cm" — el analizador se basa en units/length.psd1 (sin lista fija de unidades). El decorador muestra el valor en la unidad preferida de la región.
Hint_Spinner                  = Ejecutando una pausa de 2 segundos...
Hint_SpinnerTimer             = Ejecutando una pausa de 3,5 segundos con contador en vivo...
Hint_SpinnerStylesAscii       = El modo ASCII está activado — -Ascii fuerza Style=Ascii independientemente de -Style, así que los cuatro se renderizan como el glifo Ascii. Desactive ASCII para ver cada estilo nombrado.
Hint_SpinnerClosure           = El ámbito llamante contiene $magicNumber = {0}. El scriptblock lo usará sin -ArgumentList.
Hint_Date                     = ← → mueven campos, ↑ ↓ ajustan el valor enfocado, escriba dígitos para llenar el campo, Tab alterna modos.
Hint_DateCalendar1            = Mismo modelo de entrada que el selector en línea; la cuadrícula es contexto de solo lectura mostrando el día enfocado.
Hint_DateCalendar2            = Limitado a hoy..hoy+1 año; Entrar está bloqueado fuera de ese rango.
Hint_Time                     = Escriba cuatro dígitos para llenar HH:MM de una vez (1430 → 14:30); flechas para navegar entre campos + Arriba/Abajo para ajustar.
Hint_TimeTwelve               = Reloj de 12 horas con AM/PM (atajos a/p) y un campo de segundos. El almacenamiento interno permanece en 24 horas.
Hint_Templated                = Cada envoltorio codifica una máscara o regex para una de las formas comunes de entrada. Esc salta al siguiente.
Hint_Timezone1                = Zona local resaltada por defecto; zonas comunes ancladas arriba con "*".
Hint_Timezone2                = Hereda la búsqueda de selección paginada — Tab para filtrar.

Prompt_PhoneNumber            = Número de teléfono:
Prompt_MacAddress             = Dirección MAC:
Prompt_Password               = Contraseña:
Prompt_NewPassword            = Nueva contraseña:
Prompt_Retype                 = Reescribir:
Prompt_PIN                    = PIN (longitud oculta):
Prompt_IPv4                   = Dirección IPv4:
Prompt_CIDR                   = Notación CIDR:
Prompt_Email                  = Dirección de correo:
Prompt_DeleteFile             = ¿Eliminar el archivo?
Prompt_PickColor              = Elige un color:
Prompt_PickToppings           = Elige ingredientes:
Prompt_PickDate               = Elige una fecha:
Prompt_ScheduleFor            = Programar para:
Prompt_StartTime              = Hora de inicio:
Prompt_Alarm                  = Alarma:
Prompt_Phone                  = Teléfono:
Prompt_EmailShort             = Correo:
Prompt_IPv4Short              = Dirección IPv4:
Prompt_CIDRShort              = Notación CIDR:
Prompt_URL                    = URL:
Prompt_Port                   = Puerto:
Prompt_Coverage               = Cobertura:
Prompt_Temperature            = Temperatura:
Prompt_Budget                 = Presupuesto:
Prompt_Amount                 = Importe:
Prompt_BodyTemp               = Temperatura corporal:
Prompt_Progress               = Progreso:
Prompt_Distance               = Distancia:
Prompt_Ambient                = Temperatura ambiente:

Activity_Working              = Trabajando
Activity_Querying             = Consultando
Activity_Computing            = Calculando
Activity_StylePrefix          = Estilo: {0}

Result_YouSelected            = Seleccionado: {0}
Result_YouSelectedWithID      = Seleccionado: {0} (ID: {1})
Result_SelectionCancelled     = Selección cancelada.
Result_Cancelled              = Cancelado.
Result_CancelledNull          = Cancelado (retorno $null).
Result_CancelledOrExhausted   = Cancelado o intentos agotados.
Result_ConfirmedNoSelections  = Confirmado sin selecciones.
Result_SelectedItems          = {0} elemento(s) seleccionado(s):
Result_Captured               = Capturado: {0}
Result_CapturedPlainText      = Texto plano capturado: {0}
Result_CapturedSecureString   = SecureString capturado de longitud {0}.
Result_ConfirmedSecureString  = SecureString confirmado de longitud {0}.
Result_Strength               = Fuerza: {0} (puntuación {1}/6, {2} clases de caracteres)
Result_ConfirmedYes           = Confirmado: Sí
Result_ConfirmedNo            = Confirmado: No
Result_CapturedNone           = Capturado: (ninguno)
Result_AllStylesShown         = Todos los estilos mostrados.
Result_ScriptblockReturned    = El scriptblock devolvió: {0} (esperado: 84)
Result_Done                   = Hecho.
Result_MenuCancelled          = Menú cancelado.
Result_CapturedAction         = Acción capturada: {0}
Result_SelectedTimezone       = Seleccionado: {0}
Result_TimezoneDisplay        = Mostrar:  {0}
Result_LocalNow               = Local ahora:   {0}
Result_InSelected             = En seleccionado: {0}
Result_SelectedDate           = Seleccionado: {0}
Result_SelectedTime           = Seleccionado: {0}

Common_PressAnyKey            = [ Pulse cualquier tecla para volver al menú ]
Common_Thanks                 = Gracias por probar pwshTui.
Common_CouldNotLoadLocale     = No se pudo cargar el idioma "{0}".
Common_DemoBox                = Caja de demo
Common_BodyCPU                = CPU: 12 %
Common_BodyRAM                = RAM: 4,2 GB
Common_BodyDisk               = Disco: 80 % lleno
'@
