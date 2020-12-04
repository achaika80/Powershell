<#
.SYNOPSIS
    .
.DESCRIPTION
    Test azure load balancer (ar any load balancer) connection to particular port. Presumes that the port isn't configured on the enpoint
    VMs yet. To be able to test the endpoints it copies nginx portable to the endpoints changes its config to the specified port and starts it.
    have to be ran under the user account which has administrative permissions on the endpoint computers.
.PARAMETER ILBFrontEndIP
    This is IP address or DNS name resolvable to the IP of the load balancer.
.PARAMETER ILBFrontEndPort
    This is load balancer port which we ara going to test against.
.PARAMETER EndpointHostNames
    This is array of the endpoint host names.
.EXAMPLE
    PS .\Test-AzureILB-Endpoints.ps1 -ILBFrontEndIP 10.10.50.49 -EndpointHostNames TESTVM01,TESTVM02 -ILBFrontEndPort 8642
    Tests 10.10.50.49:8642 by making sure that TESTVM01,TESTVM02 have nginx listening on the port 8642 
.NOTES
    Author: Alex Chaika
    Date:   Dec 4, 2020 
    
.LINK
    https://github.com/achaika80/Powershell/tree/master/TestLoadbalancer
   
#>


[cmdletbinding()]
    Param([Parameter(Mandatory=$true)]$ILBFrontEndIP,
          [Parameter(Mandatory=$true)]$ILBFrontEndPort,
          [Parameter(Mandatory=$true)]$EndpointHostNames
          )

function CopyFiles{
    [cmdletbinding()]
    Param($EndpointHostNames)
    Write-Host "`nCopying nginx files to the endpoints"
    foreach($Endpoint in $EndpointHostNames){
         if(-not (Test-path "\\$Endpoint\c$\TEMP\nginx-1.18.0")){
             md -Path "\\$Endpoint\c$\TEMP\nginx-1.18.0"
         }
         Copy-Item -Path "\\server\share\NGINX\nginx-1.18.0\*" -Destination "\\$Endpoint\c$\TEMP\nginx-1.18.0" -Force -Recurse # -Path needs to be replaced by the path to the fileshere with nginx files 
    }
}

function ChangePort{
    [cmdletbinding()]
    Param($EndpointHostNames,
          $ILBFrontEndPort)
    Write-Host "`nConfiguring nginx on the endpoints"
    foreach($Endpoint in $EndpointHostNames){
         $file = "\\$Endpoint\c$\TEMP\nginx-1.18.0\conf\nginx.conf"
         $regex = 'listen       80;'
         (Get-Content $file) -replace $regex, "listen       $ILBFrontEndPort;" | Set-Content $file

    }
}

function Start-Nginx{
    [cmdletbinding()]
    Param($EndpointHostNames)
    Write-Host "`nStarting nginx on the endpoints"
    foreach($Endpoint in $EndpointHostNames){
        $s = New-PSSession -ComputerName $Endpoint
        Invoke-Command -Session $s -ScriptBlock{
            Set-Location C:\TEMP\nginx-1.18.0
            Start-Process nginx.exe 
       }
    }

    
}

function Test-ILB{
    [cmdletbinding()]
    Param($ILBFrontEndIP,
          $ILBFrontEndPort)
    Write-Host "`nTesting connection"
    if((Test-NetConnection -ComputerName $ILBFrontEndIP -Port $ILBFrontEndPort).TcpTestSucceeded){
        Write-Host "`nILB Connection to $ILBFrontEndIP port: $ILBFrontEndPort succesfull!" -ForegroundColor Green
    }
    else{
        Write-Host "`nILB Connection to $ILBFrontEndIP port: $ILBFrontEndPort failed!" -ForegroundColor Red
    }

}

function Stop-Nginx{
    [cmdletbinding()]
    Param($EndpointHostNames)
    Write-Host "`nStopping nginx on the endpoints"
    foreach($Endpoint in $EndpointHostNames){
        $s = New-PSSession -ComputerName $Endpoint
        Invoke-Command -Session $s -ScriptBlock{
            Get-Process nginx | Stop-Process
       }
    }
 }



CopyFiles $EndpointHostNames

ChangePort -EndpointHostNames $EndpointHostNames -ILBFrontEndPort $ILBFrontEndPort

Start-Nginx $EndpointHostNames

sleep 2

Test-ILB -ILBFrontEndIP $ILBFrontEndIP -ILBFrontEndPort $ILBFrontEndPort

Stop-Nginx $EndpointHostNames
