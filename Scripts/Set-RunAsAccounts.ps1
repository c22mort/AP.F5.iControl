#==================================================================================
# Script: 	Set-RunAsAccounts.ps1
# Date:		30/06/20
# Author: 	Andi Patrick
# Purpose:	Creates iControl REST API RunAsAccounts and	associates to 
#			Network nodes
#			If Only one account is given then it is associated to all targeted 
#			objects
#
# Parameters :	ConnectToManagementServer
#				Name of SCOM Management Server to connect to
#
#				DistributionResourcePool (Optional)
#				Name of SCOM Management Server Resource pool to Distribute accounts to
#
#				DistributionServers (Optional)
#				Comma Seperated list of management servers to Distribute accounts to
#
# Notes :		If no DistributionResourcePool or DistributionServers is given then
#				Accounts will be setup as less secure, this is NOT Reccomended
#
#==================================================================================

# Define the named parameters
Param(
	# Management Server to Connect to
    [Parameter(Mandatory=$true)]
    [string[]]$ConnectToManagementServer,
	# DistributionResourcePool
    [Parameter(Mandatory=$false)]
    [string[]]$DistributionResourcePool,
	# DistributionServers
    [Parameter(Mandatory=$false)]
    [string[]]$DistributionServers
)

# Distribution Resource Pool object
$DistributionResourcePoolObject = $null
# Distribution Servers Array
$DistributionServersList = $null
# Device List from CSV
$csvDevices = $null
# Are We doing Moe Secure Distribution 
$secureDistribution = $true

#==================================================================================
# Function:	Remove Accounts
# Purpose:	Creates a Single Account associated with all targettable objects
#==================================================================================
function Remove-Accounts
{
	# Get Run AS Profile
	$profile = Get-SCOMRunAsProfile | ? {$_.DisplayName -eq "AP.F5 Device Login (iControl)"}

	# Get Existing Accounts
	$existingAccountsArray = Get-SCOMRunAsAccount | ? {$_.Name -eq "AP.F5.iControl"}

	# Single Account to Remove
	If ($existingAccountsArray.count -eq 1) {
		Try
		{
			$profileAccount = Get-SCOMRunAsAccount -Id $existingAccountsArray[0].Id
			$result = Set-SCOMRunAsProfile -Action Remove -Profile $profile -Account $profileAccount 			
		}
		Catch{}
		$remove = $profileAccount | Remove-SCOMRunAsAccount
	
	}

	If ($existingAccountsArray.count -gt 1) {
		Foreach ($existingAccount in $existingAccountsArray) {
			$profileAccount = Get-SCOMRunAsAccount -Id $existingAccount.Id
			# Get F5 Devices from SCOM
			$scomDevice = Get-SCOMClass -name "AP.F5.Device" | Get-SCOMClassInstance | ? {$_.DisplayName -eq $profileAccount.Description}
			$result = Set-SCOMRunAsProfile -Action Remove -Profile $profile -Account $profileAccount -Instance $scomDevice
			$remove = $profileAccount | Remove-SCOMRunAsAccount
		}
	}
}


#==================================================================================
# Function:	Create-SingleAccount
# Purpose:	Creates a Single Account associated with all targettable objects
#==================================================================================
function Create-SingleAccount
{
	# Get Run AS Profile
	$profile = Get-SCOMRunAsProfile | ? {$_.DisplayName -eq "AP.F5 Device Login (iControl)"}

	# Now Create New Account
	$password = ConvertTo-SecureString $csvDevices[0].password -AsPlainText -Force
	$Cred = New-Object System.Management.Automation.PSCredential ($csvDevices[0].username, $password)
	Try
	{
		Write-Output "Creating Account..."
		$newAccount = Add-SCOMRunASAccount -Basic -Name "AP.F5.iControl" -Description "All Targeted Objects" -RunAsCredential $Cred

		Write-Output "Assigning Account to Profile..."
		$runAsAccount = Get-SCOMRunAsAccount | ? {$_.Name -eq "AP.F5.iControl"}
		Set-SCOMRunAsProfile -Action Add -Profile $profile -Account $runAsAccount 
		Write-Output "Setting up Account Distribution..."

		If ($secureDistribution -eq $false)
		{
			$runAsAccount | Set-SCOMRunAsDistribution -LessSecure
		}
		else
		{
			$distribution = @()
			$distribution += $DistributionResourcePoolObject 			
			Foreach ($DistributionServer in $DistributionServersList)
			{
				$distribution += $DistributionServer		
			}				
			$runAsAccount | Set-SCOMRunAsDistribution -MoreSecure -SecureDistribution $distribution						
		}
	}
	Catch
	{
		# Log Error Message
		Write-Host "Unable to Create iControl REST API Account" -ForegroundColor Red
	}
}

#==================================================================================
# Function:	Create-MultipleAccounts
# Purpose:	Creates a Single Account associated with all targettable objects
#==================================================================================
function Create-MultipleAccounts
{
	# Get Run AS Profile
	$profile = Get-SCOMRunAsProfile | ? {$_.DisplayName -eq "AP.F5 Device Login (iControl)"}

	# Create an Account for each given device
	Foreach ($csvDevice in $csvDevices)
	{
		# Create Credential
		$password = ConvertTo-SecureString $csvDevice.password -AsPlainText -Force
		$Cred = New-Object System.Management.Automation.PSCredential ($csvDevice.username, $password)

		$message = "Creating Account for " + $csvDevice.fqdn
		Write-Output $message

		# Get F5 Devices from SCOM
		$scomDevice = Get-SCOMClass -name "System.NetworkManagement.Node" | Get-SCOMClassInstance | ? {$_.DisplayName -eq $csvDevice.fqdn}
		If ($scomDevice.Count -eq 1){
			$message = "Matching Device Found in SCOM"
			Write-Output "Creating Account..."
			$newAccount = Add-SCOMRunASAccount -Basic -Name "AP.F5.iControl" -Description $csvDevice.fqdn -RunAsCredential $Cred 
			Write-Output "Assigning Account to Profile..."
			$runAsAccount = Get-SCOMRunAsAccount | ? {$_.Name -eq "AP.F5.iControl" -And $_.Description -eq $csvDevice.fqdn}
			# Set RunAs Profile
			Set-SCOMRunAsProfile -Action Add -Profile $profile -Account $runAsAccount -Instance $scomDevice
			# Set Secure Distribution
			If ($secureDistribution -eq $false)
			{
				$runAsAccount | Set-SCOMRunAsDistribution -LessSecure
			}
			else
			{
				$distribution = @()
				$distribution += $DistributionResourcePoolObject 			
				Foreach ($DistributionServer in $DistributionServersList)
				{
					$distribution += $DistributionServer		
				}				
				$runAsAccount | Set-SCOMRunAsDistribution -MoreSecure -SecureDistribution $distribution				
			}

		} else {	
			$message = "Matching Device Not Found in SCOM"
			Write-Output $message
		}

	}
}

# Log Startup Message
Write-Host "Set-RunAsAccounts v.1.1, ©A.Patrick, 2020" -ForegroundColor Cyan
Write-Host

#Start by setting up API object.
$api = New-Object -comObject 'MOM.ScriptAPI'

# Try To Connect to Management Server
Try
{
	# Connect to Management Server
	Write-Host "Connecting to $ConnectToManagementServer..." -ForegroundColor Yellow -NoNewLine
	Start-OperationsManagerClientShell -managementServerName $ConnectToManagementServer
	Write-Host "Success!" -ForegroundColor Yellow
}
Catch 
{
	# Log Error Message
	Write-Host
	Write-Host "Unable to connect to : " $ConnectToManagementServer -ForegroundColor Red
	EXIT
}

# Check Distribution Parameters
If ($DistributionResourcePool -ne $null) 
{
		Write-Host "Checking DistributionResourcePool $DistributionResourcePool..." -ForegroundColor Yellow -NoNewLine
		$DistributionResourcePoolObject = Get-SCOMResourcePool -DisplayName $DistributionResourcePool
		If ($DistributionResourcePoolObject -eq $null)
		{
			# Log Error Message
			Write-Host
			Write-Host "Unable to Get $DistributionResourcePool from $ConnectToManagementServer" -ForegroundColor Red
			EXIT		
		}
		Write-Host "Success!" -ForegroundColor Yellow
}

If ($DistributionServers -ne $null)
{
	Foreach ($DistributionServer in $DistributionServers)
	{
		Write-Host
		Write-Host "Checking Distribution Server $distributionServer..." -ForegroundColor Yellow -NoNewLine
		$serverObject = Get-SCOMManagementServer | ? {$_.ComputerName -eq $distributionServer}
		If ($serverObject -eq $null)
		{
			# Log Error Message
			Write-Host "Failed!" -ForegroundColor Red
			Write-Host "Unable to Get $DistributionServer from $ConnectToManagementServer" -ForegroundColor Red
			EXIT		
		}
		$DistributionServersList += $serverObject
		Write-Host "Success!" -ForegroundColor Yellow
	}
}

# If Both Distribution Servers and DistributionResourcePool are Empty then it will be done as less secure, so we need to warn users
If (($DistributionResourcePool -eq $null) -and ($DistributionServers -eq $null))
{
	Write-Host
	Write-Host "No Resource Pool or Servers given for Distrubution!`r`nDo you want to set up less Secure Distribution (NOT Reccomended) [Y/N] : " -NoNewLine -ForegroundColor Green
	$confirmation = Read-Host 
	If (-Not ($confirmation -match "[yY]")){
		Exit
	}
	Write-Host "Continuing with Less Secure Distribution" -ForegroundColor Yellow
	$secureDistribution = $false
}

# Check CSV File
Try
{
	# Get CSV File
	Write-Host
	Write-Host "Opening f5-devices.csv..." -ForegroundColor Yellow -NoNewLine
	$csvDevices = @(Import-Csv .\f5-devices.csv)
	
	# Empty CSV
	If ($csvDevices.count -eq 0) {
		# Log Error Message
		Write-Host "f5-devices.csv appears to be empty, please check!" -ForegroundColor Red			
		EXIT
	}

	Write-Host "Success!" -ForegroundColor Yellow
}
Catch
{
	# Log Error Message
	Write-Host "Couldn't open f5-devices.csv, please check for file in scripts location!" -ForegroundColor Red		
}

# All Checking now done, proceed with Removing accounts and creating new Ones
Try
{
	Write-Host
	Write-Host "Removing Existing Account(s)..." -ForegroundColor Yellow -NoNewLine
	Remove-Accounts
	Write-Host "Success!" -ForegroundColor Yellow

}
Catch 
{
	Write-Host "Failed!" -ForegroundColor Red
	Write-Host $_ -ForegroundColor Red
	EXIT
}

# Create Single Account if needed
If ($csvDevices.count -eq 1)
{
	Create-SingleAccount
} 

# Create Single Account if needed
If ($csvDevices.count -gt 1)
{
	Create-MultipleAccounts
} 
