import json
import requests

mcURL = ""
mcPort = -1
mcToken = ""

def initializeMCParams(url, port, token):
  global mcURL
  global mcPort
  global mcToken
  mcURL = url
  mcPort = port
  mcToken = "Token " + token

def getAPIRequest(APIReq) -> json:
    URL = mcURL + ":" + str(mcPort) + APIReq
    req = requests.get(URL, headers={"Authorization": mcToken})
    return json.loads(req.content)

def postAPIRequest(APIReq, bodyData) -> json:
    URL = mcURL + ":" + str(mcPort) + APIReq
    bodyData = json.dumps(bodyData)
    headersData = {
        "Authorization": mcToken,
        "Content-Type": "application/json",
        "Content-Length": str(len(bodyData))
    }
    req = requests.post(URL, headers=headersData, data=bodyData)
    return json.loads(req.content)
