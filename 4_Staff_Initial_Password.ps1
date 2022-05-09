<#
This script was created by Ali Kaba for HPS.
App name on Azure Ad:  Graph Script to set TeamsID as the Initial Password
**************
1-Get all Azure AD users(staff only) that are NOT SSPR registered with Paging.
2-Loop through all users. If user has employeeId on Azure AD profile set "Harmony" + (employeeId/teamsID) as initial password. ( Must be min 10 digits)
#>
# Connect-AzureAD

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


# # get all users that are NOT SSPR registered
$APIUserURL="https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails?`$filter=isRegistered eq false"


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




$fileVersion = Get-Date -Format "MMdd_HHmm"
$_path = 'D:\Graph_Scripts\LOGS\' +$fileVersion+ '_Azure_users_No_SSPR.csv'
$userList | Export-CSV $_path -NoTypeInformation -Encoding UTF8
Write-Host "......" 
Write-Host $userList.Count "accounts have NOT registered for SSPR."
Write-Host "Output in" $_path
Write-Host "......" 



# if employeeId/teamsID  is empty, skip user

$staffList = [System.Collections.Generic.List[Object]]::new() 


# Authenticate
# Connect-AzureAD -TenantId $tenantID -CertificateThumbprint $thumbPrint -ApplicationId $clientID


Foreach ($user in $userList) {

    $UPN=$user.userPrincipalName  
  
    do {
      try { 
          $userData = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/users/$($UPN)?`$select=userPrincipalName,displayName,employeeId,id" -Method get -Headers $headers;
          $StatusCode = $userData.StatusCode
          } catch {
              $StatusCode = $_.Exception.Response.StatusCode.value__         
          
              if ($StatusCode -eq 429) {
                    Write-Warning "Too many requests. Sleeping for 60 seconds..."
                    Start-Sleep -Seconds 60
              }else {                 
                    Write-Host "..."
                    Write-Host "UPN: " $UPN $_.Exception.Response.StatusCode.value__  $_.Exception.Response.StatusDescription                    
              }
          }
    } while ($StatusCode -eq 429)


      if (-not ([string]::IsNullOrEmpty($userData))) {

          $teamsID = $userData.employeeId      
      
          if($teamsID -ne $null) 
          {

             $tmp_password_plainText = "Harmony" + $teamsID
             # $tmp_password_secureString = ConvertTo-SecureString $tmp_password_plainText -AsPlainText -Force

            

            $ResetPwd = @{
                                "passwordProfile" = @{
                                    "forceChangePasswordNextSignIn"= "false"
                                    "forceChangePasswordNextSignInWithMfa" = "false"
                                    "password" =  $tmp_password_plainText 
                                }
                        } | ConvertTo-Json        
           

            $responseFinal = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$($userData.id)" -Method PATCH -Body $ResetPwd -Headers $headers

            # Set-AzureADUserPassword -ObjectId  $userData.id -Password $tmp_password_secureString

            

             $staffrow  = [PSCustomObject] @{          
                 UPN              = $userData.userPrincipalName;
                 DisplayName      = $userData.displayName;
                 isSPPRregistered = $user.isRegistered;
                 EmployeeId       = $userData.employeeId;
                 TMP_Passsword    = $tmp_password_plainText;                
                 ObjectId         = $userData.id;                 
                 }
               $staffList.Add($staffrow)         
           }
    }

} # End ForEach


$fileVersion = Get-Date -Format "MMdd_HHmm"
$_path = 'D:\Graph_Scripts\LOGS\' +$fileVersion+ '_Azure_Staff_Initial_PSW_SET.csv'
$staffList | Export-CSV $_path -NoTypeInformation -Encoding UTF8
Write-Host "......" 
Write-Host $staffList.Count "accounts set with TEAMS ID as initial password."
Write-Host "Output in" $_path
Write-Host "......" 
Write-Host "All done. "
