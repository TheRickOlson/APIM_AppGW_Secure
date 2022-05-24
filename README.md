# Locking Down APIM behind Application Gateway
Wanted to find a way to use bicep (as much as possible) to deploy APIM and Application Gateway to an isolated VNET.  The use-case here was to restrict ingress to the APIM to the Application Gateway only.

The high level diagram for what we're going to build looks like this:

![image](https://user-images.githubusercontent.com/16612216/170125643-570194b2-5424-429d-90a8-85910393e356.png)

PreRequisites:
- Generate four self-signed certificates
  - I used `azure-apim.net` as the private DNS zone name
  - My four self-signed certificates were for `api`, `management`, `portal` and `scm`
  - All certs were saved in a `resources` subfolder
  - TODO: Add reference links

JSON parameter definitions:
- `dev.json`
  - `location`   : Azure location to build the components
  - `prefix`     : A string prefix/suffix to be used in building out the components (example, if `prefix = "foo"` then the keyvault would be named `kv-foo` when built)
  - `groupId`    : GUID for a group that you are a member of - this is used to grant yourself the ability to upload certificates to keyvault
  - `domainName` : Domain name for the certificates and private DNS
- `dev-config.json`
  - `location`   : Azure location to build the components
  - `prefix`     : A string prefix/suffix to be used in building out the components (example, if `prefix = "foo"` then the keyvault would be named `kv-foo` when built)
  - `domainName` : Domain name for the certificates and private DNS
  - `gatewayEndpoint` : Name of the APIM Gateway Endpoint
  - `managementEndpoint` : Name of the APIM Management Endpoint
  - `devPortalEndpoint` : Name of the APIM Developer Portal Endpoint
  - `scmEndpoint` : Name of the APIM SCM Endpoint


The VNET is not peered with anything, and we're using self-signed certificates in this POC in order to get it to work.  For testing, I modified the local hosts file of a test VM, taking the public IP of the Application Gateway and mapping that to the four FQDN's representing the APIM endpoints (portal, management, api and scm).

As of v1.0 of this, deployment consists of the following steps:
- Step 1: Modify values in `dev.json` and issue the following new build request: `New-AzResourceGroupDeployment -ResourceGroupName $rsg -TemplateFile .\build.bicep -TemplateParameterFile .\configurations\dev.json`
- Step 2: Run `certImport.ps1` to manually import certificates
- Step 3: Modify values in `dev-config.json` and issue the following new build request: `New-AzResourceGroupDeployment -ResourceGroupName $rsg -TemplateFile .\configure.bicep -TemplateParameterFile .\configurations\dev-config.json`

Steps 1 and 2 are relatively quick.  Step 3 can take upwards of an hour to deploy.


Disclaimers:
- I am not a dev
- I identify as [Battle Faction](https://ironscripter.us/factions/)
- I'm constantly learning, so what you see here is a product of my own learning
