param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$false)]
    [string]$ProfileName = $("fd-" + $ResourceGroupName)
)

Write-Host "Removing Azure Front Door profile '$ProfileName' in RG '$ResourceGroupName'..." -ForegroundColor Cyan

# Clean delete of the profile will remove endpoint, origins, routes, and security policy
az resource delete --ids \
  (az resource show -g $ResourceGroupName -n $ProfileName --resource-type Microsoft.Cdn/profiles --query id -o tsv) --verbose --only-show-errors

Write-Host "Done." -ForegroundColor Green
