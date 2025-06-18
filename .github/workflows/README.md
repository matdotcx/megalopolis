# GitHub Actions Workflows Setup

## Required GitHub Secrets

To enable automated Let's Encrypt DNS-01 certificate provisioning, add these secrets to your GitHub repository:

### Setup Instructions:
1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add the following secrets:

### Required Secrets:

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `NS1_API_KEY` | NS1 API key for DNS-01 challenges | `YOUR_NS1_API_KEY` |

### Optional Secrets:

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `DOCKER_HUB_USERNAME` | Docker Hub username for image pushing | `your-dockerhub-user` |
| `DOCKER_HUB_TOKEN` | Docker Hub access token | `dckr_pat_abc123...` |

## Usage in Bootstrap

The bootstrap script will automatically detect the `NS1_API_KEY` environment variable:

```bash
# Set environment variable before running bootstrap
export NS1_API_KEY="your-ns1-api-key"
./scripts/bootstrap.sh
```

## Example GitHub Actions Workflow

```yaml
name: Deploy Megalopolis

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup cluster
      run: make init
      
    - name: Deploy with Let's Encrypt
      env:
        NS1_API_KEY: ${{ secrets.NS1_API_KEY }}
      run: |
        # Bootstrap script will automatically configure Let's Encrypt
        ./scripts/bootstrap.sh
        
    - name: Validate deployment
      run: make validate
```

## Security Best Practices

1. **Rotate API Keys:** Regularly rotate the NS1 API key
2. **Least Privilege:** Ensure NS1 API key has minimal required permissions:
   - `zones` - View zone information
   - `records` - Manage DNS records
   - `data` - View data sources
3. **Secret Scanning:** Enable GitHub secret scanning to detect exposed keys
4. **Environment Separation:** Use different API keys for staging/production