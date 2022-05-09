<#
This script was created by Ali Kaba for HPS.
App name on Azure Ad:  Graph Script to update Administrative Units (ADD / REMOVE users based on their current campus)
**************
1-Get all Azure AD synced users(staff only).
2-Loop through all users. 
3-Remove old staff from AU
4-Add staff to campus AU if not a member
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




# get all AD synced users

$apiUrl="https://graph.microsoft.com/beta/users?`$select=userPrincipalName,displayName,officeLocation,employeeId,id"
#$apiUrl="https://graph.microsoft.com/beta/users?`$filter=startswith(displayName,'Ali  K')&onPremisesSyncEnabled eq true&`$select=userPrincipalName,displayName,officeLocation,employeeId,id"


$response = Invoke-RestMethod -Uri $apiUrl -Method get -Headers $headers
$users1 = $response.value | Where-Object { ( -not ([string]::IsNullOrEmpty($_.employeeId)) ) }
$userList = [System.Collections.Generic.List[Object]]::new() 

$users1 | ForEach-Object {

   $Datarow1  = [PSCustomObject] @{          
     UPN                = $_.userPrincipalName 
     DisplayName        = $_.displayName
     OfficeLocation     = $_.officeLocation
     EmployeeId         = $_.employeeId
     ObjectId           = $_.id }
   $userList.Add($Datarow1) 
}


# Is data longer than one page ? 
$NextLink = $response.'@Odata.NextLink'
While ($NextLink -ne $Null) { 

    Write-Host "Processing..."
    $response = Invoke-RestMethod -Uri $NextLink -Method get -Headers $headers;
    $users2 = $response.value | Where-Object { ( -not ([string]::IsNullOrEmpty($_.employeeId)) ) }

    $users2 | ForEach-Object {

       $Datarow2  = [PSCustomObject] @{          
         UPN                = $_.userPrincipalName 
         DisplayName        = $_.displayName
         OfficeLocation     = $_.officeLocation
         EmployeeId         = $_.employeeId
         ObjectId           = $_.id }
       $userList.Add($Datarow2) 
    }


   # Check for more data
   $NextLink = $response.'@Odata.NextLink'
} # End While



Write-Host "Processing..."


<#
$UPN ="akaba@harmonytx.org"
$api_AU_Url = "https://graph.microsoft.com/v1.0/users/$($UPN)/memberOf/$/Microsoft.Graph.AdministrativeUnit"
$response = Invoke-RestMethod -Uri $api_AU_Url -Method get -Headers $headers

$response.value | ForEach-Object {

   Write-Host $_.displayName 
}
#>



# get all administrative Units

# Initialize the AU List array
[System.Object[]]$AUList = @()
$AU_URL = "https://graph.microsoft.com/v1.0/directory/administrativeUnits"

do {
    # Web request against the AUs endpoint
    $Result = Invoke-RestMethod -Uri $AU_URL -Method Get -Headers $headers
    
    # Set the Graph API Query url to the next link value that was passed from the Graph API if there are more pages to iterate over.
    # This value may be blank, this means there are no more pages of data to iterate over.
    $AU_URL = $Result."@odata.nextLink"

    # Extract the AUs from the list
    $AUList += $Result.Value

# Continue looping as long as there are more pages
} while ($Result."@odata.nextLink")

# foreach ($AU in $AUList) {
#  Write-Host  $AU.displayName
#  Write-Host  $AU.id
# }


$user_Log = [System.Collections.Generic.List[Object]]::new() 



Foreach ($user in $userList) {


            # check if Token Expired
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


[bool] $AU_member = $false
      
    do {
      try { 
          $userData = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$($user.UPN)/memberOf/$/Microsoft.Graph.AdministrativeUnit" -Method Get -Headers $headers;
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


    
    if (-not ([string]::IsNullOrEmpty($userData)) -and ($user.OfficeLocation -ne $null) ) {


                $MemberID = $user.ObjectId

                # loop user's each AU and compare with campus name

                $userData.value | ForEach-Object {

                   $campusName=$_.displayName.substring(3)

                   if( $campusName -eq $user.OfficeLocation )
                   {

                   $AU_member=$true
                   
                   } elseif ( ($user.OfficeLocation -eq "District - Houston West") -and ($campusName -eq "District - Houston South") ) 
                   {
                   $AU_member=$true                    
                   
                   } else {
                   # remove user from AU
                   
                   $AdminUnitID =  $_.id
                   
                   # Write-Host "AdminUnitID: " $AdminUnitID
                   # Write-Host "MemberID: " $MemberID
                 
                   # Write-Host $user.displayName " REMOVED from "  $_.displayName
                   $user_datarow  = [PSCustomObject] @{          
                                            user   = $user.DisplayName
                                            UPN    = $user.UPN
                                            action = "REMOVED"
                                            au     = $_.displayName}
                   $user_Log.Add($user_datarow) 

                   Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/directory/administrativeUnits/$AdminUnitID/members/$MemberID/`$ref" -Method delete -Headers $headers;
                   
                   }

                } # End ForEach


                
                if(-not $AU_member)
                {
                # add user to the AU

                    
             # Build the body of the web request                     

            $Body = @"
{
    "@odata.id":"https://graph.microsoft.com/v1.0/users/$MemberID"
}
"@

$AdminUnitName=""

switch ($user.OfficeLocation)
{

'HPS Central Office' { $AdminUnitName = '00 HPS Central Office'}
'District - Houston South' { $AdminUnitName = '04 District - Houston South'}
'District - Houston West' { $AdminUnitName = '04 District - Houston South'}
'Houston-Academy' { $AdminUnitName = '05 Houston-Academy'}
'Houston-Innovation' { $AdminUnitName = '06 Houston-Innovation'}
'Houston-Ingenuity' { $AdminUnitName = '07 Houston-Ingenuity'}
'Houston-Science' { $AdminUnitName = '08 Houston-Science'}
'Houston-Art' { $AdminUnitName = '09 Houston-Art'}
'Houston-Exploration' { $AdminUnitName = '10 Houston-Exploration'}
'Sugar Land-Academy' { $AdminUnitName = '11 Sugar Land-Academy'}
'Sugar Land-Innovation' { $AdminUnitName = '12 Sugar Land-Innovation'}
'Katy-Academy' { $AdminUnitName = '13 Katy-Academy'}
'Beaumont-Academy' { $AdminUnitName = '14 Beaumont-Academy'}
'Katy-Innovation' { $AdminUnitName = '15 Katy-Innovation'}
'Sugar Land-Excellence' { $AdminUnitName = '16 Sugar Land-Excellence'}
'District - Houston North' { $AdminUnitName = '17 District - Houston North'}
'Houston-Excellence' { $AdminUnitName = '18 Houston-Excellence'}
'Houston-Endeavor' { $AdminUnitName = '19 Houston-Endeavor'}
'Bryan-Academy' { $AdminUnitName = '20 Bryan-Academy'}
'Houston-Advancement' { $AdminUnitName = '21 Houston-Advancement'}
'Houston-Discovery' { $AdminUnitName = '22 Houston-Discovery'}
'Houston-Technology' { $AdminUnitName = '23 Houston-Technology'}
'Houston-Achievement' { $AdminUnitName = '24 Houston-Achievement'}
'Houston-Enrichment' { $AdminUnitName = '25 Houston-Enrichment'}
'Cypress-Academy' { $AdminUnitName = '26 Cypress-Academy'}
'District - DFW' { $AdminUnitName = '27 District - DFW'}
'Waco-Academy' { $AdminUnitName = '28 Waco-Academy'}
'Garland-Academy' { $AdminUnitName = '29 Garland-Academy'}
'Dallas-Academy-ELM' { $AdminUnitName = '30 Dallas-Academy-ELM'}
'Dallas-Academy-HIG' { $AdminUnitName = '30 Dallas-Academy-HIG'}
'Dallas-Academy-MDL' { $AdminUnitName = '30 Dallas-Academy-MDL'}
'Carrollton-Innovation' { $AdminUnitName = '31 Carrollton-Innovation'}
'Dallas-Innovation' { $AdminUnitName = '32 Dallas-Innovation'}
'Garland-Innovation' { $AdminUnitName = '33 Garland-Innovation'}
'Fort Worth-Academy' { $AdminUnitName = '34 Fort Worth-Academy'}
'Grand Prairie-Academy' { $AdminUnitName = '35 Grand Prairie-Academy'}
'Euless-Academy' { $AdminUnitName = '36 Euless-Academy'}
'Dallas-Excellence' { $AdminUnitName = '37 Dallas-Excellence'}
'Fort Worth-Innovation' { $AdminUnitName = '38 Fort Worth-Innovation'}
'Euless-Innovation' { $AdminUnitName = '39 Euless-Innovation'}
'Carrollton-Academy' { $AdminUnitName = '40 Carrollton-Academy'}
'Waco-Innovation' { $AdminUnitName = '41 Waco-Innovation'}
'Plano-Academy' { $AdminUnitName = '42 Plano-Academy'}
'Grand Prairie-Innovation' { $AdminUnitName = '43 Grand Prairie-Innovation'}
'District - Austin' { $AdminUnitName = '44 District - Austin'}
'Austin-Academy' { $AdminUnitName = '45 Austin-Academy'}
'Pflugerville-Academy' { $AdminUnitName = '46 Pflugerville-Academy'}
'Austin-Science' { $AdminUnitName = '47 Austin-Science'}
'Austin-Excellence' { $AdminUnitName = '48 Austin-Excellence'}
'Austin-Endeavor' { $AdminUnitName = '49 Austin-Endeavor'}
'Cedar Park-Academy' { $AdminUnitName = '50 Cedar Park-Academy'}
'Austin-Innovation' { $AdminUnitName = '51 Austin-Innovation'}
'District - San Antonio' { $AdminUnitName = '52 District - San Antonio'}
'San Antonio-Academy' { $AdminUnitName = '53 San Antonio-Academy'}
'San Antonio-Innovation' { $AdminUnitName = '54 San Antonio-Innovation'}
'Laredo-Academy' { $AdminUnitName = '55 Laredo-Academy'}
'Laredo-Innovation' { $AdminUnitName = '56 Laredo-Innovation'}
'Brownsville-Academy' { $AdminUnitName = '57 Brownsville-Academy'}
'San Antonio-Excellence' { $AdminUnitName = '58 San Antonio-Excellence'}
'Brownsville-Innovation' { $AdminUnitName = '59 Brownsville-Innovation'}
'Laredo-Excellence' { $AdminUnitName = '60 Laredo-Excellence'}
'District - El Paso' { $AdminUnitName = '61 District - El Paso'}
'El Paso-Academy' { $AdminUnitName = '62 El Paso-Academy'}
'El Paso-Innovation' { $AdminUnitName = '63 El Paso-Innovation'}
'Lubbock-Academy' { $AdminUnitName = '64 Lubbock-Academy'}
'Odessa-Academy' { $AdminUnitName = '65 Odessa-Academy'}
'El Paso-Excellence' { $AdminUnitName = '66 El Paso-Excellence'}
'El Paso-Science' { $AdminUnitName = '67 El Paso-Science'}

}

# Get AdminUnitID by AdminUnitName

foreach ($AU in $AUList) {
if( $AU.displayName -eq $AdminUnitName )
  {
    $AdminUnitID =$AU.id 
    #Write-Host $user.displayName " ADDED to "  $AU.displayName
    $user_datarow1  = [PSCustomObject] @{          
                                  user   = $user.DisplayName
                                  UPN    = $user.UPN
                                  action = "ADDED"
                                  au     = $AU.displayName}
    $user_Log.Add($user_datarow1) 
 
    # Add user to the Administrative units                  
    Invoke-RestMethod -Method "Post" -Uri "https://graph.microsoft.com/v1.0/directory/administrativeUnits/$AdminUnitID/members/`$ref" -Headers $headers -Body $Body -ContentType "application/json"
 }
}

                }  # add user to the AU        
    } 

} # End ForEach user


<#
$fileVersion = Get-Date -Format "MMdd_HHmm"
$_path = 'D:\Graph_Scripts\LOGS_AU\' +$fileVersion+ '_AU_user_updates.csv'
$user_Log | Export-CSV $_path -NoTypeInformation -Encoding UTF8
Write-Host "Updates Output in" $_path
#>
Write-Host "......" 
Write-Host $user_Log.Count "accounts processes."
Write-Host "......" 
Write-Host "All done. "