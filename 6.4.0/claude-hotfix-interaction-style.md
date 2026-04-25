---
name: 'BMAD Hotfix: Add AskUserQuestion enforcement'
description: 'Adds structured interaction enforcement to a BMAD 6.4.0 Claude Code install — forces AskUserQuestion tool usage'
---

# Hotfix: Add AskUserQuestion enforcement to BMAD

You are applying a hotfix to a BMAD 6.4.0 installation for Claude Code. This install has NO interaction_style feature. You are ADDING it from scratch.

## Step 0 — Check if hotfix is needed

Before applying any changes, check if AskUserQuestion enforcement already exists natively:

1. Search `.claude/skills/` recursively for `AskUserQuestion`
2. Search `_bmad/` recursively for `AskUserQuestion` enforcement rules

If enforcement rules are already present in the BMAD installation (not just references to the tool, but actual RULE/mandate text requiring its use), report to the user that the hotfix is not needed and abort. Otherwise, proceed.

## What this adds

Default BMAD has no mechanism to force agents to use the `AskUserQuestion` tool. Agents ask questions as plain text, which users cannot interact with structurally. This hotfix:
1. Adds `interaction_style: structured` to all config files
2. Updates activation steps to load and store the variable
3. Adds a RULE to every `.claude/skills/` entry point enforcing `AskUserQuestion`
4. Adds a mandate to the workflow task file
5. Adds rules to agent `<rules>` blocks and handler sections

## Steps

### Step 1 — Add `interaction_style` to config files

Add `interaction_style: structured` to EVERY `config.yaml` under `_bmad/`:

**`_bmad/core/config.yaml`** — append after the last line:
```yaml
interaction_style: structured
```

**`_bmad/bmm/config.yaml`** — append after the last line:
```yaml
interaction_style: structured
```

Also check for `_bmad/_memory/config.yaml` or any other module config and add there too.

### Step 2 — Update activation steps in ALL agent files

In every agent `.md` file under `_bmad/core/agents/` and `_bmad/bmm/agents/`, find the activation `<step n="2">` that loads config.yaml. It currently says:

```
- Store ALL fields as session variables: {user_name}, {communication_language}, {output_folder}
```

Replace with:

```
- Store ALL fields as session variables: {user_name}, {communication_language}, {output_folder}, {interaction_style}
```

This ensures `{interaction_style}` is available as a session variable.

### Step 3 — Add RULE to every `.claude/skills/` entry point

For EVERY `SKILL.md` file (or `.md` entry point) in `.claude/skills/` and its subdirectories, add the following line immediately after the closing `---` of the frontmatter (before any other content):

```
RULE: ALWAYS use the `AskUserQuestion` tool for ALL questions, choices, and user input. NEVER write questions as plain text. No exceptions unless the workflow explicitly requests free-form input.
```

Example — a skill file currently looks like:
```
---
name: 'create-prd'
description: '...'
---

IT IS CRITICAL THAT YOU FOLLOW...
```

After the hotfix:
```
---
name: 'create-prd'
description: '...'
---

RULE: ALWAYS use the `AskUserQuestion` tool for ALL questions, choices, and user input. NEVER write questions as plain text. No exceptions unless the workflow explicitly requests free-form input.

IT IS CRITICAL THAT YOU FOLLOW...
```

**Note:** BMAD 6.4 uses `.claude/skills/` with `SKILL.md` entry points instead of `.claude/commands/*.md`. If the project still has `.claude/commands/` (legacy layout), apply the same rule to those files as well.

### Step 4 — Add mandate to workflow task file

Find the workflow task file. Check these paths in order:
1. `_bmad/core/tasks/workflow.xml`
2. Search `_bmad/` for files containing `<llm critical="true">` if the above doesn't exist

Find the `<llm critical="true">` section. It currently starts with:

```xml
<llm critical="true">
    <mandate>Always read COMPLETE files...
```

Add this as the FIRST mandate (before the existing ones):

```xml
    <mandate>ALWAYS use the AskUserQuestion tool for ALL questions to the user. No exceptions. No inline text prompts.</mandate>
```

### Step 5 — Add rule to agent `<rules>` blocks

In ALL agent `.md` files under `_bmad/core/agents/` and `_bmad/bmm/agents/`, find the `<rules>` block. It currently starts with:

```xml
<rules>
  <r>ALWAYS communicate in {communication_language}...
```

Add this as the SECOND rule (after the communication_language rule):

```xml
  <r>ALWAYS use the AskUserQuestion tool for ALL questions, choices, and user input. NEVER write questions as plain text.</r>
```

### Step 6 — Add rule to handler sections in agent files

In agent files that have `<handler type="workflow">`, `<handler type="exec">`, or `<handler type="action">` sections, add this line at the end of each handler block (before the closing `</handler>`):

```
      RULE: ALWAYS use the AskUserQuestion tool for ALL questions to the user. No plain text prompts.
```

### Step 7 — Verify

1. Search for `AskUserQuestion` across the entire project. Confirm it appears in:
   - Every `.claude/skills/**/*.md` file (or `.claude/commands/*.md` if legacy layout)
   - The workflow task file (e.g., `_bmad/core/tasks/workflow.xml`)
   - Every agent `.md` file (in both `<rules>` and `<handler>` sections)

2. Search for `interaction_style` in all `config.yaml` files. Confirm it's present.

3. Search for `{interaction_style}` in agent activation steps. Confirm it's in the session variable list.

Report the total number of files modified.
