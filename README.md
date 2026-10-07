# AI Ops MCP Workshop Setup

Deploys the workshop end to end: an MCP server on Amazon ECS that lets Claude Desktop investigate and fix a sample nginx app on Amazon EKS.

Works on **macOS** and on **Windows with Git Bash**. All commands are bash: on Windows, run every command in this README in **Git Bash**, not PowerShell or Command Prompt.

## Tools you need

| Tool | Version | macOS | Windows |
|---|---|---|---|
| Git (+ Git Bash on Windows) | any | `xcode-select --install` | `winget install Git.Git` |
| AWS CLI | v2 | `brew install awscli` | `winget install Amazon.AWSCLI` |
| Terraform | 1.5 or later | `brew install terraform` | `winget install Hashicorp.Terraform` |
| kubectl | any recent | `brew install kubectl` | `winget install Kubernetes.kubectl` |
| Docker Desktop | with `buildx` | [docker.com](https://www.docker.com/products/docker-desktop/) | [docker.com](https://www.docker.com/products/docker-desktop/) (WSL 2 backend) |
| Node.js | 18 or later (includes `npx`) | `brew install node` | `winget install OpenJS.NodeJS.LTS` |
| Python | 3.x, as `python3` | `brew install python` | see [Windows setup](#windows-setup-git-bash) |
| curl | any | preinstalled | included with Git Bash |
| Claude Desktop | latest | [claude.ai/download](https://claude.ai/download) | [claude.ai/download](https://claude.ai/download) |

You also need an AWS account where you can create VPC, EKS, ECS, ECR, IAM, SSM and CloudWatch resources, and an S3 bucket for Terraform state.

### Windows setup (Git Bash)

Do this once, before step 1:

1. Open **Git Bash** (Start menu → Git Bash). After installing tools, open a new Git Bash window so they're on the `PATH`.
2. Keep Unix line endings, or the `.sh` scripts fail with `$'\r': command not found`:

   ```bash
   git config --global core.autocrlf input
   ```

3. Make sure `python3` works. The scripts call `python3`, which the python.org installer doesn't provide:

   ```bash
   python3 --version
   ```

   If that fails or opens the Microsoft Store, install Python from the Microsoft Store (it includes `python3`), or turn off the `python3.exe` alias under Settings → Apps → Advanced app settings → App execution aliases and add a copy of `python.exe` named `python3.exe` next to it.

4. Start Docker Desktop and check it from Git Bash with `docker buildx version`.

## 1. Install

```bash
git clone https://github.com/mrkhurana/mcp-demo-setup.git
cd mcp-demo-setup
./install.sh
```

`install.sh` creates a `FLO26` directory next to this repo, clones the three workshop repositories into it, and copies the deploy and destroy scripts there:

```text
FLO26/
├── main_deploy.sh
├── main_destroy.sh
├── mcp-server-deployments/   MCP server code + ECR image build
├── mcp-server-terraform/     VPC, EKS, ECS, load balancer, nginx workload
└── mcp-client/               connects Claude Desktop to the MCP server
```

To put it somewhere else, run `FLO26_DIR=~/work/FLO26 ./install.sh`. To clone over SSH, run `GIT_BASE=git@github.com:mrkhurana ./install.sh`.

## 2. Export your AWS credentials

The same commands work in the macOS Terminal and in Git Bash. Use access keys:

```bash
export AWS_ACCESS_KEY_ID=<your-access-key-id>
export AWS_SECRET_ACCESS_KEY=<your-secret-access-key>
export AWS_SESSION_TOKEN=<your-session-token>   # only for temporary credentials
export AWS_REGION=us-east-1
```

Or use a named profile:

```bash
export AWS_PROFILE=<your-profile>
export AWS_REGION=us-east-1
```

Check that they work:

```bash
aws sts get-caller-identity
```

Run every command below in the same terminal window, so the credentials stay set.

## 3. Configure (first time only)

**Terraform state (backend).** Both Terraform projects store their state in an S3 bucket, set in `mcp-server-terraform/backend.tf` and `mcp-server-deployments/terraform/versions.tf`. Update the `backend "s3"` block in both files as needed, for example to a bucket in your own account:

```bash
cd ../FLO26
export TF_STATE_BUCKET=<your-bucket-name>
aws s3 mb "s3://$TF_STATE_BUCKET" --region us-east-1   # skip if the bucket exists
```

macOS:

```bash
sed -i '' "s/tf-state-backup-kay-bkp/$TF_STATE_BUCKET/" mcp-server-terraform/backend.tf mcp-server-deployments/terraform/versions.tf
```

Windows (Git Bash):

```bash
sed -i "s/tf-state-backup-kay-bkp/$TF_STATE_BUCKET/" mcp-server-terraform/backend.tf mcp-server-deployments/terraform/versions.tf
```

**Terraform variables.** Create `terraform.tfvars` from the example:

```bash
cp mcp-server-terraform/terraform.tfvars.example mcp-server-terraform/terraform.tfvars
```

Then edit `mcp-server-terraform/terraform.tfvars` (on Windows, `notepad mcp-server-terraform/terraform.tfvars` works from Git Bash):

- Replace `123456789012` with your AWS account ID (from `aws sts get-caller-identity`) and point the image at the `mcp-server` repository:

  ```hcl
  container_image                = "<account-id>.dkr.ecr.us-east-1.amazonaws.com/mcp-server:latest"
  container_image_repository_arn = "arn:aws:ecr:us-east-1:<account-id>:repository/mcp-server"
  ```

- Add your public IP, so the load balancer and the EKS API accept your connections. Find it with `curl -s https://checkip.amazonaws.com`:

  ```hcl
  public_allowed_cidrs = ["<your-ip>/32"]
  ```

## 4. Deploy

Quit Claude Desktop completely: Cmd+Q on macOS, or right-click its icon in the system tray → Quit on Windows. It rewrites its config file while it is open. Then, from the `FLO26` directory:

```bash
./main_deploy.sh v0.2.0
```

It takes about 25 to 30 minutes and stops at the first error. It runs, in order:

1. `mcp-server-deployments/deploy.sh`: builds the MCP server image, pushes it to ECR, and copies the nginx image into ECR.
2. `mcp-server-terraform/deploy.sh`: creates the VPC, EKS cluster, ECS service, load balancer and auth token, then deploys nginx. It then restarts the ECS service on the new image.
3. `mcp-client/deploy.sh`: checks that the MCP server answers, and adds the `aiops-eks` entry to Claude Desktop.

Then open Claude Desktop and start a new chat. `aiops-eks` appears with its tools. On Windows, the script writes the entry to `%APPDATA%\Claude\claude_desktop_config.json` and starts `mcp-remote` through `cmd /c npx`.

Try:

> List the pods in the application namespace.

## 5. Destroy

When you're done, remove everything so it stops costing money. From the `FLO26` directory:

```bash
./main_destroy.sh
```

It asks you to type `destroy`, removes the `aiops-eks` entry from Claude Desktop, then destroys the infrastructure and the ECR repositories. It takes about 15 to 20 minutes.

- `./main_destroy.sh --keep-images` keeps the ECR images, so the next deploy is faster.
- `./main_destroy.sh --yes` skips the confirmation prompt.

Quit Claude Desktop first, so the entry (which holds the token) can be removed.

Your Terraform state bucket is not deleted.

## Cost

While it runs, the EKS control plane, Fargate pods, ECS task, load balancer and VPC endpoints are billed hourly. Destroy the setup when you're not using it.

## Troubleshooting

- **`could not clone`** during install: you don't have access to the repository. Ask for access, or use `GIT_BASE` with a URL you can reach.
- **`AccessDenied` on the S3 backend**: update the backend to a bucket you can access (step 3).
- **`/health` gets no response** during deploy: your IP isn't in `public_allowed_cidrs`. Your IP changes when you switch networks; update it and re-run `./main_deploy.sh v0.2.0`.
- **`Claude Desktop is running`** (macOS): quit it with Cmd+Q and re-run.
- **`aiops-eks` doesn't appear in Claude Desktop**: see `mcp-client/README.md`, Troubleshooting. On Windows, the log is in `%APPDATA%\Claude\logs\mcp-server-aiops-eks.log`.
- **Windows: `$'\r': command not found`**: the scripts were checked out with Windows line endings. Run `git config --global core.autocrlf input`, delete `mcp-demo-setup` and `FLO26`, and clone again.
- **Windows: `python3: command not found`**: see [Windows setup](#windows-setup-git-bash), step 3.
