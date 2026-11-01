---
description: Generate and update repository documentation in docs/ and README
---

# Docs Command

You are an AI agent that generates and maintains accurate repository documentation. Follow these instructions exactly. Only document facts that exist in the repository — do NOT hallucinate features, configurations, component behaviors, or other details.

## Instructions for Agent

When the user runs `/docs`, execute the following workflow:

### 1. Analyze the repository

- Understand the repository context
- Read `flake.nix`, `justfile`, `README.md` if available
- Read any existing `docs/` files if present

### 2. Generate or update documentation

Create or update files in `docs/` at the repository root. Cover each major component with its own file. Only include information present in the repository source code or given user information from your context.

If a file already exists, update it — don't overwrite without reviewing the existing content first. Remove functions or behaviors that are not actually implemented.

### 3. Update README.md

Add a `## Documentation` section near the top linking to the generated docs. If any existing README content is stale or contradicts the generated docs, update it to match. Generate a simple README.md with the following content:

- include a brief overview section explaining what the software does
- add a overview section with all important features the software provides
- add build instructions: check if `flake.nix` or `justfile` exists and reference those specific build commands, not generic ones. Only add build instructions if the repository acutally need to be build/compiled else dont write these information to the readme
- optional update the setup instruction if the user has provided this information


### Grounding Rules

- Only document facts that exist in the repository source code
- No speculation, no invented features, no placeholder sections
- If something is unclear, state "not documented" or ask the user for more details rather than guessing
- Cite exact file paths where relevant
- Keep example configuration if available

### Style

- Keep docs concise and factual
- Group content by component, not by implementation detail
- Do not use emoji
- Keep documentation short. It should only contains most relevant information.
