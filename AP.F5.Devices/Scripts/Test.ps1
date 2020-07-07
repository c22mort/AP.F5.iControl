#==================================================================================
# Script: 	Discover-Devices.ps1
# Date:		01/04/19
# Author: 	Andi Patrick
# Purpose:	Gets F5 Device Info via iControl returns all as Property Bag
#==================================================================================
param(
    $deviceAddress,
	$iControlUsername,
	$iControlPassword
)

# Get Start Time For Script
$StartTime = (GET-DATE)

# iControl Authorisation Token
$AUTH_TOKEN = $null
$AUTH_NEEDED = $false

# Get Start Time For Script
$StartTime = (GET-DATE)

#Constants used for event logging
$SCRIPT_NAME			= 'Discover-Devices.ps1'
$EVENT_LEVEL_ERROR 		= 1
$EVENT_LEVEL_WARNING 	= 2
$EVENT_LEVEL_INFO 		= 4

$SCRIPT_STARTED             = 14601
$SCRIPT_PROPERTYBAG_CREATED	= 14602
$SCRIPT_EVENT               = 14603
$SCRIPT_ERROR               = 14604
$SCRIPT_EVENT_AUTH		    = 14605
$SCRIPT_ERROR_ICONTROL      = 14606
$SCRIPT_ENDED               = 14608

#==================================================================================
#   Get-AuthToken
#   Returns AuthToken or $null
#==================================================================================
function Get-AuthToken()
{
    $token = $null

    # Build Token Uri
    $tokenUri = "https://" + $deviceAddress + "/mgmt/shared/authn/login"

    Try
    {
        $headers = @{};
        $body = "{'username':'$iControlUsername','password':'$iControlPassword','loginProviderName':'tmos'}";
        $Token = Invoke-RestMethod -Method POST -Uri $tokenUri -Headers $headers -Body $body
        $token = $Token.token.token       
	}
    Catch 
    {
		# Write Error to Event Log
        $message = "Authentication Error : " + $_
   		Log-Event $SCRIPT_ERROR_ICONTROL $EVENT_LEVEL_ERROR $message
	}

    return $token
}

#==================================================================================
#   Log-Event
#   Logs an informational event to the Operations Manager event log
#   $writeevent by default is debug value
#==================================================================================
function Log-Event
{
	param(
    $eventNo,
    $eventLevel,
    $message,
    $writeEvent = $Debug
    )

	$message = $deviceAddress + "`r`n" + $message + $option
	if ($writeEvent -eq $true)
	{
		$api.LogScriptEvent($SCRIPT_NAME,$eventNo,$eventLevel,$message)
	}
}

#Start by setting up API object.
$api = New-Object -comObject 'MOM.ScriptAPI'

# Log Startup Message
Log-Event $SCRIPT_STARTED $EVENT_LEVEL_INFO "Started F5 Device Discovery" $true

# Ignore Certificate Errors
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# Only Proceed if There is a username given
If ([string]::IsNullOrEmpty($iControlUsername)) 
{
    $message = "No username given to access REST API, please check Run As Accounts!"
    Log-Event $SCRIPT_ERROR_ICONTROL $EVENT_LEVEL_ERROR $message $true

}
else
{
    $Credential = [System.Management.Automation.PSCredential]::new($iControlUsername,(ConvertTo-SecureString $iControlPassword -AsPlainText -Force))
}


Try
{

	# First try a Simple Request to see if Authentication Token os Required
	Try
	{
	    $baseUri = "https://" + $deviceAddress + "/mgmt/tm"
		$results = Invoke-RestMethod -Method GET -Uri $baseUri -Credential $Credential
		# Log AUTH Not Needed Message
		$message = "iControl REST API : Sample Get Request to $baseUri Succesfull, AUTH Token NOT Needed"
		Log-Event $SCRIPT_EVENT_AUTH $EVENT_LEVEL_INFO $message $true
		$AUTH_NEEDED = $false

	}
	Catch
	{
		# Log AUTH Needed Message
		$message = "iControl REST API : Sample Get Request to $baseUri Failed, AUTH Token Needed"
		Log-Event $SCRIPT_EVENT_AUTH $EVENT_LEVEL_INFO $message $true
		$AUTH_NEEDED = $true	
	}

    If ($AUTH_NEEDED) {
		# Try To Get AUTH Token
		$AUTH_TOKEN = Get-AuthToken	

		# Have We Got an Auth Token
		If ($AUTH_TOKEN -ne $null)
		{
			# Log Info Message
			$message = "iControl REST API : AUTH Token Retrieved"
			Log-Event $SCRIPT_EVENT $EVENT_LEVEL_INFO $message $true
		}
		Else
		{
			# Log Error Message
			$message = "iControl REST API Error : Couldn't Get AUTH Token, please check credentials"
			Log-Event $SCRIPT_ERROR_ICONTROL $EVENT_LEVEL_ERROR $message $true
		}
	}
    
    # If AUTH Token isn't needed or We have got an AUTH Token succesfully
	# We Can proceed with Discovery
	If (($AUTH_NEEDED -eq $false) -Or ($AUTH_TOKEN -ne $null))
    {
        # Apply Token To Headers
        $headers = @{};
		If ($AUTH_NEEDED) { $headers.Add("X-F5-Auth-Token", $AUTH_TOKEN) }
        # Get global settings
        $globalUri = "https://" + $deviceAddress + "/mgmt/tm/sys/global-settings"
        $globalSettings = (Invoke-RestMethod -Method GET -Headers $headers -Uri $globalUri -Credential $Credential)
        $hostName = $globalSettings.hostname
        $hostName

        # Get hardware info
        $hardwareUri = "https://" + $deviceAddress + "/mgmt/tm/sys/hardware"
        $hardwareinfo = (Invoke-RestMethod -Method GET -Headers $headers -Uri $hardwareUri -Credential $Credential).entries

        # Get platform info from Hardware Info
        $platformInfo = $hardwareinfo.'https://localhost/mgmt/tm/sys/hardware/platform'.nestedStats.entries.'https://localhost/mgmt/tm/sys/hardware/platform/0'.nestedStats.entries

        # Get systemInfo from hardware info
        $systemInfo = $hardwareInfo.'https://localhost/mgmt/tm/sys/hardware/system-info'.nestedStats.entries.'https://localhost/mgmt/tm/sys/hardware/system-info/0'.nestedStats.entries

        # Get Model
        $model = $platformInfo.marketingName.Description
        $model
        # Get biosRev
        $biosRev = $platformInfo.biosRev.Description       
        $biosRev
        # Get Serial Number
        $serialNumber = $systemInfo.bigipChassisSerialNum.Description
        $serialNumber
        # Get PlatformId
        $platformId = $systemInfo.platform.Description
        $platformId
    
	}
    

}
Catch
{
    $message = "User $restusername, appears to not have access to REST API!`r`n" + $_ 
    Log-Event $SCRIPT_ERROR_ICONTROL $EVENT_LEVEL_ERROR $message $true
}

# Get End Time For Script
$EndTime = (GET-DATE)
$TimeTaken = NEW-TIMESPAN -Start $StartTime -End $EndTime
$Seconds = [math]::Round($TimeTaken.TotalSeconds, 2)

# Log Finished Message
$message = "Script Finished. Took $Seconds Seconds to Complete!"
Log-Event $SCRIPT_ENDED $EVENT_LEVEL_INFO $message $true