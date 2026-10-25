# Sends evaluation events straight to the SQS queue (bypassing the
# evaluation-service) to load the analytics-service consumer and its HPA.
# Batches are sent in parallel so the queue fills faster than one consumer
# can drain it (requires PowerShell 7+).
# Usage:
#   ./loadtest/sqs-burst.ps1 -QueueUrl <url> [-Batches 500] [-Parallel 20]
# Watch: kubectl get hpa -n togglemaster-app -w
param(
    [Parameter(Mandatory = $true)][string]$QueueUrl,
    [int]$Batches = 500,
    [int]$Parallel = 20
)

$start = Get-Date
1..$Batches | ForEach-Object -ThrottleLimit $Parallel -Parallel {
    $flags = "black-friday", "dark-mode", "new-checkout"
    # SQS accepts at most 10 messages per batch.
    $entries = foreach ($i in 1..10) {
        $body = @{
            user_id   = "user-$(Get-Random -Maximum 100000)"
            flag_name = $flags | Get-Random
            result    = [bool](Get-Random -Maximum 2)
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
        } | ConvertTo-Json -Compress
        @{ Id = "m$i"; MessageBody = $body }
    }
    $tmp = New-TemporaryFile
    try {
        [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject @($entries) -Compress))
        aws sqs send-message-batch --queue-url $using:QueueUrl --entries "file://$tmp" --output text --query "length(Successful)" | Out-Null
    }
    finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}
$seconds = [int]((Get-Date) - $start).TotalSeconds
Write-Host "$($Batches * 10) messages sent in $seconds s"
