<#
This script was created by Ali Kaba for HPS.
Graph Script to add +1 trick email as emailAuthenticationMethod for students as 
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


# GET ALL STUDENTS

$APIUserURL="https://graph.microsoft.com/beta/users?`$select=userPrincipalName,displayName,employeeId,id,mailNickname"
#$apiUrl="https://graph.microsoft.com/beta/users?`$filter=startswith(displayName,'Z')&onPremisesSyncEnabled eq true&`$select=userPrincipalName,displayName,employeeId,id,mailNickname"

[System.Object[]]$allStudents = @()

do {
    # Web request against the users endpoint
    $Result = Invoke-RestMethod -Method "Get" -Uri $APIUserURL -Headers $headers
    
    # Set the Graph API Query url to the next link value that was passed from the Graph API if there are more pages to iterate over.
    # This value may be blank, this means there are no more pages of data to iterate over.
    $APIUserURL = $Result."@odata.nextLink"

    # Extract the users from the list
    $allStudents += $Result.Value | Where-Object { ( $_.userPrincipalName -like '*@student.harmonytx.org' -and -not ([string]::IsNullOrEmpty($_.employeeId)) ) }

# Continue looping as long as there are more pages
} while ($Result."@odata.nextLink")



$fileVersion = Get-Date -Format "MMdd_HHmm"
$_path = 'D:\Graph_Scripts\LOGS_Students\' +$fileVersion+ '_AllStudent.csv'
$allStudents | Export-CSV $_path -NoTypeInformation -Encoding UTF8
Write-Host "Output in" $_path

Write-Host "......" 
Write-Host $allStudents.Count "All Students."
Write-Host "......" 




# GET STUDENTS WITH email authMethod 

$APIUserURL="https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails?`$filter=authMethods/any(t:t eq microsoft.graph.registrationAuthMethod'email')"
#$APIUserURL="https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails?`$filter=authMethods/any(t:t eq microsoft.graph.registrationAuthMethod'securityQuestion')"

[System.Object[]]$studentsWithEmailMethod = @()

do {
    # Web request against the users endpoint
    $Result = Invoke-RestMethod -Method "Get" -Uri $APIUserURL -Headers $headers
    
    # Set the Graph API Query url to the next link value that was passed from the Graph API if there are more pages to iterate over.
    # This value may be blank, this means there are no more pages of data to iterate over.
    $APIUserURL = $Result."@odata.nextLink"

    # Extract the users from the list
    $studentsWithEmailMethod += $Result.Value | Where-Object { ($_.userPrincipalName -like '*@student.harmonytx.org') }

# Continue looping as long as there are more pages
} while ($Result."@odata.nextLink")


$fileVersion = Get-Date -Format "MMdd_HHmm"
#$_path = 'D:\Graph_Scripts\LOGS_Students\' +$fileVersion+ '_StudentsWithEmail_Method.csv'
$_path = 'D:\Graph_Scripts\LOGS_Students\' +$fileVersion+ '_StudentsWithsecurityQuestion_Method.csv'
$studentsWithEmailMethod | Export-CSV $_path -NoTypeInformation -Encoding UTF8
Write-Host "Output in" $_path

Write-Host "......" 
Write-Host $studentsWithEmailMethod.Count "Students With Email Method."
Write-Host "......" 




# Remove students-with-email-method from all students
$targetStudents = Compare-Object -ReferenceObject ($allStudents) -DifferenceObject ($studentsWithEmailMethod) -Property userPrincipalName -PassThru | Select-Object * | Where-Object{$_.sideIndicator -eq "<="}



$fileVersion = Get-Date -Format "MMdd_HHmm"
$_path = 'D:\Graph_Scripts\LOGS_Students\' +$fileVersion+ '_TargetStudents.csv'
$targetStudents | Export-CSV $_path -NoTypeInformation -Encoding UTF8
Write-Host "Output in" $_path

Write-Host "......" 
Write-Host $targetStudents.Count "Target Students."
Write-Host "......" 



$students = Import-Csv -Path D:\Graph_Scripts\students.csv

$user_Log = [System.Collections.Generic.List[Object]]::new() 


Foreach ($user in $targetStudents) {


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






        # Add email Method
        #  
        $addEmailAddress =  $user.mailNickname + '+1@student.harmonytx.org'
        $UpdateUserSetting  = @{ emailAddress=$addEmailAddress }
        $UpdateUserSetting = ConvertTo-Json -InputObject $UpdateUserSetting

         try { 
             $ExecuteUpdateUserSetting = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/users/$($user.userPrincipalName)/authentication/emailMethods" -Method "Post" -Headers $headers -Body $UpdateUserSetting -ErrorAction Stop -UseBasicParsing
             } catch {
                    Write-Host "..."
                    Write-Host "error post ExecuteUpdateUserSetting: " $user.userPrincipalName                      
                    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ 
                    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
             }

        # Set Initial Passwords
        #        
        $student = $students | Where-Object -Property STUDENT_ID -eq $user.employeeId 

             if (-not ([string]::IsNullOrEmpty($student))) {

                $tmp_password_plainText = $student.PSW
                # $tmp_password_secureString = ConvertTo-SecureString $tmp_password_plainText -AsPlainText -Force               
                # Set-AzureADUserPassword -ObjectId  $user.id -Password $tmp_password_secureString

                $ResetPwd = @{
                                "passwordProfile" = @{
                                    "forceChangePasswordNextSignIn"= "false"
                                    "forceChangePasswordNextSignInWithMfa" = "false"
                                    "password" =  $tmp_password_plainText 
                                }
                } | ConvertTo-Json
   
                $response = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)" -Method PATCH -Body $ResetPwd -Headers $headers;             
                
                $user_datarow  = [PSCustomObject] @{          
                                USER   = $user.displayName
                                STUDENT_NUMBER  = $student.STUDENT_NUMBER
                                UPN   = $user.userPrincipalName
                                PSW   = $student.PSW                                          
                                                    }
                $user_Log.Add($user_datarow) 

                # write-host  "Password set for" $user.userPrincipalName

              }

       
 
 
 
  
} # Foreach    
 

$fileVersion = Get-Date -Format "MMdd_HHmm"
$_path = 'D:\Graph_Scripts\LOGS_Students\' +$fileVersion+ '_Student_updated.csv'
$user_Log | Export-CSV $_path -NoTypeInformation -Encoding UTF8
Write-Host "Updates Output in" $_path
Write-Host "......" 
Write-Host $user_Log.Count "accounts Email and Password set."
Write-Host "......" 
Write-Host "All done. "
