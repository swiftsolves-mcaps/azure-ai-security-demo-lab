param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [string]$AppServiceName,

    [Parameter(Mandatory=$false)]
    [ValidateSet('Standard_AzureFrontDoor','Premium_AzureFrontDoor')]
    [string]$Sku = 'Standard_AzureFrontDoor',

    [Parameter(Mandatory=$false)]
    [string]$ProfileName = $("fd-" + $ResourceGroupName),

    [Parameter(Mandatory=$false)]
    [string]$EndpointName = $("ep-" + $ResourceGroupName)
)

# Preconditions: logged in az cli and correct subscription selected

Write-Host "Discovering App Service..." -ForegroundColor Cyan
$web = az webapp show -g $ResourceGroupName -n $AppServiceName --only-show-errors | ConvertFrom-Json
if (-not $web) { throw "App Service '$AppServiceName' not found in RG '$ResourceGroupName'" }

$appServiceId = $web.id
$appServiceHost = $web.defaultHostName

# Ensure HTTPS only on App Service (recommended when fronted by AFD)
az webapp update -g $ResourceGroupName -n $AppServiceName --set httpsOnly=true | Out-Null

# Deploy AFD + WAF via Bicep
Write-Host "Deploying Azure Front Door ($Sku) + WAF in RG '$ResourceGroupName'..." -ForegroundColor Cyan
$deploymentName = "afd-waf-" + (Get-Date -Format "yyyyMMddHHmmss")

$whatIf = az deployment group what-if -g $ResourceGroupName -n $deploymentName --template-file ./infra/frontdoor.bicep --parameters profileName=$ProfileName endpointName=$EndpointName appServiceId=$appServiceId appServiceDefaultHostname=$appServiceHost wafPolicyName="afd-waf-$ResourceGroupName" sku=$Sku --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0) { Write-Warning "What-if failed; continuing with create." }

$deployment = az deployment group create -g $ResourceGroupName -n $deploymentName --template-file ./infra/frontdoor.bicep --parameters profileName=$ProfileName endpointName=$EndpointName appServiceId=$appServiceId appServiceDefaultHostname=$appServiceHost wafPolicyName="afd-waf-$ResourceGroupName" sku=$Sku --only-show-errors | ConvertFrom-Json

$endpointHost = $deployment.properties.outputs.endpointHostname.value
Write-Host "Front Door deployed. Default endpoint: https://$endpointHost" -ForegroundColor Green

# Optional: Print guidance for custom domains and origin header
Write-Host "Tip: Add a custom domain to Front Door and update app CORS if needed." -ForegroundColor Yellow
