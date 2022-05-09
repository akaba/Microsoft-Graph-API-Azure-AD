<#
This script was created by Ali Kaba for HPS.
Date: 4/24/2022
App name on Azure Ad:  Graph Script to set TeamsID as the Initial Password
**************
1-Get all staff (only active and without AzureAd id) from SQL database [HR_SIS].[dbo].[AzureAD_Staff]

2-Get all active Azure AD users(staff only).

3-Loop through all db users. If UPN does NOT exists in Azure AD, create user profile,
  set "Harmony" + (employeeId/teamsID) as initial password. ( Must be min 10 digits)
#>

$clientID = "AZURE AD client ID"
$tenantID = "AZURE AD tenant ID"
$thumbPrint ="retrieve the Thumbprint of a Certificate"
$certificateSubject="CN=???"

$ClientCertificate = Get-Item "Cert:\CurrentUser\My\$($thumbPrint)"
$myAccessToken = Get-MsalToken -ClientId $clientID -TenantId $tenantID -ClientCertificate $ClientCertificate
$token=$myAccessToken.AccessToken

$headers = @{
    "Authorization" = "Bearer $($token)";
    "Content-Type" = "application/json";
}


# SQL db Input Variables
$serverName = "MIM_DB1"
$databaseName = "HR_SIS"
$tableSchema = "dbo"
$tableName = "AzureAD_Staff"

[System.Object[]]$dbUsers = @()

    

## Select staff [userPrincipalName] only active and without AzureAd id
$mySQL= "SELECT userPrincipalName,idautoID,employeeId,givenName,surname,jobTitle,companyName,department,officeLocation FROM $tableSchema.$tableName WHERE accountEnabled ='true' AND id is NULL" 
$dbUsers=@(Invoke-Sqlcmd -ServerInstance $serverName -Database $databaseName -Query $mySQL)


# get all users
$APIUserURL="https://graph.microsoft.com/beta/users?`$select=userPrincipalName,displayName,officeLocation,employeeId,id"

[System.Object[]]$userList = @()

do {
    # Web request against the users endpoint
    $Result = Invoke-RestMethod -Method "Get" -Uri $APIUserURL -Headers $headers
    
    # Set the Graph API Query url to the next link value that was passed from the Graph API if there are more pages to iterate over.
    # This value may be blank, this means there are no more pages of data to iterate over.
    $APIUserURL = $Result."@odata.nextLink"

    # Extract the staff from the list
    $userList += $Result.Value | Where-Object { ($_.userPrincipalName -like '*@harmonytx.org') }
    Write-Host "Processing..."

# Continue looping as long as there are more pages
} while ($Result."@odata.nextLink")



[bool] $userExists = $false
$userCount=0

Foreach ($dbUser in $dbUsers) {

    $userExists = $false
    Foreach ($user in $userList) {
           
        if ($dbUser.userPrincipalName.Trim() -eq $user.userPrincipalName.Trim() ) {
            $userExists=$true 
            try {
                    # UPN exists in AzureAD: update local db with id.
                    $updateSQL="UPDATE $tableSchema.$tableName SET id='$($user.id)' WHERE idautoID='$($dbUser.idautoID)'" 
                    Invoke-Sqlcmd -Query $updateSQL -ServerInstance $serverName -Database $databaseName -QueryTimeout 65535 -ErrorAction 'Stop'
                    #Write-Host($updateSQL)

                } catch {
                    "error when running sql $sql"
                    Write-Host($error)
                }   
        }
    }
        
    If(-not $userExists) {
            
        # UPN does NOT exists in Azure AD: create the user on AzureAD AND update local db with id.
        #echo "{ $($dbUser.userPrincipalName) }" 

        $params = @{
	        accountEnabled = $true
            preferredLanguage = "en-US"
            givenName = $($dbUser.givenName)
            surname =  $($dbUser.surname)
	        displayName =  $($dbUser.givenName) +" "+ $($dbUser.surname)
	        mailNickname = $($dbUser.userPrincipalName).Split("@")[0]
	        userPrincipalName = $dbUser.userPrincipalName.Trim()
            employeeId = $($dbUser.employeeId)
            jobTitle = $($dbUser.jobTitle)
            companyName = $($dbUser.companyName)
            department = $($dbUser.department)
            officeLocation = $($dbUser.officeLocation)
	        passwordProfile = @{
		        forceChangePasswordNextSignIn = $true
		        password = "Harmony" + $($dbUser.employeeId)
	        }
        } | ConvertTo-Json    

        $response = Invoke-RestMethod -Method "POST" -Uri "https://graph.microsoft.com/v1.0/users" -Body $params -Headers $headers

        #foreach ($item in $response) {
        #            Write-Host $item
        #}


        if (-not ([string]::IsNullOrEmpty($response))) {         

            if ($response.id -ne $null ) {

             $userCount = $userCount +1        
             Write-Host $response.userPrincipalName " created."  
                    
                        try {
                                # UPN exists in AzureAD: update local db with id.
                                $updateSQL="UPDATE $tableSchema.$tableName SET id='$($response.id)' WHERE idautoID='$($dbUser.idautoID)'" 
                                Invoke-Sqlcmd -Query $updateSQL -ServerInstance $serverName -Database $databaseName -QueryTimeout 65535 -ErrorAction 'Stop'
                                #Write-Host($updateSQL)

                            } catch {
                                "error when running sql $updateSQL"
                                Write-Host($error)
                            }
              }

                   
         }



                       
    }      
}


Write-Host "......" 
Write-Host $userCount " users created."
Write-Host "......" 
Write-Host "All done. "