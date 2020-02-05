<#
.Notes
	Author:	Nan Zhang
	Date:	April 6, 2008

	Sources:
	1) WMI Ping status
		http://www.winstructor.com/articles/windows-powershell/ping.htm
	2) Get-WMIObject bug
		http://blogs.msdn.com/powershell/archive/2008/08/12/some-wmi-instances-can-have-their-first-method-call-fail-and-get-member-not-work-in-powershell-v1.aspx

	May-26-2016: Nan Zhang (NSZ11)
		* Bugfix: The computer OU Location search uses the actual computer domain now.

	Aug-24-2015: Nan Zhang (NSZ10)
		* Added Product ID information.

	Jul-15-2015: Nan Zhang (NSZ09)
		* Added CPU information

	Jun-26-2015: Nan Zhang (NSZ08)
		* Added available memory information

	Jun-17-2015: Nan Zhang (NSZ07)
		* Fix up a bug in the get-ComputerOULocation function.
			* The distinguishname property has a capital n in the 'name'. It
			* needs to be all in lower case.

	Jun-04-2015: Nan Zhang (NSZ06)
		* Add timezone information

	Jun-03-2015: Nan Zhang (NSZ05)
		* Using win32_volume instead of win32_logicaldisk to get the disk
		* information, the former includes all of the disks, including the ones
		* that are mount under any disk drive.

	Dec-28-2012: Nan Zhang (NSZ04)
		* Added RAID and physical disk drive information
		* Sources: 
			1. HP Insight Management WBEM Proviers 2.8, Page 272
				URL: http://bizsupport2.austin.hp.com/bc/docs/support/SupportManual/c02777114/c02777114.pdf

	Dec-27-2012: Nan Zhang (NSZ03)
		* Added a check for power supply.
		* RAID battery status
		* Source: http://h10032.www1.hp.com/ctg/Manual/c03004638.pdf

	Jul-16-2012: Nan Zhang 	(NSZ02)
		* Added OS "Install Date" property to the output.

	Sep-01-2011:	Nan Zhang
		* Added memory dimm information, as an option to show.

	Nov-26-2008: NSZ01
		* Added the -ErrorAction to the get-wmiobject call to silent the any error messages

	Aug-22-2008: 
		* Check for credentials.
		* Added UPTime

.SYNOPSIS
	Get common computer information and display on the console.
.DESCRIPTION
	Get common computer information and display on the console.

	If the computer contains HP hardware information, it will grab the hardware specific information, like 
		1. RAM (size and slot) 
		2. RAID
		3. Disk drives
		4. Power supply
.PARAMETER computer
		List of computer name to query.
.PARAMETER tableFormat
		Type: Switch. Default is true.
		
		Shows the disk information in table format. This is only applicable when the -showdisk switch is true.
.PARAMETER verbose
		Type: Switch. Default is false. 
		
		Shows both memory dimm configuration and physical disk information.
.PARAMETER showdisk
		Type: Switch. Default is false.
		
		Shows physical disk information.
.PARAMETER showmem
		Type: Switch. Default is false.
		
		Shows memory dimm configuration information.
.PARAMETER showall
		Type: Switch. Default is false.
		
		Includes both raid/power/memory/disk information if it has HP hardware.
.PARAMETER showOULocation
		Type: Switch. Default is false. 
		
		Shows the OU location of the computer.
.PARAMETER showReservePart
		Type: Switch. Default is false. 
		
		Shows the reserve partition.
.PARAMETER reportMode
		Type: Switch. Default is false.
		
		Shows the result as psobjects.
.EXAMPLE
	.\get-ComputerInfo.ps1 computer001

	Get system information from the computer computer001.
.EXAMPLE
	.\get-ComputerInfo.ps1 -computer computer001

	Get system information from the computer computer001 and show memory dimm and physical disk information.
.EXAMPLE
	.\get-ComputerInfo.ps1 -computer computer001 -showdisk

	Get system information from the computer computer001 with its physical disks and show them.
.EXAMPLE
	gc server-list.txt | .\get-ComputerInfo.ps1 -showall

	Get the computer information and show all available information (including memory and disks and OU Location)
.LINK
	https://www.linkedin.com/in/nan-zhang-60425223/
#>
[cmdletBinding()]
param ( 
	[Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyname=$True, Mandatory=$True)] 
	[Alias('name','computername')]
		[string[]] $computer,	# computer
	[PSCredential] $credential,				# credential 
	[switch] $showmem  = $false,			# show memory dimm information
	[switch] $showdisk = $false,			# show physical disk information
	[switch] $showOULocation = $false,		# show the computer OU location
	[switch] $tableformat = $true,			# show phyiscal disk information
	[switch] $showall = $false,
	[switch] $showReservePart = $false,
	[switch] $reportmode = $false
)

begin {
	# Time variables
	#
	$SEC_PER_DAY  = 60 * 60 * 24
	$SEC_PER_HOUR = 60 * 60
	$SEC_PER_MIN  = 60

	#################################################################################
	#
	# Function Definitions
	#
	#################################################################################

	#################################################################################
	# Create record to contain the OS information
	#################################################################################
	function new-Record {
		return "" | select-object  Name, `
							Domain, `
							Model, `
							OS, `
							CPU, `
							Memory, `
							CurrentUser, `
							TimeZone, `
							SerialNumber, `
							InstallDate, `
							UpTime, `
							DriveInfo, `
							ROMs,
							Comment
	}

	################################################################################
	#
	# Checks to see if a server is online or not.
	#
	# Arguments: 
	#	1. Computer name
	#
	# Return values:
	#	1. Status		- True or False
	#	2. Status code	- If (1) is false, a status code is provided.
	# 
	################################################################################
	function Ping-Machine {
		[cmdletbinding()]
		param (
			[Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
			$machine,
			[int32] $timeout = 2000          # default timeout is 1000
		)

		begin { }

		process {
			$filterString = "address='" + $machine + "' and timeout=$timeout"

			try { 
				$pingInfo = get-wmiobject -class win32_pingstatus -filter $filterString -errorAction silentlyContinue

				# Check if the query succeeded or not
				#
				if ( $? ) {
					if ( $pingInfo.StatusCode -eq 0 ) {	# check the return status
						return $true,"Success"
					} else {
						$status = $machine + " is not available."

						if ($null -ne $pingInfo.StatusCode ) {
							$status += " Ping error: "
							switch ($pingInfo.StatusCode ) {
								11001	   { $status += "Buffer Too Small" }
								11002	   { $status += "Destination Net Unreachable" }
								11003	   { $status += "Destination Host Unreachable" }
								11004	   { $status += "Destination Protocol Unreachable" }
								11005	   { $status += "Destination Port Unreachable" }
								11006	   { $status += "No Resources" }
								11007	   { $status += "Bad Option" }
								11008	   { $status += "Hardware Error" }
								11009	   { $status += "Packet Too Big" }
								11010	   { $status += "Request Timed Out" }
								11011	   { $status += "Bad Request" }
								11012	   { $status += "Bad Route" }
								11013	   { $status += "TimeToLive Expired Transit" }
								11014	   { $status += "TimeToLive Expired Reassembly" }
								11015	   { $status += "Parameter Problem" }
								11016	   { $status += "Source Quench" }
								11017	   { $status += "Option Too Big" }
								11018	   { $status += "Bad Destination" }
								11032	   { $status += "Negotiating IPSEC" }
								11050	   { $status += "General Failure" }
								default	   { $status += "Unknown(1)" }
							}
						} else {
							if ( $null -ne $pingInfo.ResolveAddressNames -and
								$pingInfo.ResolveAddressNames -eq $false 	) {
								$status = "Unable to resolve hostname"
							} else {
								$status = "Unknown(2)"
							}
						}
						return $false, $status
					}
				} else {
					$errmsg = Parse-ExceptionMessage $error[0].Exception.Message

					return $false,$errmsg
				}
			} catch {
				$errmsg = Parse-ExceptionMessage $error[0].Exception.Message

				return $false,$errmsg
			}
		}

		end {}
	}

	#################################################################################
	#
	# Show Memory DIMM information
	#
	#################################################################################
	function show-MemInfo
	{
		param (
			$computer,
			[PSCredential] $credential
		)

		if ( $credential ) {
			$wmiargs = @{
				computername = $computer
				credential   = $credential
			}
		} else {
			$wmiargs = @{
				computername = $computer
			}
		}

		# Show memory dimm if the user requests it.
		#
		# (ODD: When adding this expression to the function, the wmi query doesn't
		# return any results.)
		#

		# memory DIMM information
		#
		$dimmInfo = get-wmiobject @wmiargs -query "select devicelocator, capacity from Win32_PhysicalMemory" -ErrorAction silentlyContinue 

		if ( $null -ne $dimmInfo ) {
			write-host -fore yellow "`nMemory Dimm Information"
			write-host -fore yellow "-----------------------"
#                      "  1234567890123456789012345"
			write-host "  Dimm Name           Size (GB)"
			write-host "  ---------           ---------"
			foreach ( $dimm in $dimmInfo ) {
				$sizeInGB = $dimm.capacity / 1gb
				$str = "  {0,-20}" -f $dimm.devicelocator + "{0,9:n2}" -f $sizeInGB
				write-host $str
			}
		} else {
			write-host -fore red "  No Physical Dimm information available."
		}
	}

	#################################################################################
	# 
	# Returns True or False if the drive has paging file. The drive name needs to in the format "<letter>:"
	# 
	#################################################################################
	Function has-PageFile {
		param (
			$computer,
			$credential,
			$drivename
		)

		if ( $credential ) {
			$wmiargs = @{
				computername = $computer
				credential   = $credential
			}
		} else {
			$wmiargs = @{
				computername = $computer
			}
		}

		# If page file are
		try {
			# Try this location first.
			#
			$pagefileInfo = get-wmiobject @wmiargs -class win32_pagefile -erroraction silentlycontinue | select-object name

			# It appears that if the system is set to use 'system managed' the
			# win32_pagefile class would be empty, but its paging information can
			# be found in the win32_pagefileusage class.
			#
			if ( $null -eq $pageFileInfo ) {    
				$pagefileInfo = get-wmiobject @wmiargs -class win32_pagefileusage  -erroraction silentlycontinue | select-object name 

				if ( $null -ne $pageFileInfo ) {
					if ( $pageFileInfo.gettype().basetype.name -eq 'Array' ) {  # multiple page file
						foreach ( $pageFile in $pageFileInfo ) {
							$pagefileDrive = $pagefile.name -split '\\'

							if ( $pageFileDrive[0] -eq "$drivename" ) {
								return $true    
							}
						}
					} else { 
						$pagefileDrive = $pagefileInfo.name -split '\\'
						if ( $pageFileDrive[0] -eq "$drivename" ) {
							return $true    
						}
					}
				}
			} else {    # likely manual managed page file
				if ( $pageFileInfo.gettype().basetype.name -eq 'Array' ) {  # multiple page file
					foreach ( $pageFile in $pageFileInfo ) {
						$pagefileDrive = $pagefile.name -split '\\'

						if ( $pageFileDrive[0] -eq "$drivename" ) {
							return $true    
						}
					}
				} else {
					$pagefileDrive = $pagefileInfo.name -split '\\'

					if ( $pageFileDrive[0] -eq "$drivename" ) {
						return $true    
					}
				}
			}
		} catch {
			$errmsg = parse-ExceptionMessage $error[0].Exception.Message

			write-host -fore red "  Error(getPageFile): [$errmsg]"

			return $false
		}

		return $false
	}

	#################################################################################
	#
	# Show physical disk information (NSZ03)
	#
	#################################################################################
	function show-HDDInfo
	{
		param (
			$computer,
			$computersystem,
			$raidDiskInfo,
			$tableFormat
		)

		if ( $credential ) {
			$wmiargs = @{
				computername = $computer
				credential   = $credential
			}
		} else {
			$wmiargs = @{
				computername = $computer
			}
		}

		# Get Physical Disk drive information
		#
		if ( ($null -ne $computersystem)  -and ($computersystem.model -match 'proliant') -and ($null -ne $raidDiskInfo) ) {
			write-debug "Getting physical disk information"

			# Hard disk information
			#
			# Join fields between disk classes
			#	1. hpsa_diskdrive.systemname            <-> hpsa_arraysystem.name
			#	2. HPSA_DiskPhysicalPackage.ElementName <-> hpsa_diskdrive.elementname OR HPSA_DiskPhysicalPackage.Name <-> hpsa.diskdrive.elementname
			#	3. HPSA_DiskDrive.ElementName <-> HPSA_StorageExtent.elementname
			#
			# hpsa_diskdrive.elementname: 		Location (port,bay,box)
			# hpsa_diskdrive.operationstatus: 	Disk status (port,bay,box)
			# hpsa_diskdrive.name: 				HD Serial Number
			# HPSA_DiskPhysicalPackage.model: 	HD Model Number
			# hpsa_arraysystem.elementname: 	RAID Controller Name

			# Disk status 
			#
			$diskStatusHash = @{
				 0 = "Unknown";
				 2 = "OK";
				 5 = "Predictive Failure";
				 6 = "Error"
			}
			try {
				write-host -fore yellow "`nPhysical Disk Drive Information"
				write-host -fore yellow "-------------------------------"
				# We already have $raidDiskInfo for HPSA_ArraySystem
				#	> gwmi -namespace  root\HPQ -computer exmbx10a -query "select-object * from HPSA_arraysystem" | select-object  name, elementname
				# $raidDiskInfo
				write-debug "RAID disk information"
				$raidDiskInfoHash = @{}
				foreach ($rd in $raidDiskInfo ) {
					$raidDiskInfoHash[$rd.name] = $rd.elementname
				}

				write-debug "Physical disk information 1"
				# Get physical disk information
				#
				$physicalDiskMainInfo = get-wmiobject @wmiargs -namespace root\HPQ -query "select * from HPSA_DiskDrive"

				write-debug "Physical disk information 2"
				# Get the disk information that includes the disk model information
				#
				$physicalDiskSecondaryInfo = get-wmiobject @wmiargs -namespace root\HPQ -query "select name, model from HPSA_DiskPhysicalPackage"
				$physicalDiskInfoHash = @{}		# convert the data to a hash for easier name lookup below
				foreach ( $disk in $physicalDiskSecondaryInfo ) {
					$physicalDiskInfoHash[$disk.name] = $disk.model
				}

				write-debug "Physical disk size information"
				# Get disk size information
				#
				$diskDriveSizeInfo = get-wmiobject @wmiargs -namespace root\HPQ -query "select ElementName, blocksize, NumberOfBlocks from HPSA_StorageExtent"
				$diskDriveSizeHash = @{}
				foreach ( $disk in $diskDriveSizeInfo ) {
					$count++
					write-debug "   disk [$count] [$($disk.ElementName)]"
					$diskDriveSizeHash[$disk.ElementName] = [String]::Format("{0:0.00} GB", ($disk.blocksize * $disk.numberofblocks) / 1GB)
				}

				write-debug "Gather RAID disk"
				# Gather the disk information and show it
				#
				$diskInfoArray = @()
				$count = 0
				foreach ( $disk in $physicalDiskMainInfo ) {
					$count++
					write-debug "Get disk $count Information [$($disk.Elementname)]"
					$diskData = "" | select-object Controller, Location, Model, SerialNumber, Size, Type, Status, Speed

					$diskData.Location     = $disk.Elementname
					$diskData.SerialNumber = $disk.name
					$diskData.type         = $disk.Description
					$diskData.Speed        = $disk.DriveRotationalSpeed

					if ( $diskDriveSizeHash.contains($disk.elementname) ) {
						$diskData.Size = $diskDriveSizeHash[$disk.elementname]
					} else {
						$diskData.Size = "Unknown"
					}

					write-debug " Location:     [$($diskdata.Location)]"
					write-debug " SerialNumber: [$($diskdata.SerialNumber)]"
					write-debug " Type:         [$($diskdata.type)]"

					$tval = [int32] $disk.operationalstatus[0]
					$diskData.Status = $diskStatusHash[$tval]
					write-debug " Status:       [$($diskdata.Status)]"

					if ( $physicalDiskInfoHash.Contains($disk.elementname) ) {
						$diskData.Model = $physicalDiskInfoHash[$disk.elementname]
					} else {
						$diskData.Model = "Unknown"
					}
					write-debug " Model:        [$($diskdata.Model)]"

					if ( $raidDiskInfoHash.Contains($disk.systemname) ) {
						$diskData.Controller = $raidDiskInfoHash[$disk.systemname]
					} else {
						$diskData.Controller= "Unknown"
					}
					write-debug " Controller:   [$($diskdata.Controller)]"

					$diskInfoArray += $diskData

					write-debug " Record Count: [$($diskInfoArray.count)]"
				}

				# Return the disk information
				#
				if ( $tableFormat ) {
					$diskInfoArray | Sort-Object controller, location | select-object * | Format-Table -auto
				} else {
					$diskInfoArray | Sort-Object controller, location
				}
			} catch {
				$errmsg = parse-ExceptionMessage $error[0].Exception.Message

				write-host -fore red "Error: [$errmsg]"
			}
		}
	}

	#################################################################################
	#
	# Check tos see if Daylight Saving is enabled
	#
	#################################################################################
	function is-DaylightSavingsSettingOn
	{
		param (
			$timeZoneObject		# object from win32_timezone class
		)

		if ($timeZoneObject.DaylightDay         -eq 0 -and
			$timeZoneObject.DaylightDayOfWeek   -eq 0 -and
			$timeZoneObject.DaylightHour        -eq 0 -and
			$timeZoneObject.DaylightMillisecond -eq 0 -and
			$timeZoneObject.DaylightMinute      -eq 0 -and
			$timeZoneObject.DaylightMonth       -eq 0 -and
			$timeZoneObject.DaylightSecond      -eq 0 -and
			$timeZoneObject.DaylightYear        -eq 0 -and
			$timeZoneObject.StandardBias        -eq 0 -and
			$timeZoneObject.StandardDay         -eq 0 -and
			$timeZoneObject.StandardDayOfWeek   -eq 0 -and
			$timeZoneObject.StandardHour        -eq 0 -and
			$timeZoneObject.StandardMillisecond -eq 0 -and
			$timeZoneObject.StandardMinute      -eq 0 -and
			$timeZoneObject.StandardMonth       -eq 0 -and
			$timeZoneObject.StandardSecond      -eq 0 -and
			$timeZoneObject.StandardYear        -eq 0  ) {

			return $false
		} else {
			return $true
		}
	}

	#################################################################################
	#
	# Determine the computer OU location.
	#
	#################################################################################
	function get-ComputerOULocation
	{
		param (
			$computer,
			$domain		# NSZ11, add this parameter
		)

		try {
			$root = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$domain") 

			$searcher = New-Object System.DirectoryServices.DirectorySearcher($root) 
			$searcher.Filter = "(&(objectClass=computer)(name=$Computer))" 
			[System.DirectoryServices.SearchResult]$result = $searcher.FindOne() 

			if ( $null -ne $result ) {
				return $result.Properties["distinguishedname"] 	# NSZ07
			}
		} catch { 
			$errmsg = $error[0].Exception.Message

			write-host -fore yellow "Error: [$errmsg]"
		}

		return $null
	}

	#################################################################################
	#
	# Get server product ID for physical hardware only. - NSZ10
	#
	#################################################################################
	function get-PhysicalServerProductID
	{
		param (
			$computer,
			[PScredential] $credential
		)

		if ( $credential ) {
			$wmiargs = @{
				computername = $computer
				credential   = $credential
			}
		} else {
			$wmiargs = @{
				computername = $computer
			}
		}

		try {
			$result = get-wmiobject @wmiargs -class win32_computersystem | select-object -expandproperty oemstringarray

			foreach ( $line in $result ) {
				if ( $line -match '^Product ID' ) {
					return $line -replace '^Product ID:\s*', ''
				}
			}
		} catch {
			$errmsg = $error[0].Exception.Message

			write-host -fore yellow "Error: [$errmsg]"

			return $null
		}
	}

	################################################################################
	# NOT USED. 
	# 
	# Originally it was used to determine the volume id for EC2 instances
	# but the information returned by this function is only one of three types
	# of disk found in AWS.
	################################################################################
	function get-DiskDriveInfo {
		param (
			[string] $computer,
			[PSCredential] $credential
		)

		if ( $credential ) {
			$wmiargs = @{
				computername = $computer
				credential   = $credential
			}
		} else {
			$wmiargs = @{
				computername = $computer
			}
		}

		try { 
			$result = Get-WmiObject @wmiargs -class Win32_DiskDrive | Foreach-Object {
			  $disk = $_
			  $partitions = "ASSOCIATORS OF " +
							"{Win32_DiskDrive.DeviceID='$($disk.DeviceID)'} " +
							"WHERE AssocClass = Win32_DiskDriveToDiskPartition"
			  Get-WmiObject -computer $computer -Query $partitions | Foreach-Object {
					$partition = $_
					$drives = "ASSOCIATORS OF " +
							  "{Win32_DiskPartition.DeviceID='$($partition.DeviceID)'} " +
							  "WHERE AssocClass = Win32_LogicalDiskToPartition"
					Get-WmiObject @wmiargs -Query $drives | Foreach-Object {
						New-Object -Type PSCustomObject -Property @{
							Disk        = $disk.DeviceID
							DiskSize    = $disk.Size
							DiskModel   = $disk.Model
							Partition   = $partition.Name
							RawSize     = $partition.Size
							DriveLetter = $_.DeviceID
							VolumeName  = $_.VolumeName
							VolumeID    = $disk.serialNumber -replace "_[^ ]*$" -replace "vol", "vol-"
							Size        = $_.Size
							FreeSpace   = $_.FreeSpace
						}
					}
				}
			}
			return $result
		} catch {
			$errmsg = $error[0].Exception.Message

			write-host -fore red "Error: [$errmsg]"

			return $null
		}
	}

	#################################################################################
	#
	# This is the main function. It gathers and shows the computer system information.
	#
	#################################################################################
	function get-CompInfo
	{
		param (
			$computer,
			[PSCredential] $credential
		)

		if ( $credential ) {
			$wmiargs = @{
				computername = $computer
				credential   = $credential
			}
		} else {
			$wmiargs = @{
				computername = $computer
			}
		}

		# RAID disk status
		#
		$raidDiskStatusHash = @{
			0 = "Unknown";
			2 = "OK";
			3 = "Degrade";
			6 = "Error"
		}

		# Array battery status
		#	Source: http://h10032.www1.hp.com/ctg/Manual/c03004638.pdf
		#		Page: 32-33
		# Namespace: 	root\HPQ
		# Class: 		HPSA_ArrayController.BatteryStatus
		#
		$batteryStatusHash = @{
			0 = "Unknown";
			1 = "OK";
			2 = "Failed";
			3 = "Not Fully charged";
			4 = "Not Present"
		}

		# record to store the information
		#
		$record = new-Record
		$record.Name = $computer

		# Check to see if the server is pingable
		#
		$pingResult = ping-Machine $computer

		if ( $pingResult[0] ) {	# check the return status
			# This fails when the computer name is an IP address. But curiously
			# enough it works fine from the command line.
			#
			# NSZ01.
			#
			try {
				$computersystem = get-wmiobject @wmiargs -query "select * from win32_computersystem" -ErrorAction SilentlyContinue

				$win32bios = get-wmiobject @wmiargs -query "Select serialnumber from win32_bios" -ErrorAction SilentlyContinue | `
					select-object -first 1 serialnumber

				$osBit = get-wmiobject @wmiargs -query "select addressWidth from win32_Processor" -ErrorAction SilentlyContinue | Select-Object -first 1 addressWidth

				# NSZ05
				$disks = get-wmiobject @wmiargs -query "select driveletter, name, FreeSpace, capacity, drivetype from win32_volume" -ErrorAction silentlyContinue 

				# NSZ02
				$OS = get-wmiobject @wmiargs -query "select caption, OtherTypeDescription, CSDVersion, InstallDate, LastBootUpTime from win32_operatingsystem" -ErrorAction silentlyContinue

				$perf = get-wmiobject @wmiargs -query "select SystemUpTime from Win32_PerfFormattedData_PerfOS_System" -ErrorAction silentlyContinue

				# NSZ08
				$memInfo = get-wmiobject @wmiargs -query "select * from  Win32_PerfRawData_PerfOS_Memory" -ErrorAction silentlyContinue

				# NSZ06
				$timezoneInfo = get-wmiobject @wmiargs -query "select * from win32_timezone" -erroraction silentlyContinue

				# NSZ09
				$cpuInfo = get-wmiobject @wmiargs -query "select * from win32_processor" -erroraction silentlyContinue

				# volume ID for disk drive
				#$diskDriveInfo = get-diskDriveInfo -computer $computer
			} catch {
				write-host -fore red -nonewline "Error: "
				write-host -fore yellow "$($Error[0].Exception.Message)."
			}

			# Gather HP Hardware specific information
			#
			if ( ($null -ne $computersystem)  -and ($computersystem.model -match 'proliant') ) {
				#  Power suppply specific information
				#
				try { 
					 $PSInfo = get-wmiobject @wmiargs -namespace root\HPQ -query "select caption, description from HP_PowerSupply" -erroraction silentlycontinue
				} catch {
					$errmsg = parse-ExceptionMessage $error[0].Exception.Message
					write-host -fore red "Error: [$errmsg] [root\hpa\HPSA_PowerSupply query failure.]"
				}

				#  RAID accelerator battery specific information
				#
				#
				try { 
					 $raidBatteryInfo = get-wmiobject @wmiargs -namespace root\HPQ -query "select ElementName, BatteryStatus, CacheSerialNumber from HPSA_ArrayController" -erroraction silentlycontinue
				} catch {
					$errmsg = parse-ExceptionMessage $error[0].Exception.Message
					write-host -fore red "Error: [$errmsg] [root\hpa\HPSA_ArrayController query failure.]"
				}
				
				# Gather RAID Disk information
				#
				try {
					$raidDiskInfo = get-wmiobject @wmiargs -namespace root\hpq -query "select * from HPSA_ArraySystem" -erroraction silentlycontinue
				} catch {
					$errmsg = parse-ExceptionMessage $error[0].Exception.Message
					write-host -fore red "Error: [$errmsg] [root\hpa\HPSA_ArraySystem query failure.]"
				}
			}

			# Format the string for total memory.
			#
			$memInGB = "{0:0.00} GB" -f (([Int64] $computerSystem.TotalPhysicalMemory) / 1GB)

			# Memory information
			#
			if ( $null -ne $memInfo ) { # NSZ08
				$AvailableBytesInGB = "{0:0.00} GB" -f (([Int64] $memInfo.AvailableBytes)/1gb)
				$committedBytesinGB = "{0:0.00} GB" -f (($memInfo.CommittedBytes)/1gb)
				$commitLimitinGB    = "{0:0.00} GB" -f (($memInfo.CommitLimit)/1gb)
			}

			# Format the string for UpTime.
			#

			# Get the uptime in seconds
			#
			if ( $OS.caption -match '2000' ) {	# Win2K last boot time is not found in the Win32_PerfFormattedData_PerfOS_System class.
				write-debug "OS Last Bootup Time: [$($os.LastBootUpTime)]"

				try {
					$bootUpTime = [DateTime] ([wmi]'').ConvertToDateTime($os.LastBootUpTime)	# The offset time is wrong.
					$bootUpTime = $bootUpTime.addhours(6)		# Fudging b/c the value is 6 hours behind from what is known to be the correct time.
					$currDateTime = get-date
					$upTimeInSeconds = ( $currDateTime - $bootUpTime ).TotalSeconds
				} catch {
					$errmsg = parse-ExceptionMessage $error[0].Exception.Message

					write-host -fore red "Error: [$errmsg]"
				}
			} else {
				write-debug "OS Last Bootup Time: [$($os.LastBootUpTime)]"

				$uptimeInSeconds = $perf.SystemUpTime
			}

			# Boot time in seconds
			#
			$bootTime = (get-date).addSeconds(-$uptimeInSeconds)

			# Build the uptime string in days/hours/minutes/seconds
			#
			if ( $null -ne $uptimeInSeconds ) {
				while ( $uptimeInSeconds -gt $SEC_PER_MIN ) {
					if ( $uptimeInSeconds -ge $SEC_PER_DAY ) {
						$remainingSecs = $uptimeInSeconds % $SEC_PER_DAY

						$timeUnit = ($uptimeInSeconds - $remainingSecs ) / $SEC_PER_DAY

						$strTimeString += "{0:N0}" -f $timeUnit + " Days, "
						$uptimeInSeconds = $remainingSecs
					} elseif ( $uptimeInSeconds -ge $SEC_PER_HOUR ) {
						$remainingSecs = $uptimeInSeconds % $SEC_PER_HOUR

						$timeUnit = ($uptimeInSeconds - $remainingSecs ) / $SEC_PER_HOUR

						$strTimeString += "{0:N0}" -f $timeUnit + " Hours, "
						$uptimeInSeconds = $remainingSecs
					} else {
						$remainingSecs = $uptimeInSeconds % $SEC_PER_MIN

						$timeUnit = ($uptimeInSeconds - $remainingSecs ) / $SEC_PER_MIN

						$strTimeString += "{0:N0}" -f $timeUnit + " Minutes, "
						$uptimeInSeconds = $remainingSecs
					}
				}
				$uptimeInSeconds = [Int] $uptimeInSeconds		# Win2k gives fractional seconds, force it to be integer
				$strTimeString += "$uptimeInSeconds Seconds"

				# Get the last up time in date format.
				#
				$bootTime = "{0:yyyy/MM/dd hh:mm:ss tt zz}" -f $bootTime
			} else {
				$bootTime = $null
			}

			# The property InstallDate is a string. This uses an empty wmi class method CovnertToDateTime to convert it to DateTime. (NSZ02)
			#
			if ( $null -ne $os.installdate ) {
				# Handle this exception (generated by MEISSA as it was rebooting.)
				#
				#Exception calling "ConvertToDateTime" with "1" argument(s): "Exception calling "ToDateTime" with "1" argument(s): "Specified argu
				#ment was out of the range of valid values.
				#Parameter name: dmtfDate""
				try { 
					$installDate = "{0:yyyy/MM/dd hh:mm:ss z}" -f [DateTime] ([wmi]'').ConvertToDateTime($os.installdate)
				} catch {
					$installDate = $null
				}
			} else {
				$installDate = $null
			}

			# Set up CPU string - NSZ09
			#
			if ( $null -ne $cpuInfo ) { 
				if ( $cpuInfo -is "Array" ) {
					$cpuInfoString = "[" + $cpuInfo.count  + "] "
				} else {
					$cpuInfoString = "[1] "
				}
				$tmpString     = $cpuInfo | select-object -first 1 -expandproperty name 
				$cpuInfoString = $cpuInfoString + $tmpString -replace '  *', ' '
			} else {
				$cpuInfoString = "Unknown"
			}

			# Write the information to screen
			#
			write-host -fore yellow "-------------------------------------"
			write-host "Name         : " $computerSystem.Name
			write-host "Domain       : " $computerSystem.Domain
			# How OU location if asked
			#
			if ( $showOULocation -or $showall ) {
				# NSZ11
				$OU = get-ComputerOULocation $computerSystem.Name $computerSystem.Domain
				if ( $null -ne $OU ) {	
					write-host "OU Location  : " $OU
				} else {
					write-host "OU Location  : " "Not Found"
				}	
			}

			$record.Model            = $computerSystem.Model
			$record.Domain           = $computerSystem.Domain
			$record.OS               = "$($OS.caption) $($OS.OtherTypeDescription) $($OS.CSDVersion) [$($OsBit.AddressWidth) Bit]"
			$record.CPU              = $cpuInfoString
			$record.Memory           = "[$memInGB] [Available: $AvailableBytesInGB] [Committed: $committedBytesinGB]"
			$record.CurrentUser      = $computerSystem.Username
			$record.TimeZone         = $timezoneInfo.caption
			$record.SerialNumber     = $win32BIOS.SerialNumber
			$record.InstallDate      = $InstallDate
			$record.UpTime           = "$strTimeString [$bootTime]"

			$record.DriveInfo        = 
			$record.ROMs             =

			write-host "Model        : " $computerSystem.Model
			write-host "OS           :  $($OS.caption) $($OS.OtherTypeDescription) $($OS.CSDVersion) [$($OsBit.AddressWidth) Bit]"
			write-host "CPU          : " $cpuInfoString
			write-host -nonewline "Memory       :  $memInGB"
			# NSZ08
			write-host -nonewline "  |  Available: $AvailableBytesInGB"
			write-host -nonewline "  |  Committed: $committedBytesinGB"
			write-host "  |  Commit Limit: $commitLimitinGB"
			write-host "Current User : " $computerSystem.Username
			write-host -nonewline "Time Zone    : " $timezoneInfo.caption
			$dayLightSavingsStatus = is-DaylightSavingsSettingOn $timeZoneInfo
			if ( $dayLightSavingsStatus ) {
				write-host " [Daylight Savings enabled]"
			} else {
				write-host " [Daylight Savings disabled]"
			}
			write-host "Serial Number: " $win32BIOS.SerialNumber
			write-host "Install Date : " $InstallDate
			if ( $null -ne $bootTime ) {
				write-host "Up Time      :  $strTimeString ($bootTime)"
			} else {
				write-host "Up Time      :  Not available"
			}


			# Check Power supply and RAID battery information if it is a HP server
			#
			# NSZ03 (Check for HP hardware server)
			# This is assuming that the HP management agent is installed.
			#
			if ( ($null -ne $computersystem)  -and ($computersystem.model -match 'proliant') ) {
				# NSZ10
				$productID = get-PhysicalServerProductID $computer	
				if ( $null -ne $productID ) {
					write-host "Product ID   : " $productID
				} else {
					write-host "Product ID   : " "Unknown"
				}

				write-host -nonewline "Power Supply :  "
				# NSZ03: Power Supply status
				#
				if ( $null -ne $PSInfo ) {
					if ( $PSInfo.gettype().name -ne "String" ) {
						# Sort out the good and bad power supplies
						#
						foreach ( $psRecord in $PSInfo ) {
							$psNum = $psRecord.caption -replace 'Power Supply ', ''
							if ( $psRecord.description -match "Power Supply is operating properly." ) {
								$psGoodList += $psNum + ", "
							} else {
								$psBadList += $psNum + ", "
							}
						}
						if ( $null -ne $psGoodList ) {
							$psGoodList = $psGoodList -replace ', $', ''

							write-host -nonewline "Good: "
							write-host -nonewline "["
							write-host -nonewline -fore green "$psGoodList"
							write-host -nonewline "]"
						}
						if ( $null -ne $psBadList ) {
							$psBadList  = $psBadList -replace ', $', ''
							write-host -nonewline "; Bad: "
							write-host -nonewline "["
							write-host -nonewline -fore red " $psBadList"
							write-host -nonewline "]"
						}
						write-host
					} else {
						write-host $PSInfo
					}
				} else {
					write-host "Unknown"
				}

				# RAID Battery
				#
				write-host -nonewline "RAID Battery :  "
				if ( $null -ne $raidBatteryInfo ) {
					if ( $raidBatteryInfo.gettype().name -ne "String" ) {
						foreach ( $RBRecord in $raidBatteryInfo ) {
							if ($null -ne $RBStatusList -and $RBStatusList.length -gt 0 ) {
								write-host -nonewline "; "
							}

							$tvalue = [int32] $RBRecord.BatteryStatus
							$RBStatus = $batteryStatusHash[$tvalue]
							write-host -nonewline "$($RBRecord.ElementName) ["
							if ( $RBStatus -eq "OK" ) {
								write-host -nonewline -fore green $RBStatus
								write-host -nonewline "]"
							} else {
								if ( $RBStatus -match 'Failed' ) {
									write-host -nonewline -fore yellow "$RBStatus `(SN#: $($RBRecord.CacheSerialNumber)`)"
									write-host -nonewline "]"
								} else {
									write-host -nonewline -fore yellow $RBStatus
									write-host -nonewline "]"
								}
							}

							$RBStatusList += $RBRecord.ElementName + " [$RBStatus]; "
						}
						write-host
					} else {
						write-host $raidBatteryInfo
					}
				} else {
					write-host "Unknown"
				}

				# Check RAID disk and individual disk if necessary
				#
				write-host -nonewline "RAID Disk    :  "
				if ( ($null -ne $raidDiskInfo ) ) {
					if ( $raidDiskInfo.gettype().name -ne "String" ) {
						foreach ( $RDRecord in $raidDiskInfo ) {
							if ($null -ne $RDStatusList -and $RDStatusList.length -gt 0 ) {
								write-host -nonewline "; "
							}

							$tvalue = [int32] $RDRecord.operationalStatus[0]
							$RDStatus = $raidDiskStatusHash[$tvalue]
							write-host -nonewline "$($RDRecord.ElementName) ["
							if ( $RDStatus -eq "OK" ) {
								write-host -nonewline -fore green $RDStatus
							} else {
								write-host -nonewline -fore yellow $RDStatus
							}
							write-host -nonewline "]"

							$RDStatusList += $RDRecord.ElementName + " [$RDStatus]; "
						}
						write-host
					} else {
						write-host "$raidDiskInfo"
					}
				} else {
					write-host "Unknown"
				}
			}	# HP hardware check (Power supply, RAID battery, RAID Controller)

			# Hard disk information
			#
			$firstDrive = $true
			foreach ( $disk in &{ $disks | Where-Object { $_.DriveType -eq 3 } | Sort-Object name} ) {
				if ( $firstDrive ) {
					write-host -fore yellow "-------------------------------------"
				}

				$driveName = $disk.name -replace '\\',''
				$freespace = [String]::Format("{0:0.00} GB", $disk.FreeSpace / 1GB )
				$size      = [String]::Format("{0:0.00} GB", $disk.capacity  / 1GB )

				if ( $null -eq $disk.driveletter ) {

					if ( $disk.name -match '^\\\\?' ) {	# boot partition
						if ( $showReservePart ) {
							$record.DriveInfo +=  "Drive: [$($disk.name)]`n`tFree disk space    : $freespace`n`tDisk space capacity: $size"
							write-host "  Free disk space    : " $freespace
							write-host "  Disk space capacity: " $size
#							write-host "            Volume ID: " $volumeid
						}
					} else {
						$record.DriveInfo        +=  "Volume: [$($disk.name)]`n`tFree disk space    : $freespace`n`tDisk space capacity: $size"

						write-host "Volume: [$($disk.name)]"
						write-host "  Free disk space    : " $freespace
						write-host "  Disk space capacity: " $size
#						write-host "            Volume ID: " $volumeid
					}
				} else {
					if ( has-PageFile $computer $credential $driveName ) {
						$record.DriveInfo += "Drive: [$($disk.driveletter)] [has page file]"
						write-host "Drive: [$($disk.driveletter)] [has page file]"
					} else {
						write-verbose "[debug]Drive "
						$record.DriveInfo += "Drive: [$($disk.driveletter)]"
						write-host "Drive: [$($disk.driveletter)]"
					}
					$record.DriveInfo +=  "`n`tFree disk space    : $freespace`n`tDisk space capacity: $size"

					write-verbose "DriveInfo: [$($record.DriveInfo)]"
					write-host "  Free disk space    : " $freespace
					write-host "  Disk space capacity: " $size
				}

				if ( -not $firstDrive ) {
					$record.DriveInfo += "`n"
				} 

				$firstDrive = $false
			}

			write-verbose "3. HERE"

			if ( $disks | Where-Object {$_.Drivetype -eq 5 } ) {
				$str = "List of CD/DVD-Roms: "
				write-host -fore yellow "`n----------------------"
				write-host -nonewline $str
				foreach ( $disk in &{ $disks | Where-Object { $_.DriveType -eq 5 } } ) {
					$drive = [regex]::replace($disk.driveletter, ':$', '')
					$outString += $drive + ", "
				}
				$outString = [regex]::replace($outString, ",\s*$", "")
				$record.ROMs += "$outString"
				write-host $outString
			} else {
				$str = "The machine has no CD-ROM or DVD-ROM."
				$record.ROMs = $str
				write-host "-------------------------------------"
				write-host $str
			}
			write-verbose "3. HERE"

			#  Show Memory DIMM and Physical disk information
			#
			if ( $showall ) {
					show-MemInfo $computer
					show-HDDInfo $computer $computersystem $raidDiskInfo $tableFormat
			} else {
				if ( $showmem ) {
					show-MemInfo $computer
				}

				if ( $showdisk ) {
					show-HDDInfo $computer $computersystem $raidDiskInfo $tableFormat
				}
			}
		} else {
			$record.comment  = $pingResult[1]

			write-host -nonewline "Error: ["
			write-host -nonewline -fore red $pingResult[1]
			write-host "]"
		}

		if ( $reportMode ) {
			$record
		}
	}

	# Get 

	################################################################################
	# End of Function Defintion
	################################################################################

}

process {
	foreach ( $c in $computer ) {
		if ( $credential ) {
			$wmiargs = @{
				computer = $c
				credential   = $credential
			}
		} else {
			$wmiargs = @{
				computer = $c
			}
		}
		# Now get the results
		#
		get-CompInfo @wmiargs

		write-host
	}
}

# -------------------------------------
# Name         :  computer01
# Domain       :  company.com
# OU Location  :  CN=computer01,OU=Servers,DC=company,DC=com
# Model        :  ProLiant DL380p Gen8
# OS           :  Microsoft Windows Server 2008 R2 Standard   Service Pack 1 [64 Bit]
# CPU          :  [2] Intel(R) Xeon(R) CPU E5-2609 0 @ 2.40GHz
# Memory       :  15.97 GB  |  Available: 11.93 GB  |  Committed: 3.82 GB  |  Commit Limit: 31.93 GB
# Current User :
# Time Zone    :  (UTC-07:00) Mountain Time (US & Canada) [Daylight Savings enabled]
# Serial Number:  1A234567B8
# Install Date :  2013/09/25 12:59:20 -6
# Up Time      :  15 Days, 2 Minutes, 29 Seconds (2020/01/16 04:14:50 PM -07)
# Product ID   :  653200-B21
# Power Supply :  Good: [1, 2]
# RAID Battery :  Smart Array P420i Controller in Slot 0 [OK]
# RAID Disk    :  Smart Array P420i Controller in Slot 0 [OK]
# -------------------------------------
# Drive: [C:] [has page file]
#   Free disk space    :  211.29 GB
#   Disk space capacity:  279.27 GB
# Drive: [E:]
#   Free disk space    :  165.31 GB
#   Disk space capacity:  558.73 GB
# 
# ----------------------
# List of CD/DVD-Roms: D
# 
# Memory Dimm Information
# -----------------------
#   Dimm Name           Size (GB)
#   ---------           ---------
#   PROC  1 DIMM  1          2.00
#   PROC  1 DIMM  4          2.00
#   PROC  1 DIMM  9          2.00
#   PROC  1 DIMM 12          2.00
#   PROC  2 DIMM  1          2.00
#   PROC  2 DIMM  4          2.00
#   PROC  2 DIMM  9          2.00
#   PROC  2 DIMM 12          2.00
# 
# Physical Disk Drive Information
# -------------------------------
# 
# Controller                             Location            Model       SerialNumber     Size      Type Status Speed
# ----------                             --------            -----       ------------     ----      ---- ------ -----
# Smart Array P420i Controller in Slot 0 Port:1I Box:2 Bay:1 EG0300FCHHR NNNNNNNNNNNN     279.40 GB SAS  OK     10000
# Smart Array P420i Controller in Slot 0 Port:1I Box:2 Bay:2 EG0300FCSPH NNNNNNNNNNNNNNNN 279.40 GB SAS  OK     10000
# Smart Array P420i Controller in Slot 0 Port:1I Box:2 Bay:3 EG0300FCHHR NNNNNNNNNNNN     279.40 GB SAS  OK     10000
# Smart Array P420i Controller in Slot 0 Port:1I Box:2 Bay:4 EG0300FCHHR NNNNNNNNNNNN     279.40 GB SAS  OK     10000
# Smart Array P420i Controller in Slot 0 Port:2I Box:2 Bay:5 EG0300FCHHR NNNNNNNNNNNN     279.40 GB SAS  OK     10000
