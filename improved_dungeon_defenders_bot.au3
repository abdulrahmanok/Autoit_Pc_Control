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

; Original variables from the original code
Global $Client_X, $Client_Y, $Paused = False
Global $AlreadyDropped = False, $Friend2 = False, $Friend3 = False, $Friend_Ready = False
Global $KeyPressed = False
Global $x2, $y2, $sColor

; Cooldown variables
Global $lastDetectionTime = 0
Global $cooldownPeriod = 5000 ; 5 seconds in milliseconds
Global $inCooldown = False

; Game end detection variables
Global $gameEndCheckEnabled = True
Global $EnableBoostSkill = False
Global $GoTavern = False

; Pixel detection tolerance
Global $colorTolerance = 0x000505 ; Reduced tolerance for more accurate detection

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
        If $debugMode Then
            LogToConsole("Error: Cannot get window handle")
        EndIf
        Return False
    EndIf

    ; Scale coordinates for current resolution
    Local $scaledX, $scaledY
    $scaledX = Round($X * $scaleX)
    $scaledY = Round($Y * $scaleY)

    ; Read pixel color with enhanced error handling
    Local $detectedColor = MemoryReadPixel($scaledX, $scaledY, $handle)
    If $detectedColor = 0 Then
        ; Try alternative method
        $detectedColor = AlternativePixelRead($scaledX, $scaledY, $handle)
        If $detectedColor = 0 Then
            If $debugMode Then
                LogToConsole("Error: Failed to read pixel at " & $scaledX & "," & $scaledY & " with both methods")
            EndIf
            Return False
        EndIf
    EndIf

    Global $x2 = $scaledX
    Global $y2 = $scaledY

    ; Debug information
    If $debugMode Then
        LogToConsole("Pixel at " & $scaledX & "," & $scaledY & " - Detected: " & $detectedColor & " Target: " & $Target_Color)
    EndIf

    ; Enhanced color matching with tolerance
    If ColorMatches($detectedColor, $Target_Color, $colorTolerance) Then
        If $debugMode Then
            LogToConsole("✅ Color match found at " & $scaledX & "," & $scaledY)
        EndIf
        _ScreenCoord_To_Client()
        Return True
    Else
        If $debugMode Then
            LogToConsole("❌ Color mismatch at " & $scaledX & "," & $scaledY & " - Detected: " & $detectedColor & " Target: " & $Target_Color)
        EndIf
        Return False
    EndIf
EndFunc

Func ColorMatches($color1, $color2, $tolerance)
    ; Handle exact match first
    If $color1 = $color2 Then
        Return True
    EndIf
    
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
    
    ; Stricter tolerance for green detection
    If $debugMode Then
        $toleranceValue = 8 ; Much stricter tolerance in debug mode
    Else
        $toleranceValue = 5 ; Very strict tolerance for production
    EndIf
    
    ; For green colors, be especially strict about the green component
    Local $greenMatch = ($diffG <= 2) ; Green must be very close
    Local $redMatch = ($diffR <= $toleranceValue)
    Local $blueMatch = ($diffB <= $toleranceValue)
    
    Local $match = $greenMatch And $redMatch And $blueMatch
    
    If $debugMode Then
        LogToConsole("Color comparison: R(" & $r1 & " vs " & $r2 & ") G(" & $g1 & " vs " & $g2 & ") B(" & $b1 & " vs " & $b2 & ") Tolerance: " & $toleranceValue & " GreenMatch: " & ($greenMatch ? "Yes" : "No") & " Match: " & ($match ? "Yes" : "No"))
    EndIf
    
    Return $match
EndFunc

Func MemoryReadPixel($X, $Y, $handle)
    ; Enhanced pixel reading with multiple attempts
    Local $maxAttempts = 5
    Local $attempt = 0
    
    While $attempt < $maxAttempts
        Local $hDC = _WinAPI_GetWindowDC($handle)
        If $hDC = 0 Then
            If $debugMode Then
                LogToConsole("Attempt " & ($attempt + 1) & ": Failed to get DC")
            EndIf
            Sleep(50)
            $attempt += 1
            ContinueLoop
        EndIf

        Local $Color2 = DllCall("gdi32.dll", "int", "GetPixel", "int", $hDC, "int", $X, "int", $Y)
        _WinAPI_ReleaseDC($handle, $hDC)
        
        If @error Or $Color2[0] = -1 Then
            If $debugMode Then
                LogToConsole("Attempt " & ($attempt + 1) & ": GetPixel failed or returned -1")
            EndIf
            Sleep(50)
            $attempt += 1
            ContinueLoop
        EndIf
        
        ; Convert color format properly
        Global $sColor = Hex($Color2[0], 6)
        Local $result = Hex("0x" & StringRight($sColor, 2) & StringMid($sColor, 3, 2) & StringLeft($sColor, 2))
        
        If $debugMode And $attempt = 0 Then
            LogToConsole("Raw color: " & $Color2[0] & " Hex: " & $sColor & " Processed: " & $result)
        EndIf
        
        Return $result
    WEnd
    
    If $debugMode Then
        LogToConsole("Failed to read pixel after " & $maxAttempts & " attempts")
    EndIf
    Return 0
EndFunc

Func AlternativePixelRead($X, $Y, $handle)
    ; Alternative method using different approach
    Local $hDC = _WinAPI_GetWindowDC($handle)
    If $hDC = 0 Then
        Return 0
    EndIf
    
    ; Try using different coordinate mode
    Local $Color2 = DllCall("gdi32.dll", "int", "GetPixel", "int", $hDC, "int", $X, "int", $Y)
    _WinAPI_ReleaseDC($handle, $hDC)
    
    If @error Or $Color2[0] = -1 Then
        Return 0
    EndIf
    
    ; Convert to RGB format
    Local $color = $Color2[0]
    Local $r = BitAND($color, 0xFF)
    Local $g = BitAND($color, 0xFF00) / 0x100
    Local $b = BitAND($color, 0xFF0000) / 0x10000
    
    ; Convert to hex format
    Local $result = "0x" & Hex($r, 2) & Hex($g, 2) & Hex($b, 2)
    
    If $debugMode Then
        LogToConsole("Alternative method: Raw=" & $color & " RGB=(" & $r & "," & $g & "," & $b & ") Hex=" & $result)
    EndIf
    
    Return $result
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
    Local $endPoints[4][3]
    $endPoints[0][0] = 517
    $endPoints[0][1] = 313
    $endPoints[0][2] = 0xFFD800
    $endPoints[1][0] = 239
    $endPoints[1][1] = 297
    $endPoints[1][2] = 0xFBD400
    $endPoints[2][0] = 1651
    $endPoints[2][1] = 309
    $endPoints[2][2] = 0xFFD800
    $endPoints[3][0] = 1142
    $endPoints[3][1] = 238
    $endPoints[3][2] = 0xFFD800
    
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

    ; Search for green pixel in the specified area
    Local $searchArea[2][2] = [[61, 194], [119, 293]]  ; Search area coordinates
    Local $greenColors[5] = [0x00DA1E, 0x00D41E, 0x00D91E, 0x00DB1E, 0x00DC1E]  ; Green color variations
    
    ; Scale the search area
    Local $scaledStartX = Round($searchArea[0][0] * $scaleX)
    Local $scaledStartY = Round($searchArea[0][1] * $scaleY)
    Local $scaledEndX = Round($searchArea[1][0] * $scaleX)
    Local $scaledEndY = Round($searchArea[1][1] * $scaleY)
    
    If $debugMode Then
        LogToConsole("Searching area: (" & $scaledStartX & "," & $scaledStartY & ") to (" & $scaledEndX & "," & $scaledEndY & ")")
    EndIf
    
    ; Search for green pixel in the specified area with optimized scanning
    Local $searchStep = 3  ; Step size for faster scanning
    Local $handle = WinGetHandle($hWnd)
    Local $pixelsChecked = 0
    
    For $x = $scaledStartX To $scaledEndX Step $searchStep
        For $y = $scaledStartY To $scaledEndY Step $searchStep
            $pixelsChecked += 1
            ; Read pixel directly for better performance
            Local $detectedColor = MemoryReadPixel($x, $y, $handle)
            
            ; Log every 100th pixel in debug mode to see what's being detected
            If $debugMode And Mod($pixelsChecked, 100) = 0 Then
                Local $r = BitAND($detectedColor, 0xFF0000) / 0x10000
                Local $g = BitAND($detectedColor, 0x00FF00) / 0x100
                Local $b = BitAND($detectedColor, 0x0000FF)
                LogToConsole("Sample pixel at (" & $x & "," & $y & ") - RGB(" & $r & "," & $g & "," & $b & ") - Hex: " & $detectedColor)
            EndIf
            
            For $colorIndex = 0 To UBound($greenColors) - 1
                If ColorMatches($detectedColor, $greenColors[$colorIndex], $colorTolerance) Then
                    ; Additional verification: check if it's actually green
                    Local $r = BitAND($detectedColor, 0xFF0000) / 0x10000
                    Local $g = BitAND($detectedColor, 0x00FF00) / 0x100
                    Local $b = BitAND($detectedColor, 0x0000FF)
                    
                    ; Green should be the dominant component
                    If $g > $r And $g > $b And $g > 200 Then
                        $friendReadyDetected = True
                        $successfulDetections += 1
                        $Friend_Ready = True
                        $currentState = "Friend Ready"
                        
                        If $debugMode Then
                            LogToConsole("✅ Verified green pixel found at (" & $x & "," & $y & ") - RGB(" & $r & "," & $g & "," & $b & ") - Target: " & $greenColors[$colorIndex])
                        EndIf
                        
                        UpdateTooltip("🎉 FRIEND IS READY! Starting combat sequence...", "READY")
                        ExecuteCombatSequence()
                        StartCooldown()
                        UpdateTooltip("🕐 Starting 15-second cooldown period...", "COOLDOWN")
                        Sleep(3000)
                        Return
                    Else
                        If $debugMode Then
                            LogToConsole("❌ False positive at (" & $x & "," & $y & ") - RGB(" & $r & "," & $g & "," & $b & ") - Green not dominant")
                        EndIf
                    EndIf
                EndIf
            Next
        Next
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
    Local $keys[3]
    $keys[0] = '{F11}'
    $keys[1] = '{F6}'
    $keys[2] = '{F11}'
    
    Local $delays[3]
    $delays[0] = 1000
    $delays[1] = 1500
    $delays[2] = 500
    
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
UpdateTooltip("🔧 Hotkeys: F3=Cursor Test, F4=Analyze Colors, F5=Pause, F6=Test Area, F7=Test All, F8=Manual, F9=Debug, F10=Stats, END=Exit", "INFO")
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
    Local $adPoints[2][3]
    $adPoints[0][0] = 964
    $adPoints[0][1] = 767
    $adPoints[0][2] = 0x1F1826
    $adPoints[1][0] = 771
    $adPoints[1][1] = 401
    $adPoints[1][2] = 0xC642FF
    
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
HotKeySet("{F7}", "TestPixelDetection")
HotKeySet("{F6}", "TestSpecificPixel")
HotKeySet("{F4}", "AnalyzeAreaColors")
HotKeySet("{F3}", "TestCursorPixel")

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

Func TestPixelDetection()
    ; Test pixel detection at common points and search area
    Local $testPoints[8][3]
    ; Search area center points
    $testPoints[0][0] = 90   ; Center of search area X
    $testPoints[0][1] = 243  ; Center of search area Y
    $testPoints[0][2] = 0x00DA1E  ; Friend ready area center
    $testPoints[1][0] = 61   ; Start of search area
    $testPoints[1][1] = 194  ; Start of search area
    $testPoints[1][2] = 0x00DA1E  ; Friend ready area start
    $testPoints[2][0] = 119  ; End of search area
    $testPoints[2][1] = 293  ; End of search area
    $testPoints[2][2] = 0x00DA1E  ; Friend ready area end
    ; Game end points
    $testPoints[3][0] = 517
    $testPoints[3][1] = 313
    $testPoints[3][2] = 0xFFD800  ; Game end point 1
    $testPoints[4][0] = 239
    $testPoints[4][1] = 297
    $testPoints[4][2] = 0xFBD400  ; Game end point 2
    ; Other detection points
    $testPoints[5][0] = 1018
    $testPoints[5][1] = 818
    $testPoints[5][2] = 0xD7D7D7  ; Lose game point
    $testPoints[6][0] = 964
    $testPoints[6][1] = 767
    $testPoints[6][2] = 0x1F1826  ; Ad detection point
    $testPoints[7][0] = 771
    $testPoints[7][1] = 401
    $testPoints[7][2] = 0xC642FF  ; Ad detection point 2
    
    Local $testResults = "🔍 PIXEL DETECTION TEST" & @CRLF & @CRLF
    
    For $i = 0 To UBound($testPoints) - 1
        Local $x = $testPoints[$i][0]
        Local $y = $testPoints[$i][1]
        Local $targetColor = $testPoints[$i][2]
        
        Local $scaledX = Round($x * $scaleX)
        Local $scaledY = Round($y * $scaleY)
        
        Local $handle = WinGetHandle($hWnd)
        Local $detectedColor = MemoryReadPixel($scaledX, $scaledY, $handle)
        
        $testResults &= "Point " & ($i + 1) & " (" & $x & "," & $y & "):" & @CRLF
        $testResults &= "  Scaled: (" & $scaledX & "," & $scaledY & ")" & @CRLF
        $testResults &= "  Target: " & $targetColor & @CRLF
        $testResults &= "  Detected: " & $detectedColor & @CRLF
        $testResults &= "  Match: " & (ColorMatches($detectedColor, $targetColor, $colorTolerance) ? "✅" : "❌") & @CRLF & @CRLF
    Next
    
    MsgBox(64, "Pixel Detection Test", $testResults)
    LogToConsole("Pixel detection test completed")
EndFunc

Func TestSpecificPixel()
    ; Test the specified search area for green pixels
    Local $searchArea[2][2] = [[61, 194], [119, 293]]  ; Search area coordinates
    Local $greenColors[5] = [0x00DA1E, 0x00D41E, 0x00D91E, 0x00DB1E, 0x00DC1E]
    
    ; Scale the search area
    Local $scaledStartX = Round($searchArea[0][0] * $scaleX)
    Local $scaledStartY = Round($searchArea[0][1] * $scaleY)
    Local $scaledEndX = Round($searchArea[1][0] * $scaleX)
    Local $scaledEndY = Round($searchArea[1][1] * $scaleY)
    
    Local $handle = WinGetHandle($hWnd)
    If $handle = 0 Then
        MsgBox(16, "Error", "Cannot get game window handle")
        Return
    EndIf
    
    Local $results = "🎯 SEARCH AREA TEST" & @CRLF & @CRLF
    $results &= "Search area: (" & $searchArea[0][0] & "," & $searchArea[0][1] & ") to (" & $searchArea[1][0] & "," & $searchArea[1][1] & ")" & @CRLF
    $results &= "Scaled area: (" & $scaledStartX & "," & $scaledStartY & ") to (" & $scaledEndX & "," & $scaledEndY & ")" & @CRLF & @CRLF
    
    Local $foundPixels = 0
    Local $totalChecked = 0
    
    ; Sample some points in the area for testing
    For $x = $scaledStartX To $scaledEndX Step 10  ; Check every 10 pixels for testing
        For $y = $scaledStartY To $scaledEndY Step 10
            $totalChecked += 1
            Local $detectedColor = MemoryReadPixel($x, $y, $handle)
            
            For $colorIndex = 0 To UBound($greenColors) - 1
                If ColorMatches($detectedColor, $greenColors[$colorIndex], $colorTolerance) Then
                    $foundPixels += 1
                    $results &= "✅ Found green at (" & $x & "," & $y & ") - Color: " & $detectedColor & " (Target: " & $greenColors[$colorIndex] & ")" & @CRLF
                    ExitLoop
                EndIf
            Next
        Next
    Next
    
    $results &= @CRLF & "Summary: Found " & $foundPixels & " green pixels out of " & $totalChecked & " checked points"
    
    MsgBox(64, "Search Area Test", $results)
    LogToConsole("Search area test completed - Found " & $foundPixels & " green pixels")
EndFunc

Func AnalyzeAreaColors()
    ; Analyze all colors in the search area to understand what's being detected
    Local $searchArea[2][2] = [[61, 194], [119, 293]]
    Local $scaledStartX = Round($searchArea[0][0] * $scaleX)
    Local $scaledStartY = Round($searchArea[0][1] * $scaleY)
    Local $scaledEndX = Round($searchArea[1][0] * $scaleX)
    Local $scaledEndY = Round($searchArea[1][1] * $scaleY)
    
    Local $handle = WinGetHandle($hWnd)
    If $handle = 0 Then
        MsgBox(16, "Error", "Cannot get game window handle")
        Return
    EndIf
    
    Local $colorCounts[0][2]  ; [color, count]
    Local $totalPixels = 0
    Local $greenColors[0]  ; Array to store green-like colors
    
    ; Sample pixels in the area
    For $x = $scaledStartX To $scaledEndX Step 3
        For $y = $scaledStartY To $scaledEndY Step 3
            $totalPixels += 1
            Local $detectedColor = MemoryReadPixel($x, $y, $handle)
            
            ; Check if this is a green-like color
            Local $r = BitAND($detectedColor, 0xFF0000) / 0x10000
            Local $g = BitAND($detectedColor, 0x00FF00) / 0x100
            Local $b = BitAND($detectedColor, 0x0000FF)
            
            ; If green is dominant, add to green colors array
            If $g > $r And $g > $b And $g > 150 Then
                Local $found = False
                For $i = 0 To UBound($greenColors) - 1
                    If $greenColors[$i] = $detectedColor Then
                        $found = True
                        ExitLoop
                    EndIf
                Next
                If Not $found Then
                    ReDim $greenColors[UBound($greenColors) + 1]
                    $greenColors[UBound($greenColors) - 1] = $detectedColor
                EndIf
            EndIf
            
            ; Find if color already exists in array
            Local $found = False
            For $i = 0 To UBound($colorCounts) - 1
                If $colorCounts[$i][0] = $detectedColor Then
                    $colorCounts[$i][1] += 1
                    $found = True
                    ExitLoop
                EndIf
            Next
            
            ; Add new color if not found
            If Not $found Then
                ReDim $colorCounts[UBound($colorCounts) + 1][2]
                $colorCounts[UBound($colorCounts) - 1][0] = $detectedColor
                $colorCounts[UBound($colorCounts) - 1][1] = 1
            EndIf
        Next
    Next
    
    ; Sort by count (most common first)
    _ArraySort($colorCounts, 1, 0, 0, 1)
    
    Local $results = "🎨 COLOR ANALYSIS" & @CRLF & @CRLF
    $results &= "Area: (" & $searchArea[0][0] & "," & $searchArea[0][1] & ") to (" & $searchArea[1][0] & "," & $searchArea[1][1] & ")" & @CRLF
    $results &= "Total pixels sampled: " & $totalPixels & @CRLF & @CRLF
    
    ; Show green colors found
    $results &= "🟢 GREEN COLORS FOUND (" & UBound($greenColors) & "):" & @CRLF
    For $i = 0 To UBound($greenColors) - 1
        Local $r = BitAND($greenColors[$i], 0xFF0000) / 0x10000
        Local $g = BitAND($greenColors[$i], 0x00FF00) / 0x100
        Local $b = BitAND($greenColors[$i], 0x0000FF)
        $results &= ($i + 1) & ". " & $greenColors[$i] & " - RGB(" & $r & "," & $g & "," & $b & ")" & @CRLF
    Next
    
    $results &= @CRLF & "Most common colors:" & @CRLF
    
    ; Show top 10 colors
    Local $showCount = Min(10, UBound($colorCounts))
    For $i = 0 To $showCount - 1
        Local $r = BitAND($colorCounts[$i][0], 0xFF0000) / 0x10000
        Local $g = BitAND($colorCounts[$i][0], 0x00FF00) / 0x100
        Local $b = BitAND($colorCounts[$i][0], 0x0000FF)
        $results &= ($i + 1) & ". " & $colorCounts[$i][0] & " - RGB(" & $r & "," & $g & "," & $b & ") - Count: " & $colorCounts[$i][1] & @CRLF
    Next
    
    MsgBox(64, "Color Analysis", $results)
    LogToConsole("Color analysis completed - Found " & UBound($colorCounts) & " unique colors, " & UBound($greenColors) & " green colors")
EndFunc

Func TestCursorPixel()
    ; Test pixel at current cursor position
    Local $mousePos = MouseGetPos()
    Local $handle = WinGetHandle($hWnd)
    
    If $handle = 0 Then
        MsgBox(16, "Error", "Cannot get game window handle")
        Return
    EndIf
    
    ; Convert screen coordinates to client coordinates
    Local $tPoint = DllStructCreate("int X;int Y")
    DllStructSetData($tPoint, "X", $mousePos[0])
    DllStructSetData($tPoint, "Y", $mousePos[1])
    
    If _WinAPI_ScreenToClient($hWnd, $tPoint) Then
        Local $clientX = DllStructGetData($tPoint, "X")
        Local $clientY = DllStructGetData($tPoint, "Y")
        
        Local $detectedColor = MemoryReadPixel($clientX, $clientY, $handle)
        Local $r = BitAND($detectedColor, 0xFF0000) / 0x10000
        Local $g = BitAND($detectedColor, 0x00FF00) / 0x100
        Local $b = BitAND($detectedColor, 0x0000FF)
        
        Local $results = "🎯 CURSOR PIXEL TEST" & @CRLF & @CRLF
        $results &= "Screen position: (" & $mousePos[0] & "," & $mousePos[1] & ")" & @CRLF
        $results &= "Client position: (" & $clientX & "," & $clientY & ")" & @CRLF
        $results &= "Color: " & $detectedColor & @CRLF
        $results &= "RGB: (" & $r & "," & $g & "," & $b & ")" & @CRLF & @CRLF
        
        ; Test against target green colors
        Local $greenColors[5] = [0x00DA1E, 0x00D41E, 0x00D91E, 0x00DB1E, 0x00DC1E]
        $results &= "Testing against target colors:" & @CRLF
        
        For $i = 0 To UBound($greenColors) - 1
            Local $match = ColorMatches($detectedColor, $greenColors[$i], $colorTolerance)
            $results &= "Target " & $greenColors[$i] & ": " & ($match ? "✅ MATCH" : "❌ NO MATCH") & @CRLF
        Next
        
        MsgBox(64, "Cursor Pixel Test", $results)
        LogToConsole("Cursor pixel test completed at (" & $clientX & "," & $clientY & ") - Color: " & $detectedColor)
    Else
        MsgBox(16, "Error", "Failed to convert screen coordinates to client coordinates")
    EndIf
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