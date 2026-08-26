[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080/v1',
    [string]$ApiKey = 'local',
    [string]$Model = '',
    [int]$TimeoutSec = 120,
    [switch]$SkipToolTest
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$apiRoot = $BaseUrl.TrimEnd('/')
if ($apiRoot.EndsWith('/v1', [System.StringComparison]::OrdinalIgnoreCase)) {
    $serverRoot = $apiRoot.Substring(0, $apiRoot.Length - 3)
} else {
    $serverRoot = $apiRoot
    $apiRoot = "$apiRoot/v1"
}

$headers = @{
    Authorization = "Bearer $ApiKey"
}

$health = Invoke-RestMethod -Uri "$serverRoot/health" -Headers $headers -TimeoutSec $TimeoutSec
if ($health.status -ne 'ok') {
    throw "Server health is '$($health.status)', expected 'ok'."
}

$models = Invoke-RestMethod -Uri "$apiRoot/models" -Headers $headers -TimeoutSec $TimeoutSec
if (-not $Model) {
    $Model = [string]$models.data[0].id
}
if (-not $Model) {
    throw 'No model ID was returned by /v1/models.'
}

$chatBody = @{
    model = $Model
    messages = @(
        @{ role = 'user'; content = 'Reply with exactly OK.' }
    )
    max_tokens = 16
    temperature = 0
    stream = $false
} | ConvertTo-Json -Depth 12 -Compress

$chat = Invoke-RestMethod -Uri "$apiRoot/chat/completions" -Method Post -Headers $headers `
    -ContentType 'application/json; charset=utf-8' -Body $chatBody -TimeoutSec $TimeoutSec
$chatText = [string]$chat.choices[0].message.content

$toolPassed = $null
$toolFinishReason = $null
if (-not $SkipToolTest) {
    $toolBody = @{
        model = $Model
        messages = @(
            @{ role = 'system'; content = 'Use the requested function. Do not answer normally.' },
            @{ role = 'user'; content = 'Call return_status with value OK.' }
        )
        tools = @(
            @{
                type = 'function'
                function = @{
                    name = 'return_status'
                    description = 'Return a short status value.'
                    parameters = @{
                        type = 'object'
                        properties = @{
                            value = @{ type = 'string'; description = 'The status value.' }
                        }
                        required = @('value')
                        additionalProperties = $false
                    }
                }
            }
        )
        tool_choice = 'auto'
        max_tokens = 128
        temperature = 0
        stream = $false
    } | ConvertTo-Json -Depth 20 -Compress

    $toolResponse = Invoke-RestMethod -Uri "$apiRoot/chat/completions" -Method Post -Headers $headers `
        -ContentType 'application/json; charset=utf-8' -Body $toolBody -TimeoutSec $TimeoutSec
    $toolCalls = @($toolResponse.choices[0].message.tool_calls)
    $toolPassed = $toolCalls.Count -gt 0 -and $null -ne $toolCalls[0]
    $toolFinishReason = [string]$toolResponse.choices[0].finish_reason
}

[pscustomobject]@{
    Health = [string]$health.status
    Model = $Model
    ChatPassed = -not [string]::IsNullOrWhiteSpace($chatText)
    ChatText = $chatText
    ToolTestRun = -not [bool]$SkipToolTest
    ToolPassed = $toolPassed
    ToolFinishReason = $toolFinishReason
} | Format-List

