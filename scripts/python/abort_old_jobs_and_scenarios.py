import dataiku
from datetime import datetime, timezone

client = dataiku.api_client()

projects = client.list_projects()

#TODO change these 2 parameters according to your needs
threshold_minutes = 2
admin_scenario_name = "ADMIN"

now = datetime.now(tz=timezone.utc)

for project in projects:
    print(f"# Project Name: {project.get('name')}, Project Key: {project.get('projectKey')}")
    all_running_jobs_ids = []
    all_running_scenario_ids = []
    project_key = project.get('projectKey')
    project = client.get_project(project_key)
    jobs = project.list_jobs()
    for job in jobs : 
        if job["endTime"] == 0 : # this means that job is still running
            all_running_jobs_ids.append({"job_id" : job["def"]["id"], "start_time" : job["startTime"]})
    older_jobs = [
        item for item in all_running_jobs_ids
        if (now - datetime.fromtimestamp(item['start_time'] / 1000, tz=timezone.utc)).total_seconds() / 60 > threshold_minutes
    ]
    print(f"## Old jobs to be aborted : {older_jobs}")
    for job in older_jobs:
        project.get_job(job['job_id']).abort()
    
    
    scenarios = project.list_scenarios(as_type="objects")
    for scenario in scenarios:
        try:
            last_runs = scenario.get_last_runs(limit=10, only_finished_runs=False)
            for last_run in last_runs:
                run_details = last_run.get_details()
                scenario_id = run_details["scenarioRun"]["trigger"]["scenarioId"]
                if run_details["scenarioRun"]["end"] == 0 and scenario_id != admin_scenario_name: # this means that scenario is still running
                    all_running_scenario_ids.append({"scenario_id" : scenario_id, "start_time" : run_details["scenarioRun"]["start"]})

        except Exception as e:
            # This handles cases where the scenario has never been run
            print(f"Could not retrieve jobs: {e}")
    older_scenarios = [
        item for item in all_running_scenario_ids
        if (now - datetime.fromtimestamp(item['start_time'] / 1000, tz=timezone.utc)).total_seconds() / 60 > threshold_minutes
    ]
    print(f"## Old scenarios to be aborted : {older_scenarios}")
    for scenario in older_scenarios:
        project.get_scenario(scenario['scenario_id']).abort()
