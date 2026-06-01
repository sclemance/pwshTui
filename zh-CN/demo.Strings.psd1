# pwshTui 演示的本地化字符串 (zh-CN, 简体中文)。
# 通过文化链同时覆盖中国大陆和新加坡 (zh-SG)。
ConvertFrom-StringData @'
Menu_Group_SelectionMenus     = 选择与菜单
Menu_Group_InputPrompts       = 输入
Menu_Group_DateTime           = 日期与时间
Menu_Group_AsyncLayout        = 异步与布局
Menu_ToggleRenderMode         = 切换渲染模式 (当前: {0})
Menu_ChangeLanguage           = 切换语言 (当前: {0})
Menu_ExitDemo                 = 退出演示

Menu_Paginated                = 分页选择 (可搜索)
Menu_PaginatedJump            = 分页选择 (-InitialIndex 跳到 #25)
Menu_MultiSelect              = 分页多选 (空格切换)
Menu_Nested                   = 嵌套菜单
Menu_NestedDeep               = 嵌套菜单 (-InitialPath 直链)
Menu_NestedBordered           = 嵌套菜单 (带边框 + AltScreen)

Menu_MaskedInput              = 掩码输入 (电话、MAC)
Menu_PasswordInput            = 密码输入 (SecureString、确认、PIN)
Menu_ValidatedInput           = 验证输入 (IPv4、CIDR、邮箱)
Menu_Confirmation             = 是/否确认
Menu_ChoiceSelector           = 选项选择器 (单选 + 多选)
Menu_NumberInput              = 数值输入 (单位、千位分隔符、加速方向键)
Menu_NumberWrappers           = 数值封装 (百分比、温度、货币)
Menu_Measurement              = 测量 (通过 units/*.psd1 的多单位输入)
Menu_TemplatedWrappers        = 模板封装 (电话、邮箱、IPv4、CIDR、URL)

Menu_DateInline               = Read-Date (内联字段)
Menu_DateCalendar             = Read-Date -Calendar (带月历)
Menu_Time24                   = Read-Time (24 小时)
Menu_Time12                   = Read-Time -TwelveHour -ShowSeconds
Menu_Timezone                 = Read-Timezone (带优先列表)

Menu_Spinner                  = Show-Spinner (默认 Braille)
Menu_SpinnerTimer             = Show-Spinner 带 -ShowTimer
Menu_SpinnerStyles            = Show-Spinner — 全部六种样式
Menu_SpinnerClosure           = Show-Spinner — 闭包捕获
Menu_UIBox                    = Write-TuiBox (独立)

Title_Demo                    = pwshTui 演示 [{0} | {1}]
Title_SelectSystemObject      = 选择系统对象
Title_JumpedToItem25          = 跳转到项 25
Title_PickMultiple            = 选择多个对象
Title_AdminPortal             = 管理门户
Title_BorderedMenu            = 带边框菜单
Title_SystemStatus            = 系统状态

Header_Paginated              = Get-PaginatedSelection (可搜索)
Header_PaginatedJump          = Get-PaginatedSelection (-InitialIndex 跳到指定项)
Header_MultiSelect            = Get-PaginatedSelection -MultiSelect
Header_NestedMenu             = Invoke-NestedMenu
Header_NestedMenuDeep         = Invoke-NestedMenu -InitialPath (直链到 Power Saver)
Header_NestedMenuBordered     = Invoke-NestedMenu (带边框、定位、AltScreen)
Header_MaskedInput            = Read-MaskedInput
Header_Password               = Read-Password
Header_ValidatedInput         = Read-ValidatedInput
Header_Confirmation           = Read-Confirmation
Header_Choice                 = Read-Choice
Header_Number                 = Read-Number (单位、千位分隔符、加速方向键)
Header_NumberWrappers         = Read-Percentage / Read-Temperature / Read-Currency
Header_Measurement            = Read-Measurement (数据文件驱动的多单位输入)
Header_Spinner                = Show-Spinner (默认 Braille)
Header_SpinnerTimer           = Show-Spinner -ShowTimer
Header_SpinnerStyles          = Show-Spinner — 全部六种样式、每种 1.5 秒
Header_SpinnerClosure         = Show-Spinner — 闭包能直接用
Header_UIBox                  = Write-TuiBox (独立)
Header_Date                   = Read-Date (内联)
Header_DateCalendar           = Read-Date -Calendar (带月历)
Header_Time                   = Read-Time (24 小时)
Header_TimeTwelve             = Read-Time -TwelveHour -ShowSeconds
Header_TemplatedWrappers      = 输入模板封装 (电话、邮箱、IPv4、CIDR、URL)
Header_Timezone               = Read-Timezone

Hint_Paginated                = 输入即模糊搜索；方向键导航；Enter 选择；Esc 取消。
Hint_MultiSelect              = 空格切换 (选择模式)；Tab 切到搜索模式；输入过滤；方向键回到选择模式并高亮首行；Enter 确认；Esc 取消。
Hint_NestedBordered           = 用 -Border -MinWidth 40 -X 5 -Y 15 -AltScreen 绘制菜单...
Hint_Password1                = 输入文字；退格删除；Enter 提交；Esc 取消。
Hint_Password2                = 强度指示在掩码输入右侧实时显示。
Hint_Confirmation             = Y/N 即时回答；左/右/Tab 移动高亮；Enter 确认；Esc 取消。
Hint_Choice                   = 方向键或数字 1-N 移动；Enter 确认；Esc 取消。
Hint_ChoiceMulti              = 多选: 空格切换、数字移动焦点、Enter 返回数组。
Hint_Number1                  = 上下键增减、按住可加速 (曲线随范围放大、接近上下限时减速)。PgUp/PgDn 跳 10*Step。
Hint_Number2                  = 直接输入数字编辑；Backspace/Delete 修改缓冲；在范围内时 Enter 确认；Esc 取消。
Hint_NumberWrappers           = 本地化默认: 温度单位按区域设置、货币符号按 ISO 代码。用 -Unit / -Currency 覆盖。
Hint_Measurement              = 输入测量值,例如 "5'11\""、"1m 80cm" 或 "100cm" — 解析器由 units/length.psd1 驱动 (无硬编码单位列表)。装饰器以区域偏好单位显示数值。
Hint_Spinner                  = 正在执行 2 秒休眠...
Hint_SpinnerTimer             = 正在执行 3.5 秒休眠 (带实时耗时显示)...
Hint_SpinnerStylesAscii       = ASCII 模式已启用 — -Ascii 强制 Style=Ascii (不论 -Style)，所以四种都以下面的 Ascii 字符渲染。关闭 ASCII 以查看每种样式。
Hint_SpinnerClosure           = 调用方作用域有 $magicNumber = {0}。脚本块无需 -ArgumentList 即可使用。
Hint_Date                     = ← → 字段切换，↑ ↓ 调整聚焦值，数字输入填入字段，Tab 切换模式。
Hint_DateCalendar1            = 与内联选择器相同的输入模型；网格为只读上下文，显示聚焦日。
Hint_DateCalendar2            = 限制为今天..今天+1 年，范围外时 Enter 被阻止。
Hint_Time                     = 输入四位数字一次填入 HH:MM (1430 → 14:30)；方向键切换字段 + 上下键调整。
Hint_TimeTwelve               = 12 小时制带 AM/PM (a/p 快捷键) 和秒字段。内部存储始终为 24 小时。
Hint_Templated                = 每个封装为常见输入形硬编码了一个掩码或正则。Esc 跳到下一个。
Hint_Timezone1                = 默认高亮本地时区；常用时区以 "*" 前缀置顶。
Hint_Timezone2                = 继承分页选择的搜索 — Tab 过滤。

Prompt_PhoneNumber            = 电话号码:
Prompt_MacAddress             = MAC 地址:
Prompt_Password               = 密码:
Prompt_NewPassword            = 新密码:
Prompt_Retype                 = 重新输入:
Prompt_PIN                    = PIN (长度隐藏):
Prompt_IPv4                   = IPv4 地址:
Prompt_CIDR                   = CIDR 表示法:
Prompt_Email                  = 邮箱地址:
Prompt_DeleteFile             = 删除该文件?
Prompt_PickColor              = 选择颜色:
Prompt_PickToppings           = 选择配料:
Prompt_PickDate               = 选择日期:
Prompt_ScheduleFor            = 计划日期:
Prompt_StartTime              = 开始时间:
Prompt_Alarm                  = 闹钟:
Prompt_Phone                  = 电话:
Prompt_EmailShort             = 邮箱:
Prompt_IPv4Short              = IPv4 地址:
Prompt_CIDRShort              = CIDR 表示法:
Prompt_URL                    = URL:
Prompt_Port                   = 端口:
Prompt_Coverage               = 覆盖率:
Prompt_Temperature            = 温度:
Prompt_Budget                 = 预算:
Prompt_Amount                 = 金额:
Prompt_BodyTemp               = 体温:
Prompt_Progress               = 进度:
Prompt_Distance               = 距离:
Prompt_Ambient                = 环境温度:

Activity_Working              = 处理中
Activity_Querying             = 查询中
Activity_Computing            = 计算中
Activity_StylePrefix          = 样式: {0}

Result_YouSelected            = 已选: {0}
Result_YouSelectedWithID      = 已选: {0} (ID: {1})
Result_SelectionCancelled     = 已取消选择。
Result_Cancelled              = 已取消。
Result_CancelledNull          = 已取消 (返回 $null)。
Result_CancelledOrExhausted   = 已取消或重试次数用尽。
Result_ConfirmedNoSelections  = 已确认 (无选项)。
Result_SelectedItems          = 已选 {0} 项:
Result_Captured               = 已捕获: {0}
Result_CapturedPlainText      = 已捕获明文: {0}
Result_CapturedSecureString   = 已捕获 SecureString (长度 {0})。
Result_ConfirmedSecureString  = 已确认 SecureString (长度 {0})。
Result_Strength               = 强度: {0} (得分 {1}/6、{2} 字符类)
Result_ConfirmedYes           = 已确认: 是
Result_ConfirmedNo            = 已确认: 否
Result_CapturedNone           = 已捕获: (无)
Result_AllStylesShown         = 全部样式已展示。
Result_ScriptblockReturned    = 脚本块返回: {0} (预期: 84)
Result_Done                   = 完成。
Result_MenuCancelled          = 菜单已取消。
Result_CapturedAction         = 已捕获操作: {0}
Result_SelectedTimezone       = 已选: {0}
Result_TimezoneDisplay        = 显示:  {0}
Result_LocalNow               = 本地当前:   {0}
Result_InSelected             = 所选时区:   {0}
Result_SelectedDate           = 已选: {0}
Result_SelectedTime           = 已选: {0}

Common_PressAnyKey            = [ 按任意键返回菜单 ]
Common_Thanks                 = 感谢使用 pwshTui。
Common_CouldNotLoadLocale     = 无法加载语言 "{0}"。
Common_DemoBox                = 演示框
Common_BodyCPU                = CPU: 12%
Common_BodyRAM                = RAM: 4.2GB
Common_BodyDisk               = 磁盘: 已用 80%
'@
