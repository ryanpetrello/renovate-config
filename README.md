# AIPCC Renovate Configuration

This repository contains shared Renovate configuration presets for AIPCC. The presets are organized in a modular hierarchy to provide consistent dependency management across all our repositories.

## Repository Structure

```
renovate-config/
├── default.json                         # Root presets
├── dependency-patterns.json
├── base-branches.json
├── package-rules.json
├── base-images.json                     # Base image update detection
├── konflux.json                         # Tool-specific preset
├── gitlab-approvals.json                # GitLab approval rules compatibility
├── rhaiis/
│   └── rhaiis.json                        # Product-level presets
├── rhel-ai/
│   ├── containers.json                  # Component-level presets
│   └── disk-images.json
```

## Preset Hierarchy

### **Root Level**
- **`default.json`** - Main entry point that extends all foundational presets
- **`base-branches.json`** - Standard branch patterns and enabling rules
- **`package-rules.json`** - Common package management and automerge rules
- **`dependency-patterns.json`** - Standard dependency matching patterns
- **`base-images.json`** - Base image update detection for teams consuming AIPCC base images from `quay.io/aipcc/base-images`, `registry.redhat.io/rhai`, or `registry.redhat.io/rhai-early-access`
- **`konflux.json`** - Konflux CI/CD tooling configurations
- **`gitlab-approvals.json`** - GitLab approval rules compatibility (use for repos with non-author approval enforcement)

### **Product Level**
- **`rhaiis/rhaiis.json`** - Product level specific configuration for RHAIIS repositories

### **Component Level**
- **`rhel-ai/containers.json`** - Component level specific configuration for container repositories
- **`rhel-ai/disk-images.json`** - Conponent level specific configuration for disk image repositories

## Usage Examples

### **Standard Repository**
Most repositories should extend the default preset:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "github>opendatahub-io/renovate-config"
  ]
}
```

### **Container Repository**
Container build repositories extend default + containers preset:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "github>opendatahub-io/renovate-config",
    "github>opendatahub-io/renovate-config//rhel-ai/containers"
  ]
}
```

### **Disk Image Repository**  
Disk image repositories extend default + disk-images preset:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "github>opendatahub-io/renovate-config",
    "github>opendatahub-io/renovate-config//rhel-ai/disk-images"
  ]
}
```

### **RHAIIS Product Repository**
RHAIIS repositories extend default + RHAIIS preset:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "github>opendatahub-io/renovate-config",
    "github>opendatahub-io/renovate-config//rhaiis/rhaiis"
  ]
}
```

### **Repository Consuming Base Images**
Repositories that use AIPCC base images from `quay.io/aipcc/base-images`, `registry.redhat.io/rhai`, or `registry.redhat.io/rhai-early-access` extend the base-images preset to get automated update detection:

**GitLab:**
```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "github>opendatahub-io/renovate-config",
    "github>opendatahub-io/renovate-config//base-images"
  ]
}
```

**GitHub:**
```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "local>opendatahub-io/renovate-config",
    "local>opendatahub-io/renovate-config//base-images"
  ]
}
```

### **Repository with Non-Author Approval Enforcement**
Repositories that enforce non-author approval on merge requests should extend the gitlab-approvals preset to allow Renovate MRs to bypass approval requirements:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "github>opendatahub-io/renovate-config",
    "github>opendatahub-io/renovate-config//gitlab-approvals"
  ]
}
```

## Branch Strategies

The presets define different base branch strategies for different component types:

| Preset | Base Branches | Use Case |
|--------|---------------|----------|
| **default** | Dynamic pattern | General repositories (main, 1.x, 3.x) |
| **rhel-ai/containers** | `["1.5"]` | RHEL AI container builds |
| **rhel-ai/disk-images** | `["1.5"]` | RHEL AI disk image builds |
| **rhaiis/rhaiis** | `["main", "3.0", "3.1", "3.2"]` | RHAIIS multi-version products |

## Preset Philosophy

### **Focused Responsibility**
Each preset has a single, clear purpose:
- **Root presets** provide common settings and rules
- **Product presets** define branch strategies for product lines
- **Component presets** define branch strategies for repository types

### **Composable Design**
Presets are designed to be layered:
```
Repository Config = Root + Product + Component + Custom Rules(set in individual repository)
```

### **Minimal Duplication**
- Complex custom managers live in individual repositories
- Shared presets contain only truly common patterns
- Easy to customize without breaking shared functionality

## Adding Custom Configurations

### **Repository-Specific Custom Managers**
Add your own patterns while keeping the preset benefits:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "github>opendatahub-io/renovate-config",
    "github>opendatahub-io/renovate-config//rhel-ai/containers"
  ],
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": "custom_pattern",
      "matchStrings": ["custom_regex"],
      "datasourceTemplate": "xxx",
      "depNameTemplate": "xxx"
    }
  ]
}
```

## License

This project is licensed under the [Apache License, Version 2.0](LICENSE).
