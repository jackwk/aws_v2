# 00-ssm: private VPC + EC2 reachable via SSM Session Manager

Standalone Terraform stack. Creates a VPC with one private subnet (no internet gateway, no NAT),
interface endpoints for SSM, and an Amazon Linux 2023 EC2 instance with no public IP and no inbound rules.
The only way in is AWS Systems Manager Session Manager.

## Deploy

```bash
terraform init
terraform plan
terraform apply
terraform output connect   # ready-to-paste connect command
```

Variables: `region` (default `eu-central-1`), `instance_type` (default `t3.micro`).

## Prerequisites on your machine

1. **AWS CLI v2**: `aws --version`
2. **Session Manager plugin** (the CLI cannot open sessions without it):
   - Linux (Debian/Ubuntu):
     ```bash
     curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o session-manager-plugin.deb
     sudo dpkg -i session-manager-plugin.deb
     ```
   - Other platforms: see the AWS docs, "Install the Session Manager plugin".
   - Verify: `session-manager-plugin` (prints a success message).
3. **Credentials** for the target account (SSO profile, env vars, etc.):
   ```bash
   aws sso login --profile <profile>     # if using SSO
   aws sts get-caller-identity --profile <profile>
   ```
4. **IAM permissions for the user/role connecting** (not created by this stack):
   - `ssm:StartSession` on the instance ARN and on `arn:aws:ssm:*:*:document/SSM-SessionManagerRunShell`
   - `ssm:TerminateSession`, `ssm:ResumeSession` (ideally limited to own sessions)
   - `ssm:DescribeInstanceInformation`, `ec2:DescribeInstances` (for lookups)

## Connect

```bash
# 1. Wait until the instance shows as managed (PingStatus = Online, can take 1-3 min after boot)
aws ssm describe-instance-information \
  --region eu-central-1 \
  --query 'InstanceInformationList[].[InstanceId,PingStatus,PlatformName]' --output table

# 2. Start a shell
aws ssm start-session --target <instance-id> --region eu-central-1
```

Add `--profile <profile>` if not using the default. Exit with `exit` or Ctrl-D.

### Useful extras

```bash
# Run a single command without an interactive shell
aws ssm start-session --target <instance-id> --region eu-central-1 \
  --document-name AWS-StartInteractiveCommand --parameters command="uptime"

# Port forward to a service on the instance (e.g. local 8080 -> instance 80)
aws ssm start-session --target <instance-id> --region eu-central-1 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["8080"]}'

# List / end sessions
aws ssm describe-sessions --state Active --region eu-central-1
aws ssm terminate-session --session-id <session-id> --region eu-central-1
```

Sessions open as `ssm-user` (not `ec2-user`); use `sudo` as needed.

## Troubleshooting

| Symptom | Check |
|---|---|
| `SessionManagerPlugin is not found` | Plugin not installed or not on `PATH` |
| `TargetNotConnected` / instance not in `describe-instance-information` | Wait a few minutes; check instance profile has `AmazonSSMManagedInstanceCore`; check the 3 interface endpoints are `available` and have private DNS enabled; check the instance SG allows outbound 443 to the endpoint SG |
| `AccessDeniedException` on `StartSession` | Your IAM identity lacks `ssm:StartSession` for this instance or document |
| Works in console but not CLI | Different region/profile; pass `--region` and `--profile` explicitly |

## Security notes

- **No inbound access**: the instance SG has zero ingress rules and the instance has no public IP. Access is controlled entirely by IAM (`ssm:StartSession`), so scope that permission tightly (by instance ARN or tag condition, e.g. `ssm:resourceTag/...`). Anyone with it gets a shell.
- **`ssm-user` has passwordless sudo** by default: a session is effectively root. Treat `StartSession` as an admin-level permission.
- **Session logging is not configured by this stack.** By default there is no record of commands run. For anything beyond a lab, enable Session Manager preferences: CloudWatch Logs and/or S3 logging, with KMS encryption, plus CloudTrail (records session start/stop, not content).
- **Session encryption**: traffic is TLS to the SSM endpoints; add a KMS key in the Session Manager preferences for an additional layer.
- **Port forwarding** can bypass network boundaries: it exposes instance (or, with `AWS-StartPortForwardingSessionToRemoteHost`, VPC-internal) services to your local machine. Restrict which SSM documents users may use in IAM.
- **Instance role** has `AmazonSSMManagedInstanceCore` only. Do not add broad permissions; anything on the box can use the role through IMDS. IMDSv2 is enforced to limit SSRF-style credential theft.
- **Endpoint security group** accepts 443 only from the instance SG; the instance SG may only reach the endpoints and the S3 prefix list. If you add workloads, add rules explicitly rather than reusing the default SG.
- **S3 gateway endpoint** has no endpoint policy (full S3 access from the subnet, subject to IAM). Add a policy restricting it to the buckets you need (e.g. the AL2023 repo buckets) if the role ever gets S3 permissions.
- **Patching**: the AMI is pinned at first apply (`ignore_changes = [ami]`), so the instance does not pick up newer images. Patch via `dnf` / SSM Patch Manager or recreate with `terraform apply -replace=aws_instance.this`.
- **Cost**: the 3 interface endpoints are billed hourly per AZ (~USD 0.01/h each plus data). Run `terraform destroy` when not in use.
- **Corporate accounts**: SCPs, permission boundaries or mandatory tagging/logging policies may block parts of this stack; confirm before applying.
