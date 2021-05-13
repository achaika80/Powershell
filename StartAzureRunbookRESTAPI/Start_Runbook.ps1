<#
.SYNOPSIS
    .
.DESCRIPTION
    Starts Azure Automation Runbook remotely using Azure REST API. Shows provisioning and output. Requires 
    Azure Service Principal Name (SPN) credentials. 
.PARAMETER TenantId
    Azure tenant ID.
.PARAMETER SubscriptionId
    Azure subscription ID.
.PARAMETER ClientId
    Azure SPN ID
.PARAMETER ClientSecret
    Azure SPN key
.PARAMETER RunbookName
    Azure Automation Runbook name which need to be ran. Runbook has to be published before its
    can be accessed by REST API.
.PARAMETER AaccountName
    Azure Automation Account name.
.PARAMETER AaccountNameAaResourceGroupName
    Azure Automation Account Resource Group name.
.EXAMPLE
    ./Start_Runbook.ps1 -TenantId "<>" -SubscriptionId "<>" -ClientId "<>" -ClientSecret "<>" -RunbookName "<>" -AaccountName "<>" -AaResourceGroupName"<>
    Run Azure Runbook using RESTAPI call

.NOTES
    Author: Alex Chaika
    Date:   May 13, 2021 
    
.LINK
    https://github.com/achaika80/Powershell/tree/master/SharePermissions
   
#>

[cmdletbinding()]
    Param($TenantId,
        $SubscriptionId,
        $ClientId,
        $ClientSecret,
        $RunbookName,
        $AaccountName,
        $AaResourceGroupName

    )
function GetToken {
    param (
        $TenantId,
        $SubscriptionId,
        $ClientId,
        $ClientSecret
    )
    
    $Resource = "https://management.core.windows.net/"
    $RequestAccessTokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/token"
    $body = "grant_type=client_credentials&client_id=$ClientId&client_secret=$ClientSecret&resource=$Resource"
    $Token = Invoke-RestMethod -Method Post -Uri $RequestAccessTokenUri -Body $body -ContentType 'application/x-www-form-urlencoded'

    return $Token
}

function StartRunbook {
    param (
        $RunbookName,
        $AaccountName,
        $AaResourceGroupName,
        $SubscriptionId,
        $Token
    )
    
    $JobId = [GUID]::NewGuid().ToString()
    $Headers = @{}
    $Headers.Add("Authorization","$($Token.token_type) "+ " " + "$($Token.access_token)")
    $body = @{
        "properties" = @{
            "runbook" = @{
                "name" = $RunbookName
            };
            "parameters" = @{}
        }
    } | ConvertTo-Json -Depth 4

    $Uri = "https://management.azure.com/subscriptions/$($SubscriptionId)/resourceGroups/$($AaResourceGroupName)/providers/Microsoft.Automation/automationAccounts/$($AaccountName)/jobs/$($JobId)?api-version=2017-05-15-preview"
    
    $Response = Invoke-RestMethod -Uri $Uri -Method Put -Body $body -Headers $Headers -ContentType 'application/json'

    if ($Response.properties.provisioningState -eq "Processing"){

        $doLoop = $true
        while ($doLoop) {
            sleep 5
            $job = Invoke-RestMethod -Uri $URI -Method GET -Headers $Headers
            $status = $job.properties.provisioningState
            write-output "      Provisioning State = $($status)"
            $doLoop = (($status -ne "Succeeded") -and 
            ($status -ne "Failed") -and ($status -ne "Suspended") -and 
            ($status -ne "Stopped"))
        } 
    
        $Uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$($AaResourceGroupName)/providers/Microsoft.Automation/automationAccounts/$($AaccountName)/jobs/$($JobId)/output?api-version=2017-05-15-preview"

        $Response = Invoke-RestMethod -Uri $Uri -Method Get -Headers $Headers
        $Response

    }

}

$Token = GetToken -TenantId $TenantId -SubscriptionId $SubscriptionId `
    -ClientId $ClientId -ClientSecret $ClientSecret

StartRunbook -RunbookName Test-AzConnection -AaccountName "RPS-AA-Infra-PROD" `
    -AaResourceGroupName "RG-TRS-Infastructure-Automation" `
    -SubscriptionId $SubscriptionId -Token $Token