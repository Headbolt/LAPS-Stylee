#!/bin/bash
#
###############################################################################################################################################
#
# ABOUT THIS PROGRAM
#
#   This Script is designed for use in JAMF
#
#   - This script will randomize the password of the specified user account
#	and post the password to a LAPS Extention Attribute in JAMF Pro.
#
###############################################################################################################################################
#
# HISTORY
#
#	Version: 1.1 - 13/10/2019
#
#	- 13/12/2018 - V1.0 - Created by Headbolt
#
#	- 13/10/2019 - V1.1 - Updated by Headbolt
#				More comprehensive error checking and notation
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
# Set the name of the script for later logging
ScriptName="append prefix here as needed - Change Local Administrator Password and Store in JAMF (LAPS Style)"
# Place " quotation marks around extension attribute name in the variable
extAttName=$(echo "\"${ExtensionAttributeName}"\")
# Grab UUID of machine
udid=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Hardware UUID:/ { print $3 }')
# Set path the JAMF Binary - Depends on version being run
jamf_binary="/usr/local/bin/jamf"
# Grab the Current FileVault Status
FVstatus=$(fdesetup status)
# Generate a random 12 character complex password, how this is works is explained below.
newPass=$(openssl rand -base64 10 | tr -d OoIi1lLS | head -c12;echo)
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
/bin/echo "Checking parameters."
# Outputting a Blank Line for Reporting Purposes
/bin/echo
#
# Verify all parameters are present
#
if [ "$resetUser" == "" ]
	then
	    /bin/echo "Error:  The parameter 'Target User' is blank.  Please specify a user to reset."
        ScriptEnd
        exit 1
fi
#
if [ "$apiURL" == "" ]
	then
	    /bin/echo "Error:  The parameter 'API URL' is blank.  Please specify a URL."
		ScriptEnd
        exit 1
fi
#
if [ "$apiUser" == "" ]
	then
	    /bin/echo "Error:  The parameter 'API Username' is blank.  Please specify a user."
	    ScriptEnd
        exit 1
fi
#
if [ "$apiPass" == "" ]
	then
	    /bin/echo "Error:  The parameter 'API Password' is blank.  Please specify a password."
	    ScriptEnd
        exit 1
fi
#
if [ "$adminUser" == "" ]
	then
	    /bin/echo "Error:  The parameter 'FileVault Admin User' is blank.  Please specify a user."
	    ScriptEnd
        exit 1
fi
#
if [ "$adminPass" == "" ]
	then
	    /bin/echo "Error:  The parameter 'FileVault Admin Password' is blank.  Please specify a password."
	    ScriptEnd
        exit 1
fi
#
if [ "$extAttName" == "" ]
	then
	    /bin/echo "Error:  The parameter 'Extension Attribute Name' is blank.  Please specify an Extension Attribute Name."
	    ScriptEnd
        exit 1
fi
#
/bin/echo Parameters Verified.
#
}
#
###############################################################################################################################################
#
# Check If User Exists Locally
#
CheckUser (){
#
/bin/echo Checking If User $resetUser Exists Locally
#
# Verify resetUser is a local user on the computer
checkUser=`dseditgroup -o checkmember -m $resetUser localaccounts | awk '{ print $1 }'`
#
if [[ "$checkUser" = "yes" ]]
	then
	    /bin/echo "$resetUser is a local user on the Computer"
	else
	    /bin/echo "Error: $checkUser is not a local user on the Computer!"
        ScriptEnd
	    exit 1
fi
#
}
#
###############################################################################################################################################
#
# Verify the current User Password in JAMF LAPS
#
CheckOldPassword (){
#
/bin/echo Grabbing Current Password From JAMF API
#
xmlString="<?xml version=\"1.0\" encoding=\"UTF-8\"?><computer><extension_attributes><extension_attribute><name>$ExtensionAttributeName</name><value>$newPass</value></extension_attribute></extension_attributes></computer>"
#
oldPass=$(curl -s -f -u $apiUser:$apiPass -H "Accept: application/xml" $apiURL/JSSResource/computers/udid/$udid/subset/extension_attributes | xpath "//extension_attribute[name=$extAttName]" 2>&1 | awk -F'<value>|</value>' '{print $2}')
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
		#
		if [ "$passwdA" == "" ]
			then
				/bin/echo Current Password for User $resetUser is $oldPass
				/bin/echo "Password stored in LAPS is correct for $resetUser."
			else
				/bin/echo "Error: Password stored in LAPS is not valid for $resetUser."
				/bin/echo Current Password for User $resetUser is $oldPass
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
		sudo $jamf_binary policy -trigger JAMF-NonComplex
		#
		SectionEnd
fi
#
if [ "$oldPass" == "" ]
	then
		/bin/echo "Current password not available, proceeding with forced update."
		$jamf_binary resetPassword -username $resetUser -password $newPass
	else
		/bin/echo "Updating password for $resetUser."
		$jamf_binary resetPassword -updateLoginKeychain -username $resetUser -oldPassword $oldPass -password $newPass
fi
#
/bin/echo "New Password for User $resetUser will be $newPass"
#
# Outputs User Whose Keychains We Are Going To Delete
/bin/echo Deleting Keychains for user $resetUser
#
rm -f -r /Users/$resetUser/Library/Keychains
#
if [ "$FVstatus" == "FileVault is Off." ]
	then
		/bin/echo Not going to set it again as FileVault is DISABLED.
	else
		#
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
				os_ver=$(sw_vers -productVersion)
				IFS='.' read -r -a ver <<< "$os_ver"
				/bin/echo OS Version = $os_ver
				if [[ "${ver[1]}" -ge 13 ]]
					then
						# Set it again as the user to update FileVault.
						/bin/echo "Setting Password again as the user to update FileVault (High Sierra or Higher)."
						#
						/bin/echo Changing password again to ensure updating filevault and Secure Token
						#
						sysadminctl -adminUser ${adminUser} -adminPassword ${adminPass} -resetPasswordFor ${resetUser} -newPassword $newPass 
						#
					elif [[ "${ver[1]}" -lt 13 ]]
						then
							# Set it again as the user to update FileVault.
							/bin/echo "Setting Password again as the user to update FileVault (Pre High Sierra)."
							sudo -iu ${resetUser} dscl . passwd "/Users/${resetUser}" $newPass $newPass
				fi
				#
			else    
				# Not going to set it again as the user as account is not Enabled for FileVault.
				/bin/echo Not going to set it again as the user as account is not Enabled for FileVault.
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
#
passwdB=`dscl /Local/Default -authonly $resetUser $newPass`
#
if [ "$passwdB" == "" ]
	then
		/bin/echo "New password for $resetUser is verified."
	else
		/bin/echo "Error: Password reset for $resetUser was not successful!"
		/bin/echo
		#
		if [ "$adminUser" == "JAMF" ]
			then
				/bin/echo "JAMF Management Account was used for this process"
				/bin/echo "JAMF Password needs to be Reset to an unknown Complex Value."
				/bin/echo
				sudo $jamf_binary policy -trigger JAMF-Complex
		fi
	/bin/echo
        #        
        ScriptEnd
	exit 1
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
#
/usr/bin/curl -s -u ${apiUser}:${apiPass} -X PUT -H "Content-Type: text/xml" -d "${xmlString}" "${apiURL}/JSSResource/computers/udid/$udid"
#
sleep 5
#
LAPSpass=$(curl -s -f -u $apiUser:$apiPass -H "Accept: application/xml" $apiURL/JSSResource/computers/udid/$udid/subset/extension_attributes | xpath "//extension_attribute[name=$extAttName]" 2>&1 | awk -F'<value>|</value>' '{print $2}')
#
# Outputting a Blank Line for Reporting Purposes
/bin/echo
#
/bin/echo "Verifying LAPS password for $resetUser."
passwdC=`dscl /Local/Default -authonly $resetUser $LAPSpass`
#
if [ "$passwdC" == "" ]
	then
		/bin/echo "LAPS password for $resetUser is verified."
	else
		/bin/echo "Error: LAPS password for $resetUser is not correct!"
		ScriptEnd
		exit 1
fi
}
#
###############################################################################################################################################
#
# Section End Function
#
SectionEnd(){
#
# Outputting a Blank Line for Reporting Purposes
/bin/echo
#
# Outputting a Dotted Line for Reporting Purposes
/bin/echo  -----------------------------------------------
#
# Outputting a Blank Line for Reporting Purposes
/bin/echo
#
}
#
###############################################################################################################################################
#
# Script End Function
#
ScriptEnd(){
#
# Outputting a Blank Line for Reporting Purposes
#/bin/echo
#
/bin/echo Ending Script '"'$ScriptName'"'
#
# Outputting a Blank Line for Reporting Purposes
/bin/echo
#
# Outputting a Dotted Line for Reporting Purposes
/bin/echo  -----------------------------------------------
#
# Outputting a Blank Line for Reporting Purposes
/bin/echo
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
# Outputting a Blank Line for Reporting Purposes
/bin/echo
#
ParameterCheck
SectionEnd
#
CheckUser
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
		sudo $jamf_binary policy -trigger JAMF-Complex
		#
		SectionEnd
fi
#
ScriptEnd
#
exit 0
#
# End Processing
#
###############################################################################################################################################