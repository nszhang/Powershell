<#
.NOTES
	Author: Nan Zhang
	  Date: 2019-07-09

.SYNOPSIS
	Set zone associations for IB networks.
.DESCRIPTION
	Set zone associations for IB networks.

	This script assumes that you have IB settings configured before running it. If not, you can use the set-IBWAPIConfig cmdlet to set it, like so:
		# Set-IBWAPIConfig -WAPIHost ib.mycompany.com -WAPIVersion 2.9 -Credential (import-clixml ~\cred-Infoblox.xml) -IgnoreCertificateValidation

	With this configured, there is no need to pass in the access parameters to get/set data from IB.
.PARAMETER subnet
	The subnet to associate the new zones to. The subnet should include the cidr.
.PARAMETER zones
	The zones to associate to the subnet. The pre-existing zones are kept.

	The parameter is a list of pscustomobject that defines the zone information and it includes these three fields:
		1. fqdn 		- name of the zone
		2. is_default 	- True or False
		3. view			- DNS view

	Example:
		$zonesToAssociate = @(
			[PSCustomObject] @{
				fqdn       = 'mycompany.com'
				is_default = $false
				view       = 'Int'
			},
			[PSCustomObject] @{
				fqdn       = 'mycompany.com'
				is_default = $true
				view       = 'Ext'
			}
		)
.EXAMPLE
	# $zonesToAssociate  = @(
		[PSCustomObject] @{
			fqdn       = 'mycompany.com'
			is_default = $false
			view       = 'Int'
		},
		[PSCustomObject] @{
			fqdn       = 'mycompany.com'
			is_default = $true
			view       = 'Ext'
		}
	)
	# $result = .\set-IBZoneAssociations.ps1 -subnet  "5.3.0.0/14" -zones $zonesToAssociate

	Add/Modify the zone associations for the network 5.3.0.0/14.
.LINK
 	https://www.linkedin.com/in/nan-zhang-60425223
#>
#Requires -Modules Posh-IBWAPI
[cmdletbinding()]
param (
	[Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
	[Alias('network')]
	[string] $subnet,
	
	# record to change
	#
	[object[]] $zones
)

begin {
		# Check the zones to associate that it has at most one default
		#
		$zoneDefaultCount = ($zonesToAssociate | Where-Object { $_.default -eq $true}).count 
		if ( $zoneDefaultCount -gt 1 ) {
			write-host "The new zone associations has more than 1 default. It can only have 1 or none. Please fix it before trying to run the script again"

			continue
		}

		function new-record {
			return "" | Select-Object network, before_za, after_za, output, status
		}
}

process {
	try {
		$record = new-record

		$record.network = $subnet

		$res = get-ibobject -objecttype network -Filters "network=$subnet" -ReturnFields 'zone_associations' -ea stop

		write-host "Before: "
		write-host $($res.zone_associations | Format-Table -auto | out-string)
		$record.before_za = $res.zone_associations | convertto-json -compress

		if ( $res.zone_associations.count -gt 0 ) {
			# Check for the default setting first
			#
			# The ones from zone associations is sure to have at most one default.
			#
			#  * If the existing zone asociations has a default and the zones
			#	to associate also has at least one, set the existing default to
			#	False
			#
			$defaultZone = @($res.zone_associations | Where-Object { $_.is_default -eq $true })
			if ( $defaultZone.count -eq 1 ) {
				if ( ($zones | Where-Object{ $_.is_default -eq $true }).count -ge 1 ) {
					$defaultZone.is_default = $false
				}
			}
		}

		$newZoneAssociations = $res.zone_associations

		$zones | Foreach-Object {
			$za = $_

			$searchZoneAssociation = @($newZoneAssociations | Where-Object{ ($_.fqdn -eq $za.fqdn) -and ($_.view -eq $za.view) })
			$searchZoneAssociationCount = $searchZoneAssociation.Count
			if ( $searchZoneAssociationCount -eq 1 ) {
				write-host "Changing default [$($za.fqdn)] [$($za.view)] [$($za.is_default)]"
				$searchZoneAssociation[0].is_default = $za.is_default
			} else {
				if ( $searchZoneAssociationCount -eq 0 ) {
					$newZoneAssociations += $za
				} else {
					write-host -fore yellow "Found more than 1 record [$searchZoneAssociationCount] with zone [$($za.fqdn)] and [$($za.view)]"
				}
			}
		}

		$res.zone_associations = $newZoneAssociations

		$record.after_za = $res.zone_associations | convertto-json -compress
		$record.after_za = $res.zone_associations | convertto-json -compress

		write-host "After: "
		write-host $($res.zone_associations | Format-Table -auto | out-string)

		$record

		$record.output = $res | set-ibobject
		if ( $? ) {
			$record.status = "Completed"	
		} else {
			$record.status = "Failed"	
		}
	} catch {
		$errmsg= $error[0].Exception.Message

		write-host "Error [$subnet]: $errmsg"
	}
}
