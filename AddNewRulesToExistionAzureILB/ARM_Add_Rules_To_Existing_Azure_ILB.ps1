#creating hashtables for new rules properties

$rulesArray = @{"port" = "9092"; 
                "probePath" = "/swagger";
                "probeProtocol" = "http";
                "ruleProtocol" = "TCP";
                "idleTimeOutMin" = 15;
                "intervalSec" = 15;
                "numberOfProbes"= 2},
                @{"port" = "9094"; 
                "probePath" = "/swagger";
                "probeProtocol" = "http";
                "ruleProtocol" = "TCP";
                "idleTimeOutMin" = 15;
                "intervalSec" = 15;
                "numberOfProbes"= 2},
                @{"port" = "9096"; 
                "probePath" = "/swagger";
                "probeProtocol" = "http";
                "ruleProtocol" = "TCP";
                "idleTimeOutMin" = 15;
                "intervalSec" = 15;
                "numberOfProbes"= 2}

$VMNames = "RPS-TESTVM01","RPS-TESTVM02"

#**********Automation region*****************
#Do not change unless script logic needs to be updated

$vm = get-AzVM | ?{$_.Name -eq $VMNames[0]}

$NetIntName = $vm.NetworkProfile.NetworkInterfaces[0].Id | Split-Path -Leaf
$NetInt = Get-AzNetworkInterface -Name $NetIntName -ResourceGroupName $vm.ResourceGroupName

$LBName = ($NetInt.IpConfigurations | select -ExpandProperty LoadBalancerBackendAddressPools)[0].id.Split('/')[8]

#iterating through array of hashtables and creating probes, rules and backend pools for ILB

foreach($record in $rulesArray){
    $slb = Get-AzLoadBalancer | ?{$_.Name -eq $LBName}
    $slb | Add-AzLoadBalancerBackendAddressPoolConfig -Name "$LBName-BackEnd-$($record.Item("port"))" `
         | Set-AzLoadBalancer
    $slb | Add-AzLoadBalancerProbeConfig -Name "$LBName-Probe-$($record.Item("port"))" `
         -Protocol $record.Item("probeProtocol") -Port $record.Item("port") `
         -IntervalInSeconds $record.Item("intervalSec") -ProbeCount $record.Item("numberOfProbes") `
         -RequestPath $record.Item("probePath") 
         | Set-AzLoadBalancer
    $ProbeId = ($slb | get-AzLoadBalancerProbeConfig -Name "$LBName-Probe-$($record.Item("port"))").Id
    $FrEndId = ($slb | Get-AzLoadBalancerFrontendIpConfig).Id
    $BkEndId = ($slb | Get-AzLoadBalancerBackendAddressPoolConfig -Name "$LBName-BackEnd-$($record.Item("port"))").Id
    $BkEnd = $slb | Get-AzLoadBalancerBackendAddressPoolConfig
    $slb | Add-AzLoadBalancerRuleConfig -Name "$LBName-Rule-$($record.Item("port"))" -ProbeId $ProbeId `
          -BackendAddressPoolId $BkEndId -FrontendIpConfigurationId $FrEndId -Protocol $record.Item("ruleProtocol") `
          -FrontendPort $record.Item("port") -BackendPort $record.Item("port")
    $slb | Set-AzLoadBalancer
}

#getting updated ILB config

$slb = Get-AzLoadBalancer | ?{$_.Name -eq $LBName}
$BkEnd = $slb | Get-AzLoadBalancerBackendAddressPoolConfig

#iterating through VMs in the VM array and assigning new ILB config to each VMs NIC

foreach ($vmName in $VMNames) {
    $vm = get-AzVm | ?{$_.Name -eq $vmName}
    $NetIntName = $vm.NetworkProfile.NetworkInterfaces[0].Id | Split-Path -Leaf
    $NetInt = Get-AzNetworkInterface -Name $NetIntName -ResourceGroupName $vm.ResourceGroupName
    $NetInt.IpConfigurations[0].LoadBalancerBackendAddressPools=$BkEnd
    Set-AzNetworkInterface -NetworkInterface $NetInt
}
