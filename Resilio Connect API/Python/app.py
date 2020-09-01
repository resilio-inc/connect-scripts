import sys
import json
import os

sys.path.append("./")
from communication import initializeMCParams, getAPIRequest
from agents import getAgentList
from jobs import appendToJobAgentList, addJob, startJob, monitorJob

def doSomethingWhenJobIsDone(jobID):
    print("function called after the Job " + str(jobID) + " was done")

# initialize MC
initializeMCParams(os.getenv('RESILIO_MC_URL'), 8443, os.getenv('RESILIO_AUTH_TOKEN'))

# quick test that we can actually connect to this Management Console
print(getAPIRequest("/api/v2/info"))

# get the list of agents
agents = getAgentList()
print(agents)

# create a list of agents that will be added to the job
jobAgentList = []
# we use the first 2 Agents in the agentList
jobAgentList = appendToJobAgentList(jobAgentList, agents[0]['id'], "rw", "/tmp/v1")   
jobAgentList = appendToJobAgentList(jobAgentList, agents[1]['id'], "ro", "/tmp/v1")
print(jobAgentList)
# add the job
newJob = addJob("Test Distribution Job 1", "A demo distribution job", "distribution", jobAgentList)
print(newJob)

# start the new job (only needed for distribution jobs)
newRun = startJob(newJob['id'])
print(newRun)

# monitor the job run
monitorJob(newRun['id'], doSomethingWhenJobIsDone, 5)






