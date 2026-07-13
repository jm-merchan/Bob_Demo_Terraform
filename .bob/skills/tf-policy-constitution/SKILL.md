---
name: tf-policy-constitution
description: Authoritative rules and design template for Terraform policy development (tfpolicy). Load this before any policy authoring work begins.
user-invocable: false
---

# Terraform Policy Development Constitution

**Organization**: [Your Organization Name]
**Version**: 1.0.0
**Effective Date**: May 2026
**Purpose**: Non-negotiable principles for enterprise Terraform policy development using **tfpolicy** (also written `tf-policy`). This is HashiCorp's HCL-based policy framework for HCP Terraform — it is **not** Sentinel. Do not refer to artifacts in this workflow as "Sentinel" or "Sentinel-style"; Sentinel is a separate product with its own non-HCL DSL, `.sentinel` files, and `import "tfplan/v2"` semantics. tfpolicy uses `.policy.hcl` / `.policytest.hcl`, `resource_policy`/`provider_policy`/`module_policy` blocks, and `core::*` functions as defined in this constitution.
**Authority**: This document governs what correct policy code looks like. Workflow mechanics live in orchestrator skills. Agent behavior lives in AGENTS.md. If a rule exists here, it is not duplicated elsewhere.

---

## 1. Policy Fundamentals

### 1.1 File Extensions

- Policy files MUST use the `.policy.hcl` extension
- Test files MUST use the `.policytest.hcl` extension
- No other extensions are valid for policy or policy test code

### 1.2 CLI Commands

- Validate policies: `tfpolicy validate --policies=<path>`
- Run tests: `tfpolicy test --policies=<path> [--tests=<path>]`
- Both commands MUST pass before any policy set is published

### 1.3 Policy Block Types

Three policy block types exist, each scoping enforcement to a different Terraform construct:

| Block Type        | Target                  | Example                                                                          |
| ----------------- | ----------------------- | -------------------------------------------------------------------------------- |
| `resource_policy` | Resource configurations | `resource_policy "aws_s3_bucket" "enforce_encryption" { ... }`                   |
| `provider_policy` | Provider configurations | `provider_policy "aws" "require_default_tags" { ... }`                           |
| `module_policy`   | Module calls            | `module_policy "registry.terraform.io/acme/*" "enforce_approved_source" { ... }` |

Rules:

- Every policy block takes exactly two labels: the target type and the policy name
- The first label identifies what the policy applies to (resource type, provider name, or module source pattern)
- The second label is a unique, descriptive policy name in `snake_case`
- Wildcard `*` is supported as the first label for universal policies that apply to all targets of that block type
- Prefer specific target types over wildcard `*` unless the policy is truly universal (e.g., tagging, naming conventions)

---

## 2. File Layout & Naming

### 2.1 Project Structure

Policy repositories MUST follow this structure:

```
/
├── policies/
│   ├── encryption.policy.hcl
│   ├── networking.policy.hcl
│   ├── iam.policy.hcl
│   ├── tagging.policy.hcl
│   ├── provider-governance.policy.hcl
│   └── module-governance.policy.hcl
├── tests/
│   ├── encryption.policytest.hcl
│   ├── networking.policytest.hcl
│   ├── iam.policytest.hcl
│   ├── tagging.policytest.hcl
│   ├── provider-governance.policytest.hcl
│   └── module-governance.policytest.hcl
├── plugins/
│   ├── src/
│   │   └── {name}/
│   │       └── main.go
│   └── bin/
│       └── {name}
└── README.md
```

### 2.2 Naming Conventions

- Policy files: `{domain}.policy.hcl` — group related policies by domain
- Test files: `{domain}.policytest.hcl` — one test file per policy file, matching names exactly
- Plugin source: `plugins/src/{name}/main.go`
- Plugin binary: `plugins/bin/{name}`
- Standard domains: `encryption`, `networking`, `iam`, `tagging`, `provider-governance`, `module-governance`
- Additional domains MAY be added for organization-specific concerns (e.g., `cost`, `compliance`, `data-residency`)

---

## 3. Policy Authoring Rules

### 3.1 Enforce Blocks

- Every `enforce` block MUST include both `condition` and `error_message`
- `error_message` MUST be actionable: state what is wrong AND how to fix it
- Bad: `"Encryption is not enabled."`
- Good: `"S3 bucket does not have server-side encryption enabled. Set 'server_side_encryption_configuration' with AES256 or aws:kms algorithm."`

### 3.2 Enforcement Level

- `enforcement_level` MUST be set explicitly on every policy — never rely on the default
- Encryption policies: `enforcement_level = "mandatory"`
- Public access policies: `enforcement_level = "mandatory"`
- Provider governance policies: `enforcement_level = "mandatory"`
- Module governance policies: `enforcement_level = "mandatory"`
- Tagging policies: MAY use `enforcement_level = "advisory"` for gradual rollout
- Security-critical policies MUST NOT omit `enforcement_level`

### 3.3 Targeting and Filtering

- Prefer specific resource types over wildcard `*` unless the policy is truly universal
- Use `filter` blocks to scope policies to subsets (e.g., by workspace tags, environment)
- Filter expressions MUST be deterministic — no side effects or external lookups

### 3.4 Logic and Computation

- Use `locals` blocks for intermediate computations, especially when processing `core::getresources()` results
- Functions use `core::` namespace for built-in functions
- Functions use `plugin::` namespace for custom plugin functions
- MUST NOT hardcode values that should be parameterized — use `input` blocks or `locals`
- Complex conditions MUST include inline comments explaining the logic
- Keep expressions single-line — the HCL parser has multi-line limitations during private beta

### 3.5 Null Safety

- ALWAYS use `core::try()` for optional attributes: `core::try(attrs.tags["Environment"], "")` not `attrs.tags["Environment"]`
- Check block existence with `core::length()` before indexing: verify `attrs.ingress != null && core::length(attrs.ingress) > 0` before `attrs.ingress[0]`
- Prefer `core::try()` over redundant length checks when it handles the empty case gracefully

### 3.6 Performance Rules

- `core::getresources(type, filter)` iterates ALL resources across ALL modules — O(N) complexity
- MUST cache `core::getresources()` results in top-level `locals` blocks, NEVER inside `resource_policy` blocks (would re-execute for every resource instance)
- `core::getdatasource()` makes REAL provider API calls (e.g., queries AWS APIs) — NOT cached state reads
- MUST NOT use `core::getdatasource()` inside `resource_policy` blocks (would call APIs for every resource)
- Use `core::getdatasource()` only in top-level `locals` when absolutely necessary
- Build lookup maps for O(1) access instead of iterating lists repeatedly
- Resources returned from `core::getresources()` have attributes at TOP LEVEL — access as `resource.bucket`, NOT `resource.attrs.bucket`

### 3.7 String Function Limitations

During the private beta, the following string operations are NOT available:

- No `core::startswith()` or `core::endswith()` — cannot check string prefixes/suffixes
- No substring matching — `core::contains()` only works for lists, NOT strings
- No regex functions — cannot validate string patterns
- Only available: `core::length()` for string length, `core::join()` to create strings from lists
- Workaround: Use explicit allowlists, exact matching, or simplified intent instead of string parsing

### 3.8 Collection Operations

- List comprehensions: `[for rule in attrs.ingress : rule if rule.to_port == 22]`
- `core::anytrue(list)` — returns true if any element is true
- `core::alltrue(list)` — returns true if all elements are true
- Quantifier expressions: `all v in collection : (condition)`, `any v in collection : (condition)`
- Convert sets to lists before indexing: `[for item in set : item][0]`

### 3.9 Block Argument Syntax

- Nested single blocks in `attrs` MUST use `=` sign assignment: `nested_block = { key = "value" }`
- Nested list/set blocks in `attrs` MUST use `= [{}]` syntax: `nested_blocks = [{ key = "value" }]`
- Top-level block arguments follow standard HCL block syntax

### 3.10 Cross-Resource Limitations

- New resources with cross-references may NOT have fully resolved values at policy evaluation time
- Cross-resource policies are more reliable for updates and explicit literal matches than for first-time resource creation
- Cannot distinguish between literal values, references, and computed values in attribute values
- Cannot navigate resource reference metadata — no equivalent of config attribute reference inspection exists in tfpolicy

---

## 4. Testing Rules

### 4.1 Coverage Requirements

- Every policy file MUST have a corresponding `.policytest.hcl` file
- Every policy MUST have at least one positive test case (expected to pass)
- Every policy MUST have at least one negative test case (`expect_failure = true`)
- Omitting either positive or negative tests is PROHIBITED

### 4.2 Test File Structure

- Test files MUST declare `policytest { targets = [...] }` explicitly — targets are never inferred
- Mock resources MUST include realistic attribute values that mirror actual Terraform plan output
- Provider policy tests MUST include `meta` blocks with `source` and `version`
- Module policy tests MUST include `meta` blocks with `source` and `version`
- Data source mocks use `data` blocks with static `attrs`

### 4.3 Cross-Resource Tests

- Use `skip = true` on helper resources that exist only to support cross-resource relationship tests
- Skipped resources are not evaluated by policies but are available for relationship lookups

### 4.4 Test Naming

- Test cases MUST have descriptive names reflecting the scenario: `"s3_bucket_with_encryption_enabled"`, `"s3_bucket_without_encryption_fails"`
- Negative test names SHOULD include `fails` or `denied` to signal intent

---

## 5. Security Defaults

### 5.1 Encryption Policies

- Default `enforcement_level = "mandatory"`
- MUST cover both at-rest and in-transit encryption where applicable
- MUST validate encryption key configuration (KMS key ARN, algorithm)

### 5.2 Public Access Policies

- Default `enforcement_level = "mandatory"`
- MUST block public exposure by default (S3 public access blocks, RDS public accessibility, security group 0.0.0.0/0 ingress)
- Exception paths MUST require explicit justification via tagging or workspace metadata

### 5.3 Provider and Module Governance

- Default `enforcement_level = "mandatory"`
- Provider policies MUST restrict to approved provider sources and version ranges
- Module policies MUST restrict to approved registry sources and version ranges
- Unapproved sources MUST be blocked, not merely warned

### 5.4 Tagging Policies

- MAY use `enforcement_level = "advisory"` during initial rollout
- MUST transition to `"mandatory"` once teams have had a documented grace period
- Required tags MUST be enumerated explicitly — no open-ended tag requirements

---

## 6. HCP Terraform Integration

### 6.1 Policy Set Deployment

- Policy sets MUST be VCS-backed — manual uploads are PROHIBITED for production policy sets
- Policy set repositories MUST pass `tfpolicy validate` and `tfpolicy test` in CI before merge

### 6.2 Evaluation Stages

| Stage               | Use Case                                                                         |
| ------------------- | -------------------------------------------------------------------------------- |
| Plan-time (default) | Configuration validation — resource arguments, provider settings, module sources |
| Apply-time          | Realized value validation — computed attributes, post-apply state                |

- Use plan-time evaluation unless the policy depends on computed values not available until apply
- MUST NOT use apply-time evaluation as a workaround for incomplete plan-time data when plan-time is sufficient

### 6.3 Workspace Targeting

- Scope policies to workspaces via workspace tags in `meta.tfe_workspace.tags`
- Use `filter` blocks referencing workspace tags for environment-specific enforcement (e.g., `"production"` vs `"development"`)
- Policies intended for all workspaces MUST NOT include workspace tag filters

---

## 7. Change Management

### 7.1 Git Workflow

- Direct commits to `main` PROHIBITED
- All changes MUST be made via feature branches
- Pull requests with human review REQUIRED for all merges
- MUST NOT commit secrets, credentials, or sensitive data in policy files or tests

### 7.2 Quality Gates

| Gate       | Condition                                                                    |
| ---------- | ---------------------------------------------------------------------------- |
| Pre-merge  | `tfpolicy validate --policies=policies/` passes                              |
| Pre-merge  | `tfpolicy test --policies=policies/ --tests=tests/` passes — all tests green |
| Pre-merge  | Peer review approved                                                         |
| Post-merge | Policy set syncs to HCP Terraform via VCS integration                        |

### 7.3 Versioning

- Policy repositories SHOULD use semantic versioning via Git tags
- Breaking changes (removing policies, tightening enforcement levels) MUST be communicated to affected teams before merge
- CHANGELOG entries MUST accompany every policy change

---

## 8. Governance

### 8.1 Constitution Maintenance

- Platform team maintains this constitution in version control
- Major changes require security and governance team review
- Policy developers MAY propose amendments via pull request
- Constitution version MUST be referenced in agent prompts

### 8.2 Exception Process

Deviations from this constitution require:

1. Documented requirement driving the exception
2. Alternative approach with risk assessment
3. Platform team approval
4. Exception documented in code and centralized exceptions register
5. Review during next policy update cycle

### 8.3 Audit and Compliance

- All policy code — AI-generated or human-authored — passes through the same review process
- Periodic audits verify constitution compliance
- Non-compliant patterns trigger constitution updates or policy remediation
- Metrics track policy coverage, test pass rates, and enforcement posture

---

# Policy Design: {policy-set-name}

**Branch**: feat/{name}
**Date**: {YYYY-MM-DD}
**Status**: Draft | Approved | Implementing | Complete
**Terraform**: >= {version}
**HCP Terraform Organization**: {organization}

---

## Table of Contents

1. [Purpose & Requirements](#1-purpose--requirements)
2. [Policy Inventory & Architecture](#2-policy-inventory--architecture)
3. [Policy Specifications](#3-policy-specifications)
4. [Test Scenarios](#4-test-scenarios)
5. [HCP Terraform Configuration](#5-hcp-terraform-configuration)
6. [Implementation Checklist](#6-implementation-checklist)
7. [Open Questions](#7-open-questions)

---

## 1. Purpose & Requirements

{One paragraph. What this policy set enforces, who it targets,
what organizational standard it implements. No implementation details.}

**Policy set type**: {e.g., "AWS security baseline", "provider governance", "module governance"}

**Target scope**: {Which workspaces, environments, or teams this policy set applies to.}

**Scope boundary**: {What is explicitly NOT covered -- prevents scope creep.}

### Requirements

**Functional requirements** -- what each policy must enforce (testable statements):

- {Testable statement of what a policy checks and what outcome it enforces}
- ...

**Non-functional requirements** -- compliance frameworks, enforcement strictness, evaluation constraints:

- {Compliance framework reference, override policy, or performance constraint}
- ...

{Requirements bridge Purpose and Architecture. They are testable and unambiguous.
Frame capabilities in terms of enforcement outcomes, not policy syntax.}

---

## 2. Policy Inventory & Architecture

### Architectural Decisions

{Each decision as a paragraph with this structure:}

**{Decision title}**: {What was chosen}.
_Rationale_: {Why, with MCP research citation if applicable}.
_Rejected_: {What was considered and why it was rejected}.

### Policy Inventory

| Policy File       | Policy Type                                     | Target                  | Policy Name   | Enforcement Level                          | Evaluation Stage       | Description        |
| ----------------- | ----------------------------------------------- | ----------------------- | ------------- | ------------------------------------------ | ---------------------- | ------------------ |
| {file.policy.hcl} | {resource_policy/provider_policy/module_policy} | {resource type or "\*"} | {policy_name} | {advisory/mandatory/mandatory-overridable} | {plan-time/apply-time} | {what it enforces} |

{This table is the SINGLE SOURCE OF TRUTH for the policy set's policy files.
Each row maps to exactly one policy block in one .policy.hcl file.
A single file may contain multiple policy blocks -- list each block as a separate row.}

### Input Variables

| Input Name | Type                          | Default       | Description   |
| ---------- | ----------------------------- | ------------- | ------------- |
| {name}     | {string/number/bool/list/map} | {value or --} | {description} |

{Input variables are defined in `input` blocks within .policy.hcl files.
Only include this table if the policy set uses `input` blocks. Omit if none.}

### Plugin Inventory

| Plugin Name | Source        | Functions Provided     | Description        |
| ----------- | ------------- | ---------------------- | ------------------ |
| {name}      | {source path} | {function1, function2} | {what it provides} |

{Plugins extend policy evaluation with custom functions.
Only include this table if the policy set uses plugins. Omit if none.}

### Compliance Rule Mapping

| Policy Name   | Rule ID   | Framework       | Rule Description                    |
| ------------- | --------- | --------------- | ----------------------------------- |
| {policy_name} | {rule-id} | {CIS/WA/custom} | {what the compliance rule requires} |

{If consuming tf-research-policy-aws YAML output, reference the YAML rule IDs here.
Only include this table if policies map to external compliance rules. Omit if none.}

---

## 3. Policy Specifications

{For each policy listed in the Policy Inventory (Section 2), provide a full specification.
Order must match the inventory table.}

### Policy: {policy_name}

**File**: {file.policy.hcl}
**Enforcement**: {advisory/mandatory/mandatory-overridable}
**Stage**: {plan-time/apply-time}

**Filter logic**:

```hcl
{filter block if applicable, or "No filter -- evaluates all targeted resources."}
```

**Locals / computed values**:

```hcl
{locals block if applicable, or "No locals."}
```

**Policy block**:

```hcl
resource_policy "{target_type}" "{policy_name}" {
  enforcement_level = "{enforcement_level}"

  enforce {
    condition = {HCL condition expression}
    error_message = "{Actionable error message telling the operator exactly what to fix}"
  }
}
```

**Null safety**: {List any core::try() wrappers needed for optional attributes.}

**Performance notes**: {If using getresources/getdatasource, note caching strategy.
getresources() results MUST be cached in top-level locals, never inside resource_policy.
getdatasource() calls real provider APIs — avoid inside resource_policy blocks.}

**Cross-resource relationships**: {If using getresources/getdatasource to correlate across
resource types, describe the relationship and attribute access pattern.
Resources from getresources() use top-level attribute access: resource.bucket, NOT resource.attrs.bucket.
Otherwise "None."}

{Rules:

- Error messages must be actionable -- tell the operator what to change, not just what failed.
- Each enforce block maps 1:1 to a row in the Policy Inventory.
- If a policy has multiple enforce conditions, list each condition separately.
- Use getresources/getdatasource for cross-resource checks; document the lookup pattern.
- Always wrap optional attributes with core::try() for null safety.
- Keep expressions single-line (HCL parser beta limitation).
- Cache getresources() in top-level locals for O(1) reuse -- never call inside resource_policy.
- Resources from getresources() use direct attribute access (resource.bucket, not resource.attrs.bucket).
- No startswith/endswith/regex available -- use exact match or allowlists.
- Convert sets to lists before indexing: [for item in set : item][0].}

---

## 4. Test Scenarios

### Test Strategy

- **Test framework**: HCP Terraform policy tests using `.policytest.hcl` files
- **Mock approach**: Each test case defines a `resource`, `provider`, `module`, or `data` block with `attrs` (and optionally `meta`) that simulate compliant or non-compliant infrastructure
- **Targeted policies**: {list policy files under test}
- **Helper resources**: Use `skip = true` on mock resources that exist only to satisfy cross-resource relationship lookups

### Policy: {policy_name}

#### Test Case: Compliant resource (pass)

**Purpose**: Verify the policy passes when the resource meets all requirements
**Policy Target**: {resource type}

**Mock Resource**:

```hcl
resource "{resource_type}" "{test_case_name}" {
  attrs = {
    {attribute} = {compliant_value}
  }
}
```

**Expected Result**: Pass

#### Test Case: Non-compliant resource (fail)

**Purpose**: Verify the policy fails when the resource violates the requirement
**Policy Target**: {resource type}

**Mock Resource**:

```hcl
resource "{resource_type}" "{test_case_name}_fails" {
  expect_failure = true
  attrs = {
    {attribute} = {non_compliant_value}
  }
}
```

**Expected Result**: Fail (`expect_failure = true`)
**Expected Error**: "{substring of the actionable error message}"

#### Test Case: {Edge case name}

**Purpose**: {What edge case this covers -- filter bypass, wildcard, cross-resource, missing attribute}
**Policy Target**: {resource type}

**Mock Resource**:

```hcl
resource "{resource_type}" "{test_case_name}" {
  attrs = {
    {attribute} = {edge_case_value}
  }
}
```

**Helper Resources** (if cross-resource):

```hcl
resource "{related_resource_type}" "{helper_name}" {
  skip = true
  attrs = {
    {attribute} = {value}
  }
}
```

**Expected Result**: {Pass/Fail}

{Rules:

- Every policy in the inventory must have at least one pass and one fail test case.
- Each test case maps 1:1 to a run block in a .policytest.hcl file.
- Edge cases should cover: filter bypass, wildcard behavior, missing attributes,
  cross-resource scenarios, and boundary values for numeric thresholds.
- Use skip = true for helper resources that exist only to satisfy relationship lookups.}

---

## 5. HCP Terraform Configuration

### Policy Set Organization

| Policy Set Name   | Policy Files                         | Description              |
| ----------------- | ------------------------------------ | ------------------------ |
| {policy-set-name} | {file1.policy.hcl, file2.policy.hcl} | {what this set enforces} |

{A policy set groups related policies for deployment to HCP Terraform.
One design may define one or more policy sets if logical separation is needed.}

### Workspace Targeting

| Policy Set Name   | Targeting Strategy                | Selector                         | Description          |
| ----------------- | --------------------------------- | -------------------------------- | -------------------- |
| {policy-set-name} | {tag-based/workspace-list/global} | {tag pattern or workspace names} | {why this targeting} |

{Rules:

- Prefer tag-based targeting for scalability.
- Document which workspace tags must exist for the policies to apply.
- If using workspace-list targeting, document the maintenance burden.}

### Evaluation Stage Decisions

| Policy Name   | Stage                  | Rationale                                                                             |
| ------------- | ---------------------- | ------------------------------------------------------------------------------------- |
| {policy_name} | {plan-time/apply-time} | {why this stage -- e.g., "needs planned resource values" or "needs apply-time state"} |

### Override Permissions

| Enforcement Level     | Who Can Override | Approval Process                                    |
| --------------------- | ---------------- | --------------------------------------------------- |
| mandatory-overridable | {team or role}   | {process -- e.g., "requires comment justification"} |

{Only include this table if the policy set uses mandatory-overridable enforcement.
Omit if all policies are advisory or mandatory.}

---

## 6. Implementation Checklist

- [ ] **A: Scaffold** -- Create `policies/` directory, base `.policy.hcl` files with top-level `input` / `locals` / empty policy block stubs
- [ ] **B: Core policies** -- Implement single-resource policy logic and `enforce` conditions
- [ ] **C: Cross-resource policies** -- Implement policies that use `core::getresources()` / `core::getdatasource()` for relationship checks
- [ ] **D: Plugins** -- Implement custom plugin functions (if any)
- [ ] **E: HCP configuration** -- Configure policy sets, workspace targeting, and enforcement levels (`README.md` + HCP-side config)
- [ ] **F: Validation** -- Final `tfpolicy validate` + `tfpolicy test` pass

{Keep this to 4-8 items. Each item = one implementation pass.
NOT a 34-task breakdown. Each item should be completable in one agent turn.
Each item must have clear scope boundaries -- list which files it creates/modifies.
Items must not overlap: if A creates a file, B must not also create that file.
Omit items that do not apply (e.g., skip Plugins if no plugins are used).}

---

## 7. Open Questions

{Any deferred decisions marked [DEFERRED] with context.
Empty section if all questions resolved during clarification.}

---

## Template Rules

1. No section may reference another section by line number
2. Policy names appear exactly once -- in Policy Inventory (Section 2)
3. Each policy specification (Section 3) maps 1:1 to a row in Policy Inventory (Section 2)
4. Each test case maps 1:1 to a run block in a .policytest.hcl file
5. Implementation checklist items are coarse-grained -- one per logical unit with explicit file scope
6. Error messages in policy specifications must be actionable -- tell the operator what to fix
7. Input variable names appear exactly once -- in the Input Variables table (Section 2)
