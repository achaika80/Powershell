<#
.SYNOPSIS
    .
.DESCRIPTION
    Connects remotely to the computers provided in the csv file enumerates shares and replaces "Everyone" group in the every share
    permissions to "Authenticated users" group. Script doesn't change NTFS permissions, only SMB ones.
    When script is completed report file with the status of attemted changes is produced. Report is saved to the script folder with
    "report.txt" name.
.PARAMETER csvfile
    This is the name of the csv file which consists the names of the computers to process. File has to have only one column which
    has to be titled "Name"
    Can be provided as path: "c:\temp\csvfile.csv" or name "csvfile.csv". If provided as just a name, file has to be present in the same 
    folder the script is being ran from.
    File format:
    Name
    server01
    server02
    serverXX
.PARAMETER PreserveCurrentPermissions
    When set preserves current shared folder permissions if there are any besides "Everyone" group. By default permissions 
    are not preserved, so after script ran succesfully only group which has SMB permissions to all non system shared folders 
    is going to be "Authenticated Users" and permissions level is "full". 
    
.EXAMPLE
    PS .\Remove-EveryOneGroupFromShares.ps1 -csvfile "C:\Temp\shares.csv" -PreserveCurrentPermissions
    Sets new permissions for all computers provided in "C:\Temp\shares.csv" preserving current SMB permissions.
.EXAMPLE
    PS .\Remove-EveryOneGroupFromShares.ps1 -csvfile "shares.csv"
    Sets new permissions for all computers provided in "shares.csv" which is located in the same folder 
    script ran from, replacing current SMB permissions.

.NOTES
    Author: Alex Chaika
    Date:   Oct 19, 2020 
    
.LINK
    https://github.com/achaika80/Powershell/tree/master/SharePermissions
   
#>


[cmdletbinding()]
    Param([Parameter(Mandatory=$true)]$csvfile, 
    [switch]$PreserveCurrentPermissions)

$PathToFiles = Split-Path -Parent $PSCommandPath

#setting path to the csv file to the current folder if path hasn't been provided

if($csvfile -notmatch '\\'){
    $csvfile = "$PathToFiles\$csvfile"
}



#function to get every non system used share

function Enumerate-Shares{
    [cmdletbinding()]
    Param($Computer)

    try{

        $shares = Get-WmiObject -class Win32_Share -ComputerName $Computer -ErrorAction Stop | ? {$_.type -eq 0} 

        return $shares
    }
    catch{
        
        Write-Host "Can't connect to $Computer`n" -ForegroundColor Yellow
        Write-Report -Computer $Computer -share "All" -message "Failed"
    }
}

#function to remove Everyone and add Authenticated Users to the share

function Set-SharePermissions{
    [cmdletbinding()]
    Param($Computer, $shares, [switch]$PreserveCurrentPermissions)

    foreach($share in $shares){
        Write-Host "Working on $Computer and $($share.name) share`n" -ForegroundColor Green

        #getting share permissions

        try{
            $ErrorActionPreference = "Stop"
            $setting = get-wmiobject -Class Win32_LogicalShareSecuritySetting -filter "Name='$($share.name)'" `
                -ComputerName $Computer
            $descriptor = $setting.GetSecurityDescriptor().descriptor

            #creating security descriptor trustee and ACE for Authenticated Users

            $sd = ([WMIClass] “\\$Computer\root\cimv2:Win32_SecurityDescriptor”).CreateInstance()
            $ACE = ([WMIClass] “\\$Computer\root\cimv2:Win32_ACE”).CreateInstance()
            $Trustee = ([WMIClass] “\\$Computer\root\cimv2:Win32_Trustee”).CreateInstance()
            $Trustee.Name = “Authenticated Users”
            $Trustee.Domain = “NT AUTHORITY”
            $Trustee.SID = @(1, 1, 0, 0, 0, 0, 0, 5, 11, 0, 0, 0)
            $ace.AccessMask = 2032127
            $ace.AceFlags = 4
            $ace.AceType = 0
            $ACE.Trustee = $Trustee

            #applying new descriptor to the DACL by replacing current permissions

            if(!($PreserveCurrentPermissions)){
                $descriptor.DACL = $ACE.psObject.BaseObject
                $null = $setting.SetSecurityDescriptor($descriptor)
            }

            #adding new descriptor to the DACL preserving current permissions

            else{
            
                $sd.DACL = $descriptor.DACL

                $descriptor.DACL = $ACE.psObject.BaseObject

                $revised = $sd.DACL | Where {$_.trustee.name -ne 'Everyone'}

                foreach ($acl in $revised){
                    $descriptor.DACL += $acl.psObject.BaseObject
                }
            
                $null = $setting.SetSecurityDescriptor($descriptor)
            }

        Write-Report -Computer $Computer -share $share.name -message "Success"
        Write-Host "Applied new permissions to $($share.name) share on $Computer`n" -ForegroundColor Green

        }
        catch{
            
            Write-Host "Failed to change permissions on $Computer $($share.name)`n" -ForegroundColor Yellow
            Write-Report -Computer $Computer -share $share.name -message "Failed"


                
        }
    }
}


function Write-Report{
    [cmdletbinding()]
    Param($Computer, $share, $message)

    $info = "" | select Computer, share, status

    $info.Computer = $Computer
    $info.share = $share
    $info.status = $message

    $global:report += $info


}


$csvdata = Import-Csv -Path $csvfile

$global:report = @()

foreach($Computer in $csvdata){
    $shares = Enumerate-Shares $Computer.Name
    if($shares){
        if($PreserveCurrentPermissions){
            Set-SharePermissions -shares $shares -Computer $Computer.Name -PreserveCurrentPermissions
        }
        else{
            Set-SharePermissions -shares $shares -Computer $Computer.Name
        }
    }
   
}

Write-Host "Batch is completed. Report file saved to $PathToFiles\Report.csv`n"

$report | Export-Csv -Path "$PathToFiles\Report.csv" -NoTypeInformation
