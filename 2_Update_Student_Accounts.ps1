<#
This script was created by Ali Kaba for HPS.
Date: 4/24/2022
App name on Azure Ad:  Graph Script to set TeamsID as the Initial Password
**************
Update user attributes on Azure AD
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
$tableName = "AzureAD_Student"

[System.Object[]]$dbUsers = @()

    

## Select staff only with AzureAd id
$mySQL= "SELECT * FROM $tableSchema.$tableName WHERE id is NOT NULL" 
$dbUsers=@(Invoke-Sqlcmd -ServerInstance $serverName -Database $databaseName -Query $mySQL)


# get all users
$APIUserURL="https://graph.microsoft.com/beta/users?`$select=id,employeeId,accountEnabled,givenName,surname,userPrincipalName,jobTitle,companyName,department,officeLocation"

[System.Object[]]$userList = @()

do {
    # Web request against the users endpoint
    $Result = Invoke-RestMethod -Method "Get" -Uri $APIUserURL -Headers $headers
    
    # Set the Graph API Query url to the next link value that was passed from the Graph API if there are more pages to iterate over.
    # This value may be blank, this means there are no more pages of data to iterate over.
    $APIUserURL = $Result."@odata.nextLink"

    # Extract the staff from the list
    $userList += $Result.Value | Where-Object { ($_.userPrincipalName -like '*@student.harmonytx.org') }
    Write-Host "Processing..."

# Continue looping as long as there are more pages
} while ($Result."@odata.nextLink")



# $fileVersion = Get-Date -Format "MMdd_HHmm"
# $_path = 'D:\Graph_Scripts\LOGS_Users\' +$fileVersion+ '_AzureAD_users.csv'
# $userList | Export-CSV $_path -NoTypeInformation -Encoding UTF8
Write-Host "......" 
Write-Host $userList.Count "users found on Azure AD."
# Write-Host "Output in" $_path
Write-Host "......" 



$userCount=0

Foreach ($dbUser in $dbUsers) {

            # check if Token Expired
            #
            if ($myAccessToken.ExpiresOn.LocalDateTime -gt (Get-Date)) {
            # token is valid

            } else {
                    # token expired, get new one
                    $myAccessToken = Get-MsalToken -ClientId $clientID -TenantId $tenantID -ClientCertificate $ClientCertificate
                    $token=$myAccessToken.AccessToken

                    $headers = @{
                        "Authorization" = "Bearer $($token)";
                        "Content-Type" = "application/json";
                    }
            }



            
                
  Foreach ($user in $userList) {           
    if ($dbUser.id -eq $user.id) {
        
      
        $params = @{}

        if ($dbUser.employeeId -ne $user.employeeId -and -not [string]::IsNullOrEmpty($dbUser.employeeId) ) {

            $params += @{ employeeId = $($dbUser.employeeId) } 
        }

        if ($dbUser.accountEnabled -ne $user.accountEnabled -and -not [string]::IsNullOrEmpty($dbUser.accountEnabled) ) {

            $params += @{ accountEnabled = $($dbUser.accountEnabled) }       
        }

        if ($dbUser.givenName -ne $user.givenName -and -not [string]::IsNullOrEmpty($dbUser.givenName) ) {

            $params += @{ givenName = $($dbUser.givenName) }
        }

        if ($dbUser.surname -ne $user.surname -and -not [string]::IsNullOrEmpty($dbUser.surname) ) {

            $params += @{ surname = $($dbUser.surname) }
        }

        if ($dbUser.userPrincipalName -ne $user.userPrincipalName -and -not [string]::IsNullOrEmpty($dbUser.userPrincipalName) ) {

            $params += @{ 
                            userPrincipalName = $($dbUser.userPrincipalName) 
                            mailNickname = $($dbUser.userPrincipalName).Split("@")[0]
              }
        }

        if ($dbUser.jobTitle -ne $user.jobTitle -and -not [string]::IsNullOrEmpty($dbUser.jobTitle) ) {

            $params += @{ jobTitle = $($dbUser.jobTitle) }  
        }

        if ($dbUser.companyName -ne $user.companyName -and -not [string]::IsNullOrEmpty($dbUser.companyName) ) {

            $params += @{ companyName = $($dbUser.companyName) }                
        }


        if ($dbUser.department -ne $user.department -and -not [string]::IsNullOrEmpty($dbUser.department) ) {

            $params += @{ department = $($dbUser.department) }              
        }

        if ($dbUser.officeLocation -ne $user.officeLocation -and -not [string]::IsNullOrEmpty($dbUser.officeLocation) ) {

            $params += @{ officeLocation = $($dbUser.officeLocation) }
        } 



       if($params.Count -ne 0 ){ 

            $userCount = $userCount +1

            Write-Host $dbUser.id " " $dbUser.userPrincipalName " user updated."
            $params.GetEnumerator() | ForEach-Object{
            $message = '{0} => {1}' -f $_.key, $_.value
            Write-Output $message 
            }
            Write-Host "************" 

            $params_json= $params | ConvertTo-Json

            do {
                try { 
                    $response = Invoke-RestMethod -Method PATCH -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)" -Body $params_json -Headers $headers
                    $StatusCode = $response.StatusCode
                    } catch {
                        $StatusCode = $_.Exception.Response.StatusCode.value__         
                    
                        if ($StatusCode -eq 429 -or $StatusCode -eq 503) {
                            Write-Warning "Too many requests. Sleeping for 60 seconds..."
                            Start-Sleep -Seconds 60
                        }else {                 
                            Write-Host "..."
                            Write-Host "Error UPN: " $UPN $_.Exception.Response.StatusCode.value__  $_.Exception.Response.StatusDescription                    
                        }
                    }
            } while ($StatusCode -eq 429 -or $StatusCode -eq 503)


        }
                
                  
     }

      
   }
 }


Write-Host "......" 
Write-Host $userCount "users updated."
Write-Host "......" 
Write-Host "All done. "
