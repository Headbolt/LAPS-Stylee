#!/bin/bash
#
###############################################################################################################################################
#
# ABOUT THIS PROGRAM
#
#	LAPS-Stylee.sh
#	https://github.com/Headbolt/LAPS-Stylee
#
#   This Script is designed for use in JAMF
#
#   - This script will randomize the password of the specified user account
#	and post the password to a LAPS Extention Attribute in JAMF Pro.
#
#	The API User Account for this script requires the following permissions within JAMF.
#	Computer Extension Attributes - Read and Update
#	Computers - Read and Update
#	Users - Read and Update - Why this is needed is not 100% Clear, but the script fails without it.
#
###############################################################################################################################################
#
# HISTORY
#
#	Version: 1.3 - 10/02/2023
#
#	- 13/12/2018 - V1.0 - Created by Headbolt
#
#	- 13/10/2019 - V1.1 - Updated by Headbolt
#				More comprehensive error checking and notation
#
#	- 15/06/2021 - V1.2 - Updated by Headbolt
#				Updated to deal issues in Big Sur. Big Sur updated from perl/xpath 5.18 to perl/xpath 5.28. This introduced syntax errors
#				in xpath for Big Sur, so some logic was added around the os Version and a variable to deal with the eventualities.
#
#	- 10/02/2023 - V1.3 - Updated by Headbolt
#				Updated to remove OS checks as older OS support is no linger needed
#				Also the CURL commands and Auth have been updated to use Token Based Auth, this removes the requirement for
#				"Allow Basic authentication in addition to Bearer Token authentication" in the "Allow Basic authentication for the Classic API"
#				section of the Password Policy, to be enabled, this makes things a little more secure.
#
###############################################################################################################################################
#
# DEFINE VARIABLES & READ IN PARAMETERS
#
###############################################################################################################################################
#
# Grab the username of the user to be reset from JAMF variable #4 eg. username
resetUser=$4
# Grab the first part of the API URL from JAMF variable #5 eg. https://COMPANY-NAME.jamfcloud.com
apiURL=$5
# Grab the username for API Login from JAMF variable #6 eg. username
apiUser=$6
# Grab the password for API Login from JAMF variable #7 eg. password
apiPass=$7
# Grab the username for FileVault unlock from JAMF variable #8 eg. username
adminUser=$8
# Grab the password for FileVault unlock from JAMF variable #9 eg. password
adminPass=$9
# Grab the extension atttribute name from JAMF variable #10 eg. username's password
ExtensionAttributeName=${10}
#
# Set the Trigger Name of your Policy to set the JAMF Management Account to a Known Password incase
# it is used for the Admin User from Variable #8 eg. JAMF-NonComplex
NonCOMP="JAMF-NonComplex"
#
# Set the Trigger Name of your Policy to set the JAMF Management Account to an unknown complex Password incase
# it is used for the Admin User from Variable #9 eg. JAMF-Complex
COMP="JAMF-Complex"
#
ScriptName="MacOS | Change Local Password and Store in JAMF (LAPS Style)" # Set the name of the script for later logging
extAttName=$(echo "\"${ExtensionAttributeName}"\") # Place " quotation marks around extension attribute name in the variable
udid=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Hardware UUID:/ { print $3 }') # Grab UUID of machine
jamf_binary="/usr/local/bin/jamf" # Set path the JAMF Binary - Depends on version being run
FVstatus=$(fdesetup status) # Grab the Current FileVault Status
ExitCode=0 # Set Initial ExitCode
# Generate a random 12 character complex password, how this is works is explained below.
newPass=$(openssl rand -base64 10 | tr -d OoIi1lLS | head -c12;echo)
#
xmlString="<?xml version=\"1.0\" encoding=\"UTF-8\"?><computer><extension_attributes><extension_attribute><name>$ExtensionAttributeName</name><value>$newPass</value></extension_attribute></extension_attributes></computer>"
#
###############################################################################################################################################
#
#            ┌─── openssl is used to create
#            │	a random Base64 string
#            │                    ┌── remove ambiguous characters
#            │                    │
# ┌──────────┴──────────┐	  ┌───┴────────┐
# openssl rand -base64 10 | tr -d OoIi1lLS | head -c12;echo
#                                            └──────┬─────┘
#                                                   │
#             prints the first 12 characters  ──────┘
#             of the randomly generated string
#
###############################################################################################################################################
#
# SCRIPT CONTENTS - DO NOT MODIFY BELOW THIS LINE
#
###############################################################################################################################################
#
# Defining Functions
#
###############################################################################################################################################
#
# Verifiy all Required Parameters are set.
#
ParameterCheck(){
#
/bin/echo 'Checking parameters.'
#
# Verify all parameters are present
#
if [ "$resetUser" == "" ]
	then
	    /bin/echo "Error:  The parameter 'Target User' is blank.  Please specify a user to reset."
		ExitCode=1
		ScriptEnd
fi
#
if [ "$apiURL" == "" ]
	then
	    /bin/echo "Error:  The parameter 'API URL' is blank.  Please specify a URL."
		ExitCode=1
		ScriptEnd
fi
#
if [ "$apiUser" == "" ]
	then
	    /bin/echo "Error:  The parameter 'API Username' is blank.  Please specify a user."
		ExitCode=1
		ScriptEnd
fi
#
if [ "$apiPass" == "" ]
	then
	    /bin/echo "Error:  The parameter 'API Password' is blank.  Please specify a password."
		ExitCode=1
		ScriptEnd
fi
#
if [ "$adminUser" == "" ]
	then
		/bin/echo "Error:  The parameter 'FileVault Admin User' is blank.  Please specify a user."
		ExitCode=1
		ScriptEnd
fi
#
if [ "$adminPass" == "" ]
	then
		/bin/echo "Error:  The parameter 'FileVault Admin Password' is blank.  Please specify a password."
		ExitCode=1
		ScriptEnd
fi
#
if [ "$extAttName" == "" ]
	then
		/bin/echo "Error:  The parameter 'Extension Attribute Name' is blank.  Please specify an Extension Attribute Name."
		ExitCode=1
		ScriptEnd
fi
#
/bin/echo 'Parameters Verified.'
#
}
#
###############################################################################################################################################
#
# Check If User Exists Locally
#
CheckUser (){
#
/bin/echo "Checking If User $resetUser Exists Locally"
#
checkUser=`dseditgroup -o checkmember -m $resetUser localaccounts | awk '{ print $1 }'` # Verify resetUser is a local user on the computer
#
if [[ "$checkUser" = "yes" ]]
	then
		/bin/echo "$resetUser is a local user on the Computer"
	else
		/bin/echo "Error: $checkUser is not a local user on the Computer!"
		ExitCode=1
		ScriptEnd
fi
#
}
#
###############################################################################################################################################
#
# Auth Token Function
#
AuthToken (){
#
/bin/echo 'Getting Athentication Token from JAMF'
rawtoken=$(curl -s -u ${apiUser}:${apiPass} -X POST "${apiURL}/uapi/auth/tokens" | grep token) # This Authenticates against the JAMF API with the Provided details and obtains an Authentication Token
rawtoken=${rawtoken%?};
token=$(echo $rawtoken | awk '{print$3}' | cut -d \" -f2)
#
}
#
###############################################################################################################################################
#
# Verify the current User Password in JAMF LAPS
#
CheckOldPassword (){
#
/bin/echo 'Grabbing Current Password From JAMF API'
oldPass=$(curl -s -X GET "${apiURL}/JSSResource/computers/udid/$udid/subset/extension_attributes" -H 'Authorization: Bearer '$token'' | xpath -e "//extension_attribute[name=$extAttName]" 2>&1 | awk -F'<value>|</value>' '{print $2}')
#
if [ "$oldPass" == "" ]
	then
	    /bin/echo "No Password is stored in LAPS."
	else
	    /bin/echo "A Password was found in LAPS."
fi
#
if [ "$oldPass" != "" ]
	then
		passwdA=`dscl /Local/Default -authonly $resetUser $oldPass`
		if [ "$passwdA" == "" ]
			then
				/bin/echo "Current Password stored in LAPS for User $resetUser is $oldPass"
				/bin/echo "Password stored in LAPS is correct for $resetUser."
			else
				/bin/echo "Error: Password stored in LAPS is not valid for $resetUser."
				/bin/echo "Current Password stored in LAPS for User $resetUser is $oldPass"
				oldPass=""
		fi
	else
		oldpass=$oldpass
fi
}
#
###############################################################################################################################################
#
# Update the User Password
#
RunLAPS (){
#
if [ "$adminUser" == "JAMF" ]
	then
		/bin/echo "JAMF Management Account being used for this process"
		/bin/echo "JAMF Password needs to be Reset to a Known Value."
		/bin/echo
		sudo $jamf_binary policy -trigger $NonCOMP
		#
		SectionEnd
fi
#
if [ "$oldPass" == "" ]
	then
		/bin/echo "Current password not available, proceeding with forced update."
#		$jamf_binary resetPassword -username $resetUser -password $newPass
        sysadminctl -adminUser ${adminUser} -adminPassword ${adminPass} -resetPasswordFor ${resetUser} -newPassword $newPass
	else
		/bin/echo "Updating password for $resetUser."
		$jamf_binary resetPassword -updateLoginKeychain -username $resetUser -oldPassword $oldPass -password $newPass
fi
#
/bin/echo "New Password for User $resetUser will be $newPass"
/bin/echo Deleting Keychains for user $resetUser # Outputs User Whose Keychains We Are Going To Delete
rm -f -r /Users/$resetUser/Library/Keychains
if [ "$FVstatus" == "FileVault is Off." ]
	then
		/bin/echo Not going to set it again as FileVault is DISABLED.
	else
		if [ "$(fdesetup list | grep -ic "^${resetUser},")" -eq '0' ]
			then
				/bin/echo User $resetUser is not FileVault Enabled
				UserFDE=NO
			else
				/bin/echo User $resetUser is FileVault Enabled
				UserFDE=YES
		fi
		#
		if [ "$UserFDE" == "YES" ]
			then
				/bin/echo 'Setting Password again to update FileVault.' # Set it again as the user to update FileVault.
				/bin/echo 'Using' ${adminUser} ' as the Local FileVault Admin.'
				sysadminctl -adminUser ${adminUser} -adminPassword ${adminPass} -resetPasswordFor ${resetUser} -newPassword $newPass 
			else    
				# Not going to set it again as the user as account is not Enabled for FileVault.
				/bin/echo 'Not going to set it again as the user as account is not Enabled for FileVault.'
		fi
fi
}
#
###############################################################################################################################################
#
# Verify the new User Password
#
CheckNewPassword (){
#
/bin/echo "Verifying new password for $resetUser."
passwdB=`dscl /Local/Default -authonly $resetUser $newPass`
if [ "$passwdB" == "" ]
	then
		/bin/echo "New password for $resetUser is verified."
	else
		/bin/echo "Error: Password reset for $resetUser was not successful!"
		/bin/echo # Outputting a Blank Line for Reporting Purposes
		if [ "$adminUser" == "JAMF" ]
			then
				/bin/echo "JAMF Management Account was used for this process"
				/bin/echo "JAMF Password needs to be Reset to an unknown Complex Value."
				/bin/echo # Outputting a Blank Line for Reporting Purposes
				sudo $jamf_binary policy -trigger $COMP
		fi
		/bin/echo # Outputting a Blank Line for Reporting Purposes
		ExitCode=1
		ScriptEnd
fi
}
#
###############################################################################################################################################
#
# Update the LAPS Extention Attribute
#
UpdateAPI (){
#
/bin/echo "Recording new password for $resetUser into LAPS."
/usr/bin/curl -s -X PUT -H 'Authorization: Bearer '$token'' -H "Content-Type: text/xml" -d "${xmlString}" "${apiURL}/JSSResource/computers/udid/$udid" 2>&1 /dev/null
LAPSpass=$(curl -s -f "Accept: application/xml" $apiURL/JSSResource/computers/udid/$udid/subset/extension_attributes -H 'Authorization: Bearer '$token'' | xpath -e "//extension_attribute[name=$extAttName]" 2>&1 | awk -F'<value>|</value>' '{print $2}')
#
/bin/echo # Outputting a Blank Line for Reporting Purposes
dscl /Local/Default -authonly $resetUser $LAPSpass
/bin/echo "Verifying LAPS password for $resetUser."
passwdC=`dscl /Local/Default -authonly $resetUser $LAPSpass`
if [ "$passwdC" == "" ]
	then
		/bin/echo "LAPS password for $resetUser is verified as is $LAPSpass"
	else
		/bin/echo "Error: LAPS password for $resetUser is not correct!! Currently it is $LAPSpass"
		ExitCode=1
		ScriptEnd
fi
}
#
###############################################################################################################################################
#
# Section End Function
#
SectionEnd(){
#
/bin/echo # Outputting a Blank Line for Reporting Purposes
/bin/echo  ----------------------------------------------- # Outputting a Dotted Line for Reporting Purposes
/bin/echo # Outputting a Blank Line for Reporting Purposes
#
}
#
###############################################################################################################################################
#
# Script End Function
#
ScriptEnd(){
#
/bin/echo Ending Script '"'$ScriptName'"'
/bin/echo # Outputting a Blank Line for Reporting Purposes
/bin/echo  ----------------------------------------------- # Outputting a Dotted Line for Reporting Purposes
/bin/echo # Outputting a Blank Line for Reporting Purposes
exit $ExitCode
#
}
#
###############################################################################################################################################
#
# End Of Function Definition
#
###############################################################################################################################################
#
# Beginning Processing
#
###############################################################################################################################################
#
/bin/echo # Outputting a Blank Line for Reporting Purposes
SectionEnd
#
ParameterCheck
SectionEnd
#
CheckUser
SectionEnd
#
AuthToken
SectionEnd
#
CheckOldPassword
SectionEnd
#
RunLAPS
SectionEnd
#
CheckNewPassword
SectionEnd
#
UpdateAPI
SectionEnd
#
if [ "$adminUser" == "JAMF" ]
	then
		/bin/echo "JAMF Management Account was used for this process"
		/bin/echo "JAMF Password needs to be Reset to an unknown Complex Value."
		/bin/echo
		sudo $jamf_binary policy -trigger $COMP
		#
		SectionEnd
fi
ScriptEnd
