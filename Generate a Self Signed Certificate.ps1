$certPassword = "Enter your psq"
$certName = "name your certificate"
$certPath = "file path to the certificate"
$certFileName = "file name of the certificate"

$Params = @{
   "DnsName" = @($certName)
   "Subject" = "CN=$($certName)"
   "CertStoreLocation" = "Cert:\CurrentUser\My"
   "NotAfter" = (Get-Date).AddYears(10)
   "KeyAlgorithm" = "RSA"
   "KeyLength" = "2048"
   "KeyExportPolicy"= "Exportable"
   "KeySpec" = "Signature"
 
}

$myCert = $null 
$myCert = New-SelfSignedCertificate @Params
$thumbPrint = $myCert.Thumbprint

# Password to be set on the exported Certificate
$pwd = ConvertTo-SecureString -String $certPassword -Force -AsPlainText

# Export the Certificate
Export-PfxCertificate -cert "cert:\CurrentUser\My\$($thumbPrint)" -FilePath "$($certPath)$($certFileName).pfx" -Password $pwd

$x509cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate("$($certPath)$($certFileName).pfx", (ConvertTo-SecureString -String $certPassword -Force -AsPlainText))
$keyValue = [System.Convert]::ToBase64String($x509cert.GetRawCertData())
$keyValue | out-file "$($certPath)$($certFileName).cer"

#Get-X509Details $keyValue


