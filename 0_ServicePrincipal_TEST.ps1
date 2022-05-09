$clientID = "AZURE AD client ID"
$tenantID = "AZURE AD tenant ID"
$thumbPrint ="retrieve the Thumbprint of a Certificate"
$certificateSubject="CN=???"

$ClientCertificate = Get-Item "Cert:\CurrentUser\My\$($thumbPrint)"
$myAccessToken = Get-MsalToken -ClientId $clientID -TenantId $tenantID -ClientCertificate $ClientCertificate
$token=$myAccessToken.AccessToken


Connect-AzureAD -TenantId $tenantID -ApplicationId $clientID -CertificateThumbprint $thumbPrint


$user_Mobile = Get-AzureADUser -ObjectID akaba@harmonytx.org | select Mobile

$zusers = $user_Mobile | ConvertTo-Json
write-host $zusers -ForegroundColor Yellow

write-host $user_Mobile -ForegroundColor Yellow