$client_id = "robson"

$recv_queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[String]'
$send_queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[String]'

$ws = New-Object Net.WebSockets.ClientWebSocket
$cts = New-Object Threading.CancellationTokenSource
$ct = New-Object Threading.CancellationToken($false)

Write-Output "Connecting..."
$connectTask = $ws.ConnectAsync("ws://localhost:8000/ws/$client_id", $cts.Token)
do { Sleep(1) }
until ($connectTask.IsCompleted)
Write-Output "Connected!"

$recv_job = {
    param($ws, $recv_queue)

    $buffer = [Net.WebSockets.WebSocket]::CreateClientBuffer(1024, 1024)
    $ct = [Threading.CancellationToken]::new($false)
    $taskResult = $null

    while ($ws.State -eq [Net.WebSockets.WebSocketState]::Open) {
        $jsonResult = ""
        do {
            $taskResult = $ws.ReceiveAsync($buffer, $ct)
            while (-not $taskResult.IsCompleted -and $ws.State -eq [Net.WebSockets.WebSocketState]::Open) {
                [Threading.Thread]::Sleep(10)
            }

            $jsonResult += [Text.Encoding]::UTF8.GetString($buffer, 0, $taskResult.Result.Count)
        } until (
            $ws.State -ne [Net.WebSockets.WebSocketState]::Open -or $taskResult.Result.EndOfMessage
        )

        if (-not [string]::IsNullOrEmpty($jsonResult)) {
            $recv_queue.Enqueue($jsonResult)
        }
    }
}

$send_job = {
    param($ws, $send_queue)

    $ct = New-Object Threading.CancellationToken($false)
    $workitem = $null
    while ($ws.State -eq [Net.WebSockets.WebSocketState]::Open) {
        if ($send_queue.TryDequeue([ref] $workitem)) {
            [ArraySegment[byte]]$msg = [Text.Encoding]::UTF8.GetBytes($workitem)
            $ws.SendAsync(
                $msg,
                [System.Net.WebSockets.WebSocketMessageType]::Text,
                $true,
                $ct
            ).GetAwaiter().GetResult() | Out-Null
        }
    }
}

Write-Output "Starting recv runspace"
$recv_runspace = [PowerShell]::Create().AddScript($recv_job).
    AddParameter("ws", $ws).
    AddParameter("recv_queue", $recv_queue).BeginInvoke() | Out-Null

Write-Output "Starting send runspace"
$send_runspace = [PowerShell]::Create().AddScript($send_job).
    AddParameter("ws", $ws).
    AddParameter("send_queue", $send_queue).BeginInvoke() | Out-Null

# Function to clear the screen
function Clear-Screen {
    cls
}

# Initialize progress indicators for "Downloading package..."
$downloadProgress = ""

# Define messages
$messages = @(
    @{ action = "Initializing..."; msg = "Preparing installation..." },
    @{ action = "Downloading package..."; msg = $downloadProgress += "#" },
    @{ action = "Installing..."; msg = "Installing application files..." },
    @{ action = "Configuring..."; msg = "Applying configurations..." },
    @{ action = "Completed"; msg = "Installation completed successfully!" },
    @{ action = "EXIT"; msg = "Exiting installer..." }
)

# Send each message


try {
    
    while ($ws.State -eq [Net.WebSockets.WebSocketState]::Open) {
        $msg = $null
        while ($recv_queue.TryDequeue([ref]$msg)) {
            
            write-host $msg -ForegroundColor Green
            if($msg -match "SEND") {
                foreach ($msgData in $messages) {
                    $paramHashtable = @{
                        app = "7-Zip (x64) - 24.07.00.0"
                        action = $msgData.action
                        msg = $msgData.msg
                    }
                    $jsonMessage = ConvertTo-Json -InputObject $paramHashtable
                    $send_queue.Enqueue($jsonMessage)
                    
                }
            }
        }
        
        #Clear-Screen
        <#foreach ($message in $messages) {
            Write-Output $message
        }#>
        
        # Print the prompt at the bottom
        #Write-Host -NoNewline "Enter message: "
        
        # Check for new messages every second
        Start-Sleep -Milliseconds 500

        
        
        <#if ([Console]::KeyAvailable) {
            $userInput = Read-Host
            if ($userInput -ne "") {
                $hash = @{
                    ClientID = $client_id
                    Payload = $userInput
                }

                $test_payload = New-Object PSObject -Property $hash
                $json = ConvertTo-Json $test_payload
                $send_queue.Enqueue($json)
            }
        }#>
    }
}
finally {
    Write-Output "Closing WS connection"
    $closetask = $ws.CloseAsync(
        [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
        "Client closed",
        $ct
    )

    do { Sleep(1) }
    until ($closetask.IsCompleted)
    $ws.Dispose()

    Write-Output "Stopping runspaces"
    if ($recv_runspace) {
        $recv_runspace.Stop()
        $recv_runspace.Dispose()
    }

    if ($send_runspace) {
        $send_runspace.Stop()
        $send_runspace.Dispose()
    }
}