<#
.NOTES
	Author: Nan Zhang
	  Date: April 10, 2019
.SYNOPSIS
	Print out the IB network tree
.DESCRIPTION
	Print out the IB network tree
	The network data is obtained a first time and then it is saved (cached) in two variables ibnetwork (for networks) and ibnetworkcontainers (for network containers). To get the latest network information from the Infoblox grid, use the -refresh parameter.
.PARAMETER ipamhost
	IPAM host containing the network information
.PARAMETER credential
	Credential to connect to ipam host
.PARAMETER credentialFile
	Credential file containing the credential
.PARAMETER network
	Network to search
.PARAMETER refresh
	Refresh the network and network containers from Infoblox
.EXAMPLE
	 .\get-IBNetworkInfo.ps1 -search -network "10.10.240"
	search for network containers or networks information that contains '10.10.240'.
.EXAMPLE
	.\get-IBNetworkInfo.ps1 -print -network "10.10.240.0/21"
	10.10.240.0/21
			10.10.241.0/28
			10.10.242.0/24
					10.10.242.0/27
					10.10.242.10/28
	Print out the subnet tree for the network 10.10.240.0/21.
.EXAMPLE
	 .\get-IBNetworkInfo.ps1 -search -network "10.10.240" -refresh -ipamhost ib.xxxx.com -credential (Get-Credential)
	Refresh the network/network containers information and print out the tree for the network '10.10.240' and supply explicit credential.
.EXAMPLE
	 .\get-IBNetworkInfo.ps1 -print -network "10.10.240.0/21" -refresh -ipamhost ib.xxxx.com -credential (Get-Credential)
	Refresh the network/network containers information and print out the tree for the network '10.10.240.0/21'.
.LINK
 	https://www.linkedin.com/in/nan-zhang-60425223
#>
#Requires -Modules Posh-IBWAPI
[cmdletbinding()]
param (
	[Parameter(ParameterSetName='Print')]
	[Parameter(ParameterSetName='Search')]
	[string] $network,

	[Parameter(ParameterSetName='Print')]
	[switch] $print,
	[Parameter(ParameterSetName='Search')]
	[switch] $search,

	[Parameter(ParameterSetName='Search')]
	[int] $maxResultCount = 20,

	[string] $ipamhost = "ib.xxxx.com",
	[pscredential] $credential,
	[string] $credentialFile = $env:userprofile + "\cred-Infoblox.xml",

	[switch] $refresh = $false
)

################################################################################
# Print the network tree 
################################################################################
function print-IBNetwork {
	param (
		[string] $network,
		[int] $numTabs
	)

	$nwResult  = $global:ibnetworks | where-object { $_.network -eq "$network" }
	$nwcResult = $global:ibnetworkcontainers | where-object { $_.network -eq "$network" }

	if ( $null -ne $nwResult ) {
		$tabs = "`t" * $numTabs
		write-host "$tabs$($nwResult.network)"
	} elseif ( $null -ne $nwcResult ) {
		$tabs = "`t" * $numTabs
		write-host "$tabs$($nwcResult.network)"

		$subNetworks   = $global:ibnetworks |  where-object { $_.network_container -eq "$network" }
		foreach ( $subNetwork in &{$subNetworks |Sort-Object network} ) {
			$tabs = "`t" * ($numTabs +1)
			write-host "$tabs$($subNetwork.network)"
		}

		$subContainers = $global:ibnetworkcontainers |  where-object { $_.network_container -eq "$network" }
		foreach ( $subcontainer in &{$subContainers | Sort-Object network} ){
			print-IBNetwork $subcontainer.network ($numTabs + 1)
		}
	}
}

################################################################################
# Show the search result
################################################################################
function show-Result {
	param (
		$records,
		$typeMessage
	)
	
	switch ($typeMessage) {
		"network" {
			write-host -fore yellow "------------- $typeMessage -------------" 
		}

		"network containers" {
			write-host -fore yellow "------------- $typeMessage -------------" 
		}
	}

	$records | select-object network, network_container
}

##
# start of script
##
if ( -not (get-variable -name ibnetworks -ea silentlycontinue) -or -not (get-variable -name ibnetworkcontainers -ea silentlycontinue) -or $refresh ) {
	if ( $null -ne $credential ) {
		if ( test-path -type leaf $credentialFile ) {
			$credential = import-clixml $credentialFile
		} else {
			$credential = get-credential
		}
	}
	if ( -not (get-IBWAPIConfig) ) {
		set-IBWAPIConfig -WAPIHost $ipamhost -WAPIVersion 2.1 -credential $credential -IgnoreCertificateValidation
	}


	write-host -fore yellow "Loading network information from IPAM"
	$global:ibnetworks = Get-IBObject -ObjectType 'network' -ReturnFields "network_container" -ReturnBaseFields

	write-host -fore yellow "Loading network container information from IPAM"
	$global:ibnetworkcontainers = Get-IBObject -ObjectType 'networkcontainer' -ReturnFields 'network_container'  -ReturnBaseFields
}

try { 
	switch ( $PsCmdLet.ParameterSetName ) { 
		"Search" {
			$result = @($global:ibnetworks | Where-Object { $_.network -match "^$network" })

			if ( $result.count -gt 0 ) {
				if ( $result.count -gt $maxResultCount ) {
					write-host "There are $($result.count) networks in the result."
					$response = read-host "Are you sure you want see all of them? (y/n)"
					if ( $response -match '^[Yy]$' ) {
						show-Result $result "network"
					}
				} else {
					show-Result $result "network"
				}
			} else {
				write-host -fore yellow "There are no matching networks."
			}
			
			$result = @($global:ibnetworkcontainers | Where-Object { $_.network -match "^$network" })
			if ( $result.count -gt 0 ) {
				if ( $result.count -gt $maxResultCount ) {
					write-host "There are $($result.count) network containers in the result."
					$response = read-host "Are you sure you want see all of them? (y/n)"
					if ( $reponse -match '^[Yy]$' ) {
						show-Result $result "network containers"
					}
				} else {
					show-Result $result "network containers"
				}
			} else {
				write-host -fore yellow "There are no matching network containers."
			}

			break
		}

		"Print" {

			print-IBNetwork $network 0
		}
	}
} catch {
	$errmsg = $error[0].Exception.Message

	write-host "Error: [$errmsg]"
}
