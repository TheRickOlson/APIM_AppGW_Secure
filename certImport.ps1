# Because you can't import certificates to KeyVault using bicep, this
# script is an intermediate step between the build and configure steps

# This is the password you used when generating the self-signed certificates
$certPass = Read-Host -AsSecureString -Prompt "Certificate Password"
$rsg = "rg-myresourcegroup"

$vault = (Get-AzKeyVault -ResourceGroupName $rsg).VaultName

# The names here represent the four APIM endpoints that need to be exposed
$certs = @("api","management","portal","scm")

foreach ($cert in $certs) {
    $properties = @{
        VaultName = $vault
        Name = "APIM-$cert"
        FilePath = ".\resources\$cert.pfx"
        Password = $certPass
    }

    Import-AzKeyVaultCertificate @properties
}
