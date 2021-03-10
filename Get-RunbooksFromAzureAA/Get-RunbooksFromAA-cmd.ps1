<#
.SYNOPSIS
    .
.DESCRIPTION
    Created as workaround for the following issue with Export-AzAutomationRunbook cmdlet on Linux and MacOS:
    https://github.com/Azure/azure-powershell/issues/11101

    PLEASE NOTE THE AUTOMATION ACCOUNT IS CONSIDERED THE ULTIMATE SOURCE. IF YOU HAVE SCRIPTS WITH THE SAME
    NAMES IN THE FOLDER YOU CHOOSEN TO EXPORT RUNBOOKS TO THEY WILL BE REPLACED IF RUNBOOKS MODIFIED TIME IS 
    GREATER OR EQUAL THAN THE LAST MODIFED TIME OF THE SCRIPT FILES IN THE FOLDER!!!
    
    NO WARRANTIES USE AT YOUR OWN RISK

.PARAMETER aaName
    This is the name of the automation account to export runbooks from. Parameter is mandatory.
.PARAMETER rgName
    This is the name of the resource group for the automation account to export runbooks from. Parameter is mandatory. 
.PARAMETER RunbooksFolder
    This is the full path to the folder to export runbooks to. Parameter is optional. If ommited current folder is used.
.PARAMETER tmpFolderName
    In order to work around the issue described in https://github.com/Azure/azure-powershell/issues/11101
    script creates temporary folder inside of the folder which is used to export runbooks to. This temporary 
    folder is removed after succesfull export. Parameter is optional. 
    If ommited "tmp" folder name is used.
.EXAMPLE
    PS ./Get-RunbooksFromAA-cmd.ps1 -aaName AA-Account -rgName AA-Account-RG
    Exports runbooks from AA-Account located under resource group AA-Account-RG to the folder where script is located
.EXAMPLE
    PS ./Get-RunbooksFromAA-cmd.ps1 -aaName AA-Account -rgName AA-Account-RG -runbooksFolder /Users/User/AA-Account-Runbooks
    Exports runbooks from AA-Account located under resource group AA-Account-RG to the /Users/User/AA-Account-Runbooks
.EXAMPLE
    PS ./Get-RunbooksFromAA-cmd.ps1 -aaName AA-Account -rgName AA-Account-RG -runbooksFolder /Users/User/AA-Account-Runbooks -tmpFolderName temp
    Exports runbooks from AA-Account located under resource group AA-Account-RG to the /Users/User/AA-Account-Runbooks 
    using /Users/User/AA-Account-Runbooks/temp folder to get around the issue 
.NOTES
    Author: Alex Chaika
    Date:   Mar 10, 2021 
    
.LINK
    https://github.com/achaika80/Powershell/tree/master/Get-RunbooksFromAzureAA
   
#>

[cmdletbinding()]
    Param([Parameter(Mandatory=$true)]$aaName,
          [Parameter(Mandatory=$true)]$rgName,
          [Parameter(Mandatory=$false)]$runbooksFolder = (Split-Path -Parent $PSCommandPath),
          [Parameter(Mandatory=$false)]$tmpFolderName = "tmp"
          )

$tmpFolder = "$runbooksFolder/$tmpFolderName"

if(-not (Test-Path -Path $tmpFolder)){
    New-Item -Path $tmpFolder -ItemType Directory
}

$aaRunbooks = Get-AzAutomationRunbook -ResourceGroupName $rgName `
    -AutomationAccountName $aaName `
    | ? {$_.State -eq "Published"}
$localRunbooks = Get-ChildItem -Path $runbooksFolder

$aaRunbooks | % {
    if($_.Name -notin $localRunbooks.BaseName){
        Write-Host "`nExporting $($_.Name)" -ForegroundColor Green
        Export-AzAutomationRunbook -Name $_.Name `
        -ResourceGroupName $_.ResourceGroupName `
        -AutomationAccountName $aaName `
        -OutputFolder $tmpFolder `
        -Slot Published `
    }
    else{
        $localRunbook = $localRunbooks | ?{$_.BaseName -eq $_.Name}
        if($localRunbook.LastWriteTime.LocalDateTime -le $_.LastModifiedTime){
            Write-Host "`nExporting $($_.Name)" -ForegroundColor Green
            Export-AzAutomationRunbook -Name $_.Name `
            -ResourceGroupName $_.ResourceGroupName `
            -AutomationAccountName $aaName `
            -OutputFolder $tmpFolder `
            -Slot Published `
            -Force `
        }


    }

}

$exportedRunbooks = Get-ChildItem -Path $runbooksFolder `
    | ?{$_.BaseName.StartsWith("$tmpFolderName") -and  $_.Extension -eq ".ps1"}
$exportedRunbooks | %{
    $destName = "$runbooksFolder/$($_.Name.TrimStart("$tmpFolderName\"))"
    $_.MoveTo($destName, $true)
}

if((Get-ChildItem -Path $tmpFolder -Recurse).Count -eq 0){
    Remove-Item -Path $tmpFolder -Force
}