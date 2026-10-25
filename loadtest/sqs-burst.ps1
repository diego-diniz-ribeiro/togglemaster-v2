# Sends evaluation events straight to the SQS queue (bypassing the
# evaluation-service) to load the analytics-service consumer and its HPA.
# Usage:
#   ./loadtest/sqs-burst.ps1 -QueueUrl <url> [-Batches 300]
# Watch: kubectl get hpa -n togglemaster-app -w
param(
    [Parameter(Mandatory = $true)][string]$QueueUrl,
    [int]$Batches = 300
)

$flags = "black-friday", "dark-mode", "new-checkout"
$tmp = New-TemporaryFile
try {
    for ($b = 1; $b -le $Batches; $b++) {
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
        [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject @($entries) -Compress))
        aws sqs send-message-batch --queue-url $QueueUrl --entries "file://$tmp" --query "length(Successful)" --output text | Out-Null
        if ($b % 50 -eq 0) { Write-Host "$($b * 10) messages sent" }
    }
}
finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
}
