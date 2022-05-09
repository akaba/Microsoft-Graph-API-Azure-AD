# Microsoft-Graph-API-Azure-AD scripts for Azure AD user identity lifecycle management
*  Create users from SQL database source of truth
*  Set initial password for users.
*  Add email Multifactor Authentication Method  
*  Update all user attributes 
*  Add/remove users under branch Administrative Unit
 
 

# Authentication and authorization steps
1. Use 0_Generate a Self Signed Certificate.ps1 file to create a new certificate stored in the current user’s local certificate store on the server where the command runs.
2. Register your app at Azure AD portal. https://docs.microsoft.com/en-us/graph/auth-v2-service
3. Upload certificate public key under the registered app. https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal
4. Configure permissions for Microsoft Graph on your app.
5. Get administrator consent.


