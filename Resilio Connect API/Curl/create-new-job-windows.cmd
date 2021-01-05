rem --------------------------------------------------------------------------
rem Option 1: do everything from single command line
rem 
rem Note that in Windows CURL you HAVE TO use double quotes. Single quote does not work. Therefore, you have to escape all double quotes in your JSON with \"

curl --insecure --request POST --url "https://mc.address.com:8443/api/v2/jobs?ignore_errors=true" --header "Authorization: Token ZZDRZ7LPVZ4FM35ANRDTXXXXXXXX6EX3SWZ5FWXB2RUWSDW7A" --header "Content-Type: application/json" --data "{\"name\": \"SyncJob\", \"description\": \"Job description\", \"type\": \"sync\", \"groups\": [], \"use_new_cipher\": false, \"settings\": { \"priority\": 5 }, \"profile_id\": 1, \"agents\": [{ \"id\": 1, \"permission\": \"rw\", \"path\": { \"linux\": \"source\", \"win\": \"C:\\test\", \"osx\": \"source\" } }, { \"id\": 2, \"permission\": \"rw\", \"path\": { \"linux\": \"source\", \"win\": \"D:\test\", \"osx\": \"source\" } } ] }"


rem --------------------------------------------------------------------------
rem Option 2: store your JSON in the file and tell CURL to load JSON from file
rem 
rem Note that in Windows CURL you HAVE TO use double quotes. Single quote does not work. Therefore, you have to escape all double quotes in your JSON with \"

curl --insecure --request POST --url "https://mc-test.resilio.com:8443/api/v2/jobs?ignore_errors=true" --header "Authorization: Token ZZDRZ7LPVZ4FM35ANRDTXXXXXXXX6EX3SWZ5FWXB2RUWSDW7A " --header "Content-Type: application/json" --data @json.txt

rem Here's how the json.txt content may look like (no rem's of course):
rem {
rem     "name": "SyncJob",
rem     "description": "Job description",
rem     "type": "sync",
rem     "groups": [],
rem     "settings": {
rem        "priority": 5
rem    },
rem    "profile_id": 2,
rem    "agents": [{
rem            "id": 1,
rem            "permission": "rw",
rem            "path": {
rem                "linux": "source",
rem                "win": "C:\\test",
rem                "osx": "source"
rem            }
rem        }, {
rem            "id": 2,
rem            "permission": "rw",
rem            "path": {
rem                "linux": "source",
rem                "win": "D:\\test",
rem                "osx": "source"
rem            }
rem        }
rem    ]
rem }
