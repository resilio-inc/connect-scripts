$MCHost = "https://127.0.0.1:8443"
$token = "XXX"
$JSON = '
{
    "name": "Sync job",
    "description": "My sample job",
    "type": "sync",
    "settings": {
        "priority": 5
    },
    "profile_id": 2,
    "agents": [{
            "id": 1,
            "permission": "rw",
            "path": {
                "linux": "source",
                "win": "C:\\Test",
                "osx": "source"
            }
        }, {
            "id": 2,
            "permission": "rw",
            "path": {
                "linux": "source",
                "win": "D:\\Test",
                "osx": "source"
            }
        }
    ]
}
'

######################## Ignoring cert check error callback #######################
# Please note that this callback is only necessary for Powershell v5.1 and older
# Starting from PS v6.0 you can just add a switch " -SkipCertificateCheck" to
# your Invoke-RestMethod cmdlet
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


$response = Invoke-RestMethod -Method POST -Uri "$MCHost/api/v2/jobs" -Headers @{ "Authorization" = "Token $token" } -ContentType "Application/json" -Body:$JSON -ErrorAction Stop

Write-Output "API response was: $response"