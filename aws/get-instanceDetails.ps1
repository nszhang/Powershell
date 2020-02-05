<#
.NOTES
	Author: Nan Zhang
      Date: 2018-12-13

	2019-12-16: Nan Zhang
		* Add key name
	2019-07-19: Nan Zhang
		* add profile as a parameter (in a splat hash)
	2019-07-19: Nan Zhang
		* Add field to gauge the datetime the instance was created.
.SYNOPSIS
	Get more detailed EC2 instance information.
.DESCRIPTION
	Get more detailed EC2 instance information.
.PARAMETER instances
	Data type is the one returned from the get-ec2instance cmdlet .
.PARAMETER profilename
	The AWS profile name where the instance resides in.
.EXAMPLE
	# login-AWS
	# . .\set-AWSRegion.ps1 -profile <profilename> -region <region>
	# get-ec2instance | .\get-instanceDetails.ps1

	Log in to a particular account and get the instance details. Sourcing
	the set-AWSRegion.ps1 is needed to get it attached to the account specified
	by the login-AWS function. Finally details of all the EC2 instances in this
	account.
.EXAMPLE
	# get-ec2instance -profile saml | .\get-instanceDetails.ps1 -profile saml
	
	Get all the details of all the instances in the profile saml.
.LINK
	https://www.linkedin.com/in/nan-zhang-60425223/
#>
#Requires -Module AWSPowerShell.NetCore
[cmdletbinding()]
param(
	[Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[Collections.Generic.List[Amazon.EC2.Model.Instance]] $instances,
	[Alias('profile')]
		[string] $profilename = 'saml',
	[string] $region = 'us-west-2'
)

begin {

	# record to contain the information.
	function new-Record {

#Name
#TEMPLATE_VERSION
#aws:cloudformation:logical-id
#aws:cloudformation:stack-id
#aws:cloudformation:stack-name
		return "" | Select-Object id, Name, type, bootDiskCreateTime, launchTime, systemStatus, `
			instanceStatus, platform, AMIName, imageName, iamprofile, keyname, dnsname, privateIP, publicIP, `
			state, rootDeviceName, blockDeviceDetails, SecurityGroups, subnetID, vpcID,  tagList
	}

	# get the detailed volume information
	#
	function get-VolumeInfo {
		param (
			$blockDevices
		)

		$blockDetails = @()
		foreach ( $bd in $blockDevices ) {
			$blockDetails += $bd.devicename + " : "	+ $bd.ebs.volumeid + ", " + $bd.ebs.attachtime + ", " + $bd.ebs.status
		}

		return $blockDetails
	}

	# Get the volume creation datetime
	function get-BootDiskCreateDate {
		param (
			$volumeid
		)

		return (Get-EC2Volume -VolumeId $volumeid @awsCmdParams).createTime
	}

	# Get the instance details
	#
	function get-InstanceInfo{
		param (
			$instance,
			$record
		)

		$record.id                 = $instance.InstanceId
		$record.Name               = ($instance.tags.getenumerator() | Where-Object {$_.key -eq 'Name'}).value
		$record.type               = $instance.InstanceType
		$record.systemStatus       = ($instance | get-ec2instancestatus @awsCmdParams).systemstatus.status.value
		$record.instanceStatus     = ($instance | get-ec2instancestatus @awsCmdParams).status.status.value
		$record.launchTime         = $instance.LaunchTime


		$record.platform           = $instance.platform
		$record.AMIName			   = ( get-ec2image -imageid $instance.imageid @awsCmdParams).name
		$record.iamprofile         = $( if ( $instance.IamInstanceProfile ) { $instance.IamInstanceProfile.arn } else { "" })
		$record.keyname            = $instance.keyname
		$record.dnsname            = $instance.PrivateDnsName
		$record.privateIP          = $instance.PrivateIpAddress
		$record.publicIP           = $instance.PublicIpAddress
		$record.state              = $instance.State.Name
		$record.rootDeviceName     = $instance.RootDeviceName
		$record.SecurityGroups     = $instance.SecurityGroups.GroupName -join ', '
		$record.subnetID           = $instance.SubnetId + " [" + $(get-ec2subnet -SubnetId $instance.SubnetId @awsCmdParams).cidrblock + "]"
		$record.vpcID              = $instance.VpcId + " [" + $(get-ec2vpc -VpcId $instance.vpnid @awsCmdParams).cidrblock + "]"
		$record.tagList           = ($instance.tags |  Select-Object  { $_.key + ' = ' + $_.value }) -join "`n"

		$blockdevices = get-volumeInfo $instance.blockdevicemappings
		$record.blockDeviceDetails = $blockdevices -join "`n"

		# ex. /dev/sda1 : vol-0bee355c41be7050d, 08/10/2018 15:06:36, attached
		# 	* Windows root disk is named /dev/sda1
		# 	* Non-Windows root disk is name /dev/xvda
		$volumeid = (((($blockDevices | Where-Object  { $_ -match '(sda1|xvda)' }) -split ':')[1] -split ', ')[0]).trim()
		write-verbose "volume id: [$volumeid]"
		if ( $null -ne $volumeid -and $volumeid -match '^vol-' ) {
			$record.bootDiskCreateTime = get-BootDiskCreateDate $volumeid
		}

		return $record
	}

	$awsCmdParams = @{}
	if ( $profilename.length -ne 0 ) {
		$awsCmdParams['profilename'] = $profilename	
	}
	if ( $region.length -ne 0 ) {
		$awsCmdParams['region'] = $region
	}
	
}

process {
	foreach ( $instance in $instances ) {
		write-debug "Using name"
		if ( $instances.count -gt 0 ) {
			foreach ( $instance in $instances ) {
				$record = new-Record
				$record = get-InstanceInfo $instance $record
			}
		} else {
			write-host -fore yellow "instance name [$name] not found."
			$record = new-Record
			$record.status = "Not found"
		}
		$record
	}
}

end {}