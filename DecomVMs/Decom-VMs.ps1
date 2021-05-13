<#
.SYNOPSIS
    .
.DESCRIPTION
    Decommissions Azure VMs removing VM itself along with NIC and virtual disks as well as boot diagnostincs files.
    Takes either VM name amd Resoource group accompanied by Azure subscription Id or CSV file with VM names and 
    resource groups accompanied by Azure subscription Id. You need to be authenticated in Azure before running this script.
.PARAMETER csvfile
    This is the name of the csv file which consists the names and resource groups of Azure VMs to remove. File has to have only two columns
    named "Name" and "RgName". 
    Has to be provided as a path like: "c:\temp\csvfile.csv" for example.
    File format:
    Name,RgName
    server01,RG
    server02,RG
    serverXX,Rg1
.PARAMETER name
    Name of Azure VM which needs to removed.
.PARAMETER resourceGroupName
    Resource group of Azure VM which needs to removed.
.PARAMETER subscriptionId 
    Id of the Azure subscription where VM(s) which need to be removed belong. 
.EXAMPLE
    PS .\Decom-VMs.ps1 -name VMNAme -resourceGroupName Resource-Group -subscriptionId xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    Removes "VMNAme" VM from Resource Group "Resource-Group"
.EXAMPLE
    PS .\Decom-VMs.ps1 -csvfile C:\Temp\Decom.csv -subscriptionId xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    Removes every VM from C:\Temp\Decom.csv file.

.NOTES
    Author: Alex Chaika
    Date:   Mar 30, 2020 
    
.LINK
    https://github.com/achaika80/Powershell/tree/master/TBD
   
#>


[CmdletBinding(DefaultParameterSetName = "vm")]
param (
    [Parameter(ParameterSetName='vm')]
    [string]
    $name,
    [Parameter(ParameterSetName='vm')]
    [string]
    $resourceGroupName,
    [Parameter(ParameterSetName='csv')]
    [string]
    $csvfile,
    [Parameter()]
    [string]
    $subscriptionId
)

function GetAllDisks{
    param ($VMName,
           $VMRg)
    $vm = Get-AzVm -Name $VMName -ResourceGroupName $VMRg
    $Disks = @()
    $info = "" | Select ResourceGroupName, DiskName
    $info.ResourceGroupName = $VMRg
    $info.DiskName = $vm.StorageProfile.OsDisk.Name
    $Disks+=$info
    $vm.StorageProfile.DataDisks | %{
       $info = "" | Select ResourceGroupName, DiskName
       $info.ResourceGroupName = $VMRg
       $info.DiskName = $_.Name
       $Disks+= $info
    }
return $Disks
      
}

function getNic {
    param (
        $vmName,
        $vmRg
    )
    return (Get-AzVM -ResourceGroupName $VmRg -Name $VmName).NetworkProfile.NetworkInterfaces[0].Id | Split-Path -Leaf

}

function RemoveAdAccount {
    param (
        $vmName
    )
    try{
        Get-ADComputer $vmName | Remove-ADObject -Recursive -Confirm:$false -ErrorAction Stop
        }
    catch{
        Write-Host "No Account is found in AD for $VmName, please check manualy"
        }
}

function removeLock {
    param (
        $vmName,
        $vmRg
    )
    
    $LockId = (Get-AzResourceLock -ResourceName $vmName `
         -ResourceType 'Microsoft.Compute/virtualMachines' `
         -ResourceGroupName $vmRg).LockId
    
    if($LockId){
        Write-Host "Removing Azure Resource Lock from $vmName in $vmRg`n" -ForegroundColor Green
        Remove-AzResourceLock -LockId $LockId -Force
    }
}

function remove-BootDiag {
    param (
        $vmName,
        $vmRg
    )
    
    $vm = get-azvm -ResourceGroupName $vmRg -Name $vmName

    if ($vm.DiagnosticsProfile.BootDiagnostics.Enabled){

        $stProfile = $vm.DiagnosticsProfile.BootDiagnostics.StorageUri

        $stAccName = $stProfile.TrimStart('https://').Split('.')[0]

        $stAcc = Get-AzStorageAccount | ? {$_.StorageAccountName -eq $stAccName}

        $stAccKey = (Get-AzStorageAccountKey -ResourceGroupName $stAcc.ResourceGroupName `
            -StorageAccountName $stAcc.StorageAccountName)[0].Value

        $stAccCtx = New-AzStorageContext -StorageAccountName $stAcc.StorageAccountName `
            -StorageAccountKey $stAccKey

        $ctns =  Get-AzStorageContainer -Context $stAccCtx | ?{$_.Name -match "bootdiagnostics"}

        foreach ($cn in $ctns){
        $blob = Get-AzStorageBlob -Context $stAccCtx -Container $cn.Name `
                | ?{$_.Name -match $vmName}

        if($blob){ break }

        }

        Remove-AzStorageContainer -Context $stAccCtx -Name $cn.Name -Force
    }
    
}

function removeAll{
    param (
        $vmName,
        $vmRg
    )

    $Nic = getNic -vmName $vmName -vmRg $vmRg
    $Disks = GetAllDisks -VMName $vmName -VMRg $vmRg
    
    removeLock -vmName $vmName -vmRg $vmRg

    Write-Host "Removing Boot Diagnostics files from $vmName`n" -ForegroundColor Green

    remove-BootDiag -vmName $vmName -vmRg $vmRg

    Write-Host "Removing $vmName from RG $vmRg...`n" -ForegroundColor Green

    Remove-AzVm -Name $vmName -ResourceGroupName $vmRg -Force

    Write-Host "Removing Network Interface $Nic from $vmRg`n" -ForegroundColor Green

    Remove-AzNetworkInterface -Name $Nic -ResourceGroupName $vmRg -Force

    Write-Host "Removing Disks of $vmName from Resource Group $vmRg`n" -ForegroundColor Green

    $Disks | %{
        Write-Host "`nRemoving Disk: $($_.DiskName) from Resource Group: $($_.ResourceGroupName)`n" -ForegroundColor Green
        Remove-AzDisk -ResourceGroupName $_.ResourceGroupName -DiskName $_.DiskName -Force
       }
    
    Write-Host "Removing AD Account of $vmName`n" -ForegroundColor Green

    RemoveAdAccount -vmName $vmName
}

Set-AzContext -SubscriptionId $subscriptionId

if($PSCmdlet.ParameterSetName -eq 'vm'){

    removeAll -vmName $name -vmRg $resourceGroupName
}
else {
    
    Import-Csv -Path $csvfile | %{

        removeAll -vmName $_.Name -vmRg $_.RgName
    }
}