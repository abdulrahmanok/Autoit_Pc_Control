#include <WinAPI.au3>
#include <WindowsConstants.au3>
#include <myfuncs.au3>
#include <Array.au3>
#RequireAdmin

; ==============================================================================
; Global Variables & Configuration
; ==============================================================================
Global $hWnd = 'Dungeon Defenders 2'
Global $Glory = 'LaunchUnrealUWindowsClient'

; Dynamic resolution detection
Global $gameWidth = 1920, $gameHeight = 1038
Global $baseWidth = 1920, $baseHeight = 1038
Global $scaleX = 1.0, $scaleY = 1.0

; Enhanced tracking variables
Global $debugMode = False
Global $lastTooltipMessage = ""
Global $sessionStartTime = @HOUR & ":" & @MIN & ":" & @SEC
Global $totalReadyCount = 0
Global $totalWaitCount = 0
Global $currentState = "Starting"
Global $successfulDetections = 0

; Cooldown variables
Global $lastDetectionTime = 0
Global $cooldownPeriod = 5000 ; 5 seconds in milliseconds
Global $inCooldown = False

; Game end detection variables
Global $gameEndCheckEnabled = True
Global $EnableBoostSkill = False
Global $GoTavern = False

; Pixel detection tolerance
Global $colorTolerance = 0x001010 ; Tolerance for color matching

; ==============================================================================
; Dynamic Resolution Functions
; ==============================================================================

Func InitializeGameWindow()
    ; Move window to top-left corner
    WinMove($hWnd, '', 0, 0, $gameWidth, $gameHeight)
    
    ; Get actual window dimensions
    Local $windowPos = WinGetPos($hWnd)
    If IsArray($windowPos) Then
        $gameWidth = $windowPos[2]
        $gameHeight = $windowPos[3]
        
        ; Calculate scaling factors
        $scaleX = $gameWidth / $baseWidth
        $scaleY = $gameHeight / $baseHeight
        
        LogToConsole("Game window detected: " & $gameWidth & "x" & $gameHeight)
        LogToConsole("Scaling factors: X=" & Round($scaleX, 3) & ", Y=" & Round($scaleY, 3))
    EndIf
EndFunc

Func ScaleCoordinates($x, $y)
    ; Scale coordinates based on current game resolution
    Local $scaledX = Round($x * $scaleX)
    Local $scaledY = Round($y * $scaleY)
    Return $scaledX, $scaledY
EndFunc

; ==============================================================================
; Enhanced Pixel Detection Functions
; ==============================================================================

Func BackGround_Pix($X, $Y, $Target_Color = 0x99604A, $IsTrue = False)
    Local $handle = WinGetHandle($hWnd)
    If $handle = 0 Then
        Return False
    EndIf

    ; Scale coordinates for current resolution
    Local $scaledX, $scaledY
    $scaledX = Round($X * $scaleX)
    $scaledY = Round($Y * $scaleY)

    ; Read pixel color with enhanced error handling
    Local $detectedColor = MemoryReadPixel($scaledX, $scaledY, $handle)
    If $detectedColor = 0 Then
        Return False
    EndIf

    Global $x2 = $scaledX
    Global $y2 = $scaledY

    ; Enhanced color matching with tolerance
    If ColorMatches($detectedColor, $Target_Color, $colorTolerance) Then
        _ScreenCoord_To_Client()
        Return True
    Else
        Return False
    EndIf
EndFunc

Func ColorMatches($color1, $color2, $tolerance)
    ; Extract RGB components
    Local $r1 = BitAND($color1, 0xFF0000) / 0x10000
    Local $g1 = BitAND($color1, 0x00FF00) / 0x100
    Local $b1 = BitAND($color1, 0x0000FF)
    
    Local $r2 = BitAND($color2, 0xFF0000) / 0x10000
    Local $g2 = BitAND($color2, 0x00FF00) / 0x100
    Local $b2 = BitAND($color2, 0x0000FF)
    
    ; Check if colors are within tolerance
    Local $diffR = Abs($r1 - $r2)
    Local $diffG = Abs($g1 - $g2)
    Local $diffB = Abs($b1 - $b2)
    
    Local $toleranceValue = BitAND($tolerance, 0xFF)
    
    Return ($diffR <= $toleranceValue) And ($diffG <= $toleranceValue) And ($diffB <= $toleranceValue)
EndFunc

Func MemoryReadPixel($X, $Y, $handle)
    ; Enhanced pixel reading with multiple attempts
    Local $maxAttempts = 3
    Local $attempt = 0
    
    While $attempt < $maxAttempts
        Local $hDC = _WinAPI_GetWindowDC($handle)
        If $hDC = 0 Then
            Sleep(10)
            $attempt += 1
            ContinueLoop
        EndIf

        Local $Color2 = DllCall("gdi32.dll", "int", "GetPixel", "int", $hDC, "int", $X, "int", $Y)
        _WinAPI_ReleaseDC($handle, $hDC)
        
        If @error Or $Color2[0] = -1 Then
            Sleep(10)
            $attempt += 1
            ContinueLoop
        EndIf
        
        Global $sColor = Hex($Color2[0], 6)
        Local $result = Hex("0x" & StringRight($sColor, 2) & StringMid($sColor, 3, 2) & StringLeft($sColor, 2))
        Return $result
    WEnd
    
    Return 0
EndFunc

; ==============================================================================
; Enhanced Game End Detection
; ==============================================================================

Func CheckGameEnd()
    CheckLoseGame()
    CheckAds()
    
    If Not $gameEndCheckEnabled Then
        Return False
    EndIf

    ; Multiple game end detection points with scaled coordinates
    Local $endPoints[4][3] = [
        [517, 313, 0xFFD800],
        [239, 297, 0xFBD400],
        [1651, 309, 0xFFD800],
        [1142, 238, 0xFFD800]
    ]
    
    For $i = 0 To UBound($endPoints) - 1
        Local $scaledX, $scaledY
        $scaledX = Round($endPoints[$i][0] * $scaleX)
        $scaledY = Round($endPoints[$i][1] * $scaleY)
        
        If BackGround_Pix($scaledX, $scaledY, $endPoints[$i][2]) Then
            HandleGameEnd($i)
            Return True
        EndIf
    Next
    
    UpdateTooltip(" مازلنا في الجيم", "")
    BoostSkill()
    Return False
EndFunc

Func HandleGameEnd($endPointIndex)
    $currentState = "Game Ended"
    UpdateTooltip("🎯 انتهى الجيم، إلى اللقاء", "GAMEEND")
    LogToConsole("Game end detected at point " & $endPointIndex & " - shutting down bot")
    
    ControlSend($hWnd, '', '', '{F6}')
    Sleep(1500)
    
    Local $Active_Wind = WinGetTitle('[Active]')
    WinActivate($hWnd)
    WinWaitActive($hWnd)
    
    If $GoTavern = True Then
        UpdateTooltip("🎯 إلى التافرن", "GAMEEND")
        ; Scale tavern button coordinates
        Local $tavernX, $tavernY
        $tavernX = Round(1395 * $scaleX)
        $tavernY = Round(918 * $scaleY)
        MouseClick('left', $tavernX, $tavernY, 1)
        WinActivate($Active_Wind)
    EndIf
    
    Sleep(3000)
    ToolTip("")
    
    ; Start new game if needed
    If $endPointIndex = 3 And $GoTavern = True Then
        UpdateTooltip(" Start New Game", "")
        StartNewGame()
    EndIf
EndFunc

; ==============================================================================
; Enhanced Friend Status Detection
; ==============================================================================

Func FriendStatus()
    Local $friendReadyDetected = False

    ; Multiple detection points for friend ready status
    Local $readyPoints[4][3] = [
        [101, 261, 0x00D41E],
        [94, 259, 0x00C81A],
        [Round(101 * $scaleX), Round(261 * $scaleY), 0x00D41E],
        [Round(94 * $scaleX), Round(259 * $scaleY), 0x00C81A]
    ]
    
    For $i = 0 To UBound($readyPoints) - 1
        If BackGround_Pix($readyPoints[$i][0], $readyPoints[$i][1], $readyPoints[$i][2]) Then
            $friendReadyDetected = True
            $successfulDetections += 1
            $Friend_Ready = True
            $currentState = "Friend Ready"
            
            UpdateTooltip("🎉 FRIEND IS READY! Starting combat sequence...", "READY")
            ExecuteCombatSequence()
            StartCooldown()
            UpdateTooltip("🕐 Starting 15-second cooldown period...", "COOLDOWN")
            Sleep(3000)
            Return
        EndIf
    Next
    
    If Not $friendReadyDetected Then
        $currentState = "Waiting"
        $totalWaitCount += 1
        UpdateTooltip("⏳ Waiting for friend to ready up...", "WAITING")
        Sleep(2000)
    EndIf

    ; Handle manual trigger
    If $KeyPressed Then
        $KeyPressed = False
        UpdateTooltip("🔧 Manual override activated", "MANUAL")
        ExecuteCombatSequence()
        StartCooldown()
        UpdateTooltip("🕐 Starting 15-second cooldown after manual trigger...", "COOLDOWN")
    EndIf
EndFunc

; ==============================================================================
; Enhanced Combat Sequence
; ==============================================================================

Func ExecuteCombatSequence()
    UpdateTooltip("⚡ Executing combat sequence...", "ACTION")
    
    ; Enhanced key sending with verification
    Local $keys[3] = ['{F11}', '{F6}', '{F11}']
    Local $delays[3] = [1000, 1500, 500]
    
    For $i = 0 To UBound($keys) - 1
        Local $result = ControlSend($hWnd, '', '', $keys[$i])
        If $result = 0 Then
            LogToConsole("Warning: Failed to send key " & $keys[$i])
        EndIf
        Sleep($delays[$i])
    Next
    
    UpdateTooltip("✅ Combat sequence completed!", "SUCCESS")
EndFunc

; ==============================================================================
; Enhanced Boost Skill Function
; ==============================================================================

Func BoostSkill()
    If $EnableBoostSkill = True Then
        UpdateTooltip("تفعيل البوست", "")
        
        Local $hWnd2 = WinGetHandle($hWnd)
        If $hWnd2 = 0 Then
            LogToConsole("Error: Cannot get game window handle")
            Return
        EndIf
        
        Local $iSendResult = ControlSend($hWnd2, "", "", "3")
        If $iSendResult = 0 Then
            ConsoleWrite("❌ نتيجة إرسال المفتاح '3': فشل" & @CRLF)
        EndIf
        Sleep(1000)

        $iSendResult = ControlSend($hWnd2, "", "", "9")
        Opt("MouseCoordMode", 0)
        Sleep(4000)
    EndIf
EndFunc

; ==============================================================================
; Enhanced Initialization
; ==============================================================================

UpdateTooltip("🚀 Dungeon Defenders 2 Friend Monitor Started", "SUCCESS")
UpdateTooltip("🔧 Checking game window...", "INFO")

; Verify window exists and initialize
If Not WinExists($hWnd) Then
    UpdateTooltip("❌ Game window not found", "ERROR")
    MsgBox(16, "Error", "Game window '" & $hWnd & "' not found!" & @CRLF & "Please start the game first.")
    Exit
Else
    InitializeGameWindow()
    UpdateTooltip("✅ Game window found and ready", "SUCCESS")
EndIf

; ==============================================================================
; Main Loop with Enhanced Error Handling
; ==============================================================================

UpdateTooltip("🔄 Starting main monitoring loop...", "INFO")

While 1
    ; Enhanced error handling
    If @error Then
        LogToConsole("Error in main loop: " & @error)
        Sleep(1000)
        ContinueLoop
    EndIf
    
    ; Always check for game end first (highest priority)
    CheckGameEnd()

    If Not $Paused Then
        Sleep(1000)
        MainLoop()
    Else
        Sleep(100)
    EndIf
WEnd

; ==============================================================================
; Additional Helper Functions
; ==============================================================================

Func CheckLoseGame()
    Local $scaledX, $scaledY
    $scaledX = Round(1018 * $scaleX)
    $scaledY = Round(818 * $scaleY)
    
    If BackGround_Pix($scaledX, $scaledY, 0xD7D7D7) Then
        $currentState = "Game Ended"
        UpdateTooltip("جيم خاسر", "LoseGame")
        LogToConsole("Game Lose detected- Press N")
        ControlSend($hWnd, '', '', '{n}')
    EndIf
EndFunc

Func CheckAds()
    Local $adPoints[2][3] = [
        [964, 767, 0x1F1826],
        [771, 401, 0xC642FF]
    ]
    
    For $i = 0 To UBound($adPoints) - 1
        Local $scaledX, $scaledY
        $scaledX = Round($adPoints[$i][0] * $scaleX)
        $scaledY = Round($adPoints[$i][1] * $scaleY)
        
        If BackGround_Pix($scaledX, $scaledY, $adPoints[$i][2]) Then
            $currentState = "Ad Detected"
            UpdateTooltip("Ad Detected ", "Ad Detected")
            LogToConsole("Ad Detected- Press enter")
            ControlSend($hWnd, '', '', '{enter}')
            Return
        EndIf
    Next
EndFunc

Func StartNewGame()
    Run('"C:\Users\Administrator\AppData\Local\Programs\Python\Python39\python.exe" "E:\#programs\haks\Autoit\Doungen Defenders Bot\Background\Python\Main.py"')
EndFunc

; ==============================================================================
; Hotkey Configuration
; ==============================================================================
HotKeySet('{END}', '_Exit')
HotKeySet("{F8}", "ManualTrigger")
HotKeySet("{F5}", "TogglePause")
HotKeySet("{F9}", "ToggleDebugMode")
HotKeySet("{F10}", "ShowStats")

; ==============================================================================
; Enhanced Functions (keeping original functionality)
; ==============================================================================

Func ManualTrigger()
    $KeyPressed = True
    UpdateTooltip("🔧 Manual trigger activated", "MANUAL")
    LogToConsole("Manual trigger pressed by user")
EndFunc

Func TogglePause()
    $Paused = Not $Paused
    If $Paused Then
        UpdateTooltip("⏸️ Bot paused", "PAUSE")
    Else
        UpdateTooltip("▶️ Bot resumed", "RESUME")
    EndIf
EndFunc

Func ToggleDebugMode()
    $debugMode = Not $debugMode
    If $debugMode Then
        UpdateTooltip("🔍 Debug Mode: ON", "DEBUG")
    Else
        ToolTip("")
        UpdateTooltip("🔍 Debug Mode: OFF", "DEBUG")
    EndIf
EndFunc

Func ShowStats()
    Local $statsMsg = "📊 SESSION STATISTICS" & @CRLF & _
                     "Started: " & $sessionStartTime & @CRLF & _
                     "Ready Detections: " & $successfulDetections & @CRLF & _
                     "Current State: " & $currentState & @CRLF & _
                     "Game Resolution: " & $gameWidth & "x" & $gameHeight & @CRLF & _
                     "Scaling: X=" & Round($scaleX, 3) & ", Y=" & Round($scaleY, 3)

    MsgBox(64, "Bot Statistics", $statsMsg)
EndFunc

Func _Exit()
    UpdateTooltip("🚪 Shutting down bot...", "EXIT")
    LogToConsole("Bot session ended. Total detections: " & $successfulDetections)
    ToolTip("")
    Exit
EndFunc

; ==============================================================================
; Enhanced Tooltip System
; ==============================================================================

Func UpdateTooltip($message, $type = "INFO")
    Local $timestamp = "[" & @HOUR & ":" & @MIN & ":" & @SEC & "]"
    Local $icon = GetIcon($type)

    If $debugMode Then
        Local $cooldownInfo = ""
        If $inCooldown Then
            Local $remainingTime = Round(($lastDetectionTime + $cooldownPeriod - TimerInit()) / 1000, 1)
            If $remainingTime > 0 Then
                $cooldownInfo = @CRLF & "🕐 Cooldown: " & $remainingTime & "s"
            EndIf
        EndIf

        Local $tooltipText = $icon & " " & $timestamp & @CRLF & _
                           "📍 " & $message & @CRLF & _
                           "━━━━━━━━━━━━━━━━━━━━━━━━" & @CRLF & _
                           "🎮 Game: " & $hWnd & @CRLF & _
                           "📊 State: " & $currentState & @CRLF & _
                           "✅ Detections: " & $successfulDetections & @CRLF & _
                           "⏰ Started: " & $sessionStartTime & @CRLF & _
                           "🖥️ Resolution: " & $gameWidth & "x" & $gameHeight & $cooldownInfo

        ToolTip($tooltipText, 0, 0)
    Else
        ToolTip($icon & " " & $message, 0, 0)
    EndIf

    $lastTooltipMessage = $message
    LogToConsole($message)
EndFunc

Func GetIcon($type)
    Switch $type
        Case "READY"
            Return "🎉"
        Case "WAITING"
            Return "⏳"
        Case "ERROR"
            Return "❌"
        Case "SUCCESS"
            Return "✅"
        Case "MANUAL"
            Return "🔧"
        Case "PAUSE"
            Return "⏸️"
        Case "RESUME"
            Return "▶️"
        Case "DEBUG"
            Return "🔍"
        Case "EXIT"
            Return "🚪"
        Case "ACTION"
            Return "⚡"
        Case "COOLDOWN"
            Return "🕐"
        Case "GAMEEND"
            Return "🎯"
        Case Else
            Return "ℹ️"
    EndSwitch
EndFunc

Func LogToConsole($message)
    ConsoleWrite("[" & @HOUR & ":" & @MIN & ":" & @SEC & "] " & $message & @CRLF)
EndFunc

; ==============================================================================
; Cooldown Management Functions
; ==============================================================================

Func StartCooldown()
    $lastDetectionTime = TimerInit()
    $inCooldown = True
    LogToConsole("Cooldown started - 5 second waiting period activated")
EndFunc

Func CheckCooldown()
    If Not $inCooldown Then
        Return True
    EndIf

    Local $currentTime = TimerInit()
    Local $elapsedTime = TimerDiff($lastDetectionTime)

    If $elapsedTime >= $cooldownPeriod Then
        $inCooldown = False
        LogToConsole("Cooldown period ended - resuming detection")
        Return True
    Else
        Local $remainingTime = Round(($cooldownPeriod - $elapsedTime) / 1000, 1)
        UpdateTooltip("🕐 Cooldown active - " & $remainingTime & " seconds remaining", "COOLDOWN")
        Return False
    EndIf
EndFunc

; ==============================================================================
; Main Loop Function
; ==============================================================================

Func MainLoop()
    ; Check cooldown first
    If Not CheckCooldown() Then
        Sleep(1000) ; Wait 1 second during cooldown
        Return
    EndIf

    $currentState = "Monitoring"
    UpdateTooltip("🔍 Checking friend status...", "INFO")
    FriendStatus()
EndFunc

; ==============================================================================
; Coordinate Conversion Functions
; ==============================================================================

Func _ScreenCoord_To_Client()
    Local $tPoint = DllStructCreate("int X;int Y")
    DllStructSetData($tPoint, "X", $x2)
    DllStructSetData($tPoint, "Y", $y2)

    If _WinAPI_ScreenToClient($hWnd, $tPoint) Then
        Global $Client_X = DllStructGetData($tPoint, "X")
        Global $Client_Y = DllStructGetData($tPoint, "Y")
        Return True
    Else
        Return False
    EndIf
EndFunc