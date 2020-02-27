#Requires -Version 6.0

$base_url = "https://my.resilioserver.com:8443/api/v2"
$API_token = "USEEGUIHIDRCX4ORZH5KYBGGGGGQNEWL"
$http_headers = @{ "Authorization" = "Token $API_token" }
$agent_name_to_check = "*lonebot*"

# Get list of agents
$agent_list = Invoke-RestMethod -Method GET -uri "$base_url/agents" -Headers $http_headers -ContentType "Application/json" -SkipCertificateCheck
Write-Host "Total amount of agents is $($agent_list.length)"

# Find necessary agent by it's name
$my_agent = $agent_list | Where-Object {$_.name -like $agent_name_to_check}
if (!$my_agent)
{
    Write-Host "Requested agent not found, exiting"
    exit 1
}

# Get list of active job runs
$active_runs = Invoke-RestMethod -Method GET -uri "$base_url/runs?status=working" -Headers $http_headers -ContentType "Application/json" -SkipCertificateCheck
$active_runs = $active_runs.data
Write-Host "Total amount of active runs is $($active_runs.length)"

# Go over all active runs
foreach ($jobrun in $active_runs)
{
    # Get list of agents participating in the run
    $agents_in_run = Invoke-RestMethod -Method GET -uri "$base_url/runs/$($jobrun.id)/agents" -Headers $http_headers -ContentType "Application/json" -SkipCertificateCheck
    $agents_in_run = $agents_in_run.data

    # Find my own agent in the curren job run
    $my_agent_in_run = $agents_in_run | Where-Object {$_.agent_id -eq $my_agent.id}

    # Also pick any of source agents from this job run
    $source_agent = $agents_in_run | Where-Object {$_.permission -eq 'rw'}

    if ($my_agent_in_run)
    {
        Write-Host "The agent `"$($my_agent.name)`" participating in job `"$($jobrun.name)`", run $($jobrun.id) its status is `"$($my_agent_in_run.status)`""

        # Check if agent downloaded all the files from the source (which indicates it is done)
        if ($my_agent_in_run.files_total -eq $my_agent_in_run.files_completed -and $my_agent_in_run.files_completed -eq $source_agent.files_total)
        {
            Write-Host "It completed delivery of all $($source_agent.files_total) file(s) in transfer"
        }
        else 
        {
            Write-Host "The agent `"$($my_agent.name)`" only got $($my_agent_in_run.files_completed) file(s) out of $($source_agent.files_total)"
        }
    }
    else 
    {
        Write-Host "The agent `"$($my_agent.name)`" is not participating in job `"$($jobrun.name)`""
    }

}
Write-Host "Script finished"

