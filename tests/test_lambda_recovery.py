import importlib.util
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import MagicMock

import pytest


MODULE_PATH = Path(__file__).resolve().parents[1] / "terraform" / "lambda_recovery.py"


@pytest.fixture
def recovery(monkeypatch):
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("AWS_EC2_METADATA_DISABLED", "true")
    monkeypatch.setenv("ASG_NAME", "test-asg")
    monkeypatch.setenv("TARGET_GROUP_ARN", "arn:aws:elasticloadbalancing:region:account:targetgroup/test/abc")
    spec = importlib.util.spec_from_file_location("lambda_recovery", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.autoscaling = MagicMock()
    module.ec2 = MagicMock()
    module.elbv2 = MagicMock()
    return module


def test_no_asg_returns_without_recovery(recovery):
    recovery.autoscaling.describe_auto_scaling_groups.return_value = {"AutoScalingGroups": []}

    result = recovery.lambda_handler({}, None)

    assert result == {"checked": 0, "terminated": []}
    recovery.ec2.describe_instances.assert_not_called()


def test_replaces_old_unhealthy_target_without_decrementing_capacity(recovery):
    instance_id = "i-0123456789abcdef0"
    old_launch_time = datetime.now(timezone.utc) - timedelta(minutes=10)
    recovery.autoscaling.describe_auto_scaling_groups.return_value = {
        "AutoScalingGroups": [{"Instances": [{"InstanceId": instance_id, "LifecycleState": "InService"}]}]
    }
    recovery.ec2.describe_instances.return_value = {
        "Reservations": [{"Instances": [{"InstanceId": instance_id, "LaunchTime": old_launch_time}]}]
    }
    recovery.ec2.describe_instance_status.return_value = {
        "InstanceStatuses": [{
            "InstanceId": instance_id,
            "SystemStatus": {"Status": "ok"},
            "InstanceStatus": {"Status": "ok"},
        }]
    }
    recovery.elbv2.describe_target_health.return_value = {
        "TargetHealthDescriptions": [{"Target": {"Id": instance_id}, "TargetHealth": {"State": "unhealthy"}}]
    }

    result = recovery.lambda_handler({}, None)

    assert result == {"checked": 1, "terminated": [instance_id]}
    recovery.autoscaling.terminate_instance_in_auto_scaling_group.assert_called_once_with(
        InstanceId=instance_id,
        ShouldDecrementDesiredCapacity=False,
    )


def test_skips_instance_inside_launch_grace_period(recovery):
    instance_id = "i-0123456789abcdef0"
    recent_launch_time = datetime.now(timezone.utc) - timedelta(seconds=30)
    recovery.autoscaling.describe_auto_scaling_groups.return_value = {
        "AutoScalingGroups": [{"Instances": [{"InstanceId": instance_id, "LifecycleState": "InService"}]}]
    }
    recovery.ec2.describe_instances.return_value = {
        "Reservations": [{"Instances": [{"InstanceId": instance_id, "LaunchTime": recent_launch_time}]}]
    }

    result = recovery.lambda_handler({}, None)

    assert result == {"checked": 1, "terminated": []}
    recovery.autoscaling.terminate_instance_in_auto_scaling_group.assert_not_called()
