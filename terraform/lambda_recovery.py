import os
from datetime import datetime, timezone

import boto3

autoscaling = boto3.client("autoscaling")
ec2 = boto3.client("ec2")
elbv2 = boto3.client("elbv2")

ASG_NAME = os.environ["ASG_NAME"]
TARGET_GROUP_ARN = os.environ["TARGET_GROUP_ARN"]
GRACE_PERIOD_SECONDS = int(os.environ.get("GRACE_PERIOD_SECONDS", "300"))


def _is_past_grace_period(launch_time):
    if not launch_time:
        return False
    age = (datetime.now(timezone.utc) - launch_time).total_seconds()
    return age >= GRACE_PERIOD_SECONDS


def lambda_handler(event, context):
    """Replace long-lived impaired or ALB-unhealthy ASG instances."""
    groups = autoscaling.describe_auto_scaling_groups(
        AutoScalingGroupNames=[ASG_NAME]
    ).get("AutoScalingGroups", [])

    if not groups:
        print(f"Auto Scaling Group {ASG_NAME!r} was not found.")
        return {"checked": 0, "terminated": []}

    instances = [
        item for item in groups[0].get("Instances", [])
        if item.get("LifecycleState") == "InService"
    ]
    instance_ids = [item["InstanceId"] for item in instances]
    if not instance_ids:
        print(f"No InService instances in {ASG_NAME}.")
        return {"checked": 0, "terminated": []}

    launch_times = {
        instance["InstanceId"]: instance.get("LaunchTime")
        for reservation in ec2.describe_instances(InstanceIds=instance_ids).get("Reservations", [])
        for instance in reservation.get("Instances", [])
    }

    status_response = ec2.describe_instance_status(
        InstanceIds=instance_ids,
        IncludeAllInstances=True,
    )
    statuses = {
        item["InstanceId"]: item
        for item in status_response.get("InstanceStatuses", [])
    }

    target_response = elbv2.describe_target_health(
        TargetGroupArn=TARGET_GROUP_ARN,
        Targets=[{"Id": instance_id} for instance_id in instance_ids],
    )
    target_states = {
        item["Target"]["Id"]: item["TargetHealth"]["State"]
        for item in target_response.get("TargetHealthDescriptions", [])
    }

    terminated = []
    for instance_id in instance_ids:
        if not _is_past_grace_period(launch_times.get(instance_id)):
            print(f"Skipping {instance_id}: within launch grace period.")
            continue

        status = statuses.get(instance_id, {})
        system_state = status.get("SystemStatus", {}).get("Status")
        instance_state = status.get("InstanceStatus", {}).get("Status")
        target_state = target_states.get(instance_id)

        impaired = system_state == "impaired" or instance_state == "impaired"
        target_unhealthy = target_state == "unhealthy"
        if not (impaired or target_unhealthy):
            continue

        reason = []
        if impaired:
            reason.append(f"EC2 checks system={system_state}, instance={instance_state}")
        if target_unhealthy:
            reason.append("ALB target is unhealthy")

        print(f"Replacing {instance_id}: {'; '.join(reason)}")
        autoscaling.terminate_instance_in_auto_scaling_group(
            InstanceId=instance_id,
            ShouldDecrementDesiredCapacity=False,
        )
        terminated.append(instance_id)

    return {"checked": len(instance_ids), "terminated": terminated}
