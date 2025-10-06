function RunCustomCleanup {
    Param()

    $currentTime = Get-Date
    $containers = docker ps -a --format "{{.ID}}|{{.CreatedAt}}|{{.Status}}"
    foreach ($container in $containers) {
        $parts = $container -split "\|", 3
        $id = $parts[0]
        $rawDate = $parts[1]
        $cleanDateStr = $rawDate -replace '\s\+\d{4}\sUTC', ''
        try {
            $createdAt = Get-Date $cleanDateStr
            $age = $currentTime - $createdAt
            if ($age.TotalHours -ge 2) {
                Write-Host "Container $id is older than 2 hours (Created: $createdAt, Age: $([math]::Round($age.TotalHours, 2)) hours)"
                $isRunning = docker inspect -f "{{.State.Running}}" $id
                if ($isRunning -eq "true") {
                    Write-Host "Stopping container $id..."
                    docker stop $id
                }
                Write-Host "Removing container $id..."
                docker rm $id
            }
        }
        catch {
            Write-Warning "Could not parse date for container $($id): $rawDate"
        }
    }
}