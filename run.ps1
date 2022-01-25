param (
    [string]$TargetRepository,
    [string]$GitRepo,
    [string]$KeyVaultName,
    [string]$SecretName,
    [switch]$DryRun
)

$tasks = @()
if ($true -eq $DryRun) {
    Write-Output "************ Have you ever had a dream that you were so sure was real? ************"
    $GitToken = "**********"
} else {
    $GitToken = az keyvault secret show --name $SecretName --vault-name $KeyVaultName --query "value"
    $pools = az acr agentpool list --registry $TargetRepository  --only-show-errors
    $tasks = az acr task list --registry $TargetRepository | Convertfrom-json
    if ( ($null -eq $pools) -or ($pools.Length -eq 0) ) {
        az acr agentpool create --name BaseImageAgentPool --registry $TargetRepository --only-show-errors
    } 
}

$basePath = $PSScriptRoot

if ($null -ne $System) {
    # Running on ADO
    $basePath = $(System.DefaultWorkingDirectory)
}

$images = Get-ChildItem (Join-Path -Path $basePath -ChildPath "images") -Filter "*.Dockerfile"

foreach ($image in $images) {
    Write-Output "-------------------"
    Write-Output "Processing ${image}"
    Write-Output "-------------------"

    $params = @{}

    #foreach($line in Get-Content $image) {
    #    if ($true -eq $line.StartsWith("#")) {
    #        if ($true -eq $line.Contains("=")) {
    #            $params += ConvertFrom-StringData -StringData $line.Substring(1)
    #        }
    #    } elseif ($true -eq $line.StartsWith("FROM")) {
    #        $santizedImage = $line.Substring(4).Trim()
    #        if ($santizedImage.Contains("/")) {
    #            $params += @{ registry = $santizedImage.Substring(0, $santizedImage.LastIndexOf("/"))}
    #        }
    #
    #        $imageAndTag = $santizedImage.Substring($santizedImage.LastIndexOf("/") + 1)
    #    
    #        $params += @{ image = $imageAndTag.Substring(0, $imageAndTag.LastIndexOf(":")) }
    #        $params += @{ tag = $imageAndTag.Substring($imageAndTag.LastIndexOf(":") + 1)}
    #    }
    #}


    $taskName = [System.IO.Path]::GetFileNameWithoutExtension($image) 
    $params += @{ image = $taskName.Substring(0, $taskName.IndexOf("-")) }
    $params += @{ tag = $taskName.Substring($taskName.IndexOf("-") + 1)}
    
    $params | Format-Table

    $relativePath = Resolve-Path $image -Relative

    $foundTask = $tasks |? { $_.name -imatch $taskName }
    if ( $null -ne $foundTask ) {
        Write-Output "Skipping"
    } else {   
        Write-Output "-------------------"

        $command ="& az acr task create --name $taskName -f task.yaml -r $TargetRepository
            --context $GitRepo
            --base-image-trigger-enabled True
            --set SOURCE_IMAGE=$($params.image) --set SOURCE_TAG=$($params.tag) --set DOCKERFILE_PATH=$relativePath
            --git-access-token $GitToken
            --file ./task.yaml"

        if ($True -eq $DryRun) {
            Write-Host "Would have run: $command"
        }
        else {
            Invoke-Expression $command.Replace([System.Environment]::NewLine, "")
        }
    }
    
    Write-Output "==================="
}