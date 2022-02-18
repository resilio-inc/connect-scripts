# Fill in your MC host and port
$MCHost = "https://<managemt_console_ip_or_dns>:8443"
$APIToken = "<your_API_token_here>"

$JobObject = [PSCustomObject]@{
	name	    = "SyncJob by Powershell"
	description = "Job description"
	type	    = "sync"
	settings    = [PSCustomObject]@{
		use_ram_optimization = $true
		reference_agent_id = 400
	}
	profile_id  = 2
	agents	    = @(
		[PSCustomObject]@{
			id = 320
			permission = "rw"
			path	   = [PSCustomObject]@{
				linux = ""
				win = "C:\TestFolders\test2"
				osx = ""
			}
		}
		[PSCustomObject]@{
			id		   = 400
			permission = "rw"
			path	   = [PSCustomObject]@{
				linux = ""
				win   = "C:\TestFolders\test2"
				osx   = ""
			}
		}
	)
}

######################## Ignoring cert check error callback #####################
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Ssl3, [Net.SecurityProtocolType]::Tls, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls12
####################################################################################

# Use depth 10 to ensure you convert even the deepest entries into JOSN
$JSON = $JobObject | ConvertTo-Json -Depth 10

Invoke-RestMethod -Method "POST" -Uri "$MCHost/api/v2/jobs" -Headers @{ "Authorization" = "Token $APIToken" } -ContentType "Application/json" -Body $JSON
