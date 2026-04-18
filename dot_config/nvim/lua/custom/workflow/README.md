# New Worktree Feature

The New Worktree feature creates a new git worktree from the current tab's working directory context, opens that worktree in a new Neovim tab, and initializes the same workspace-plus-opencode layout used by the existing workflow. It is intended to make spinning up a focused feature workspace fast, predictable, and consistent from inside Neovim.

## Current Behavior

- Exposes a Neovim user command named `:NewWorktree`.
- Accepts two arguments:
  - `feature_name` (required)
  - `base_branch` (optional, defaults to `main`)
- Uses the current tab-local working directory as the source context.
- Creates the new worktree as a sibling directory one level above the current tab-local working directory.
- Creates a new git branch named from `feature_name` using `git worktree add -b <feature_name> ...`.
- Uses the provided `base_branch` as the branch to base the worktree on.
- If the base branch does not exist locally, tries `origin/<base_branch>`.
- If neither the local base branch nor `origin/<base_branch>` exists, the command fails.
- Validates `feature_name` conservatively and rejects unsafe or unsupported names.
- Keeps the git branch name as provided, but uses a flattened filesystem-safe directory name for the worktree path.
- Fails early if the target sibling directory already exists.
- On any failure, stops immediately and shows an error message.
- After successful worktree creation, opens a new Neovim tab.
- Stores the feature name in a tab variable for future tab-labeling behavior.
- Sets the new tab's local working directory to the newly created worktree directory.
- Opens Oil in the workspace window for that new tab.
- Opens opencode on the right using the same behavior as the existing `<leader>ot` flow.

## Specs

- Exposes a Neovim user command named `:NewWorktree`.
- Accepts two arguments:
  - `feature_name` (required)
  - `base_branch` (optional, defaults to `main`)
- Uses the current tab-local working directory as the source context.
- Creates the new worktree as a sibling directory one level above the current tab-local working directory.
- Creates a new git branch named from `feature_name` using `git worktree add -b <feature_name> ...`.
- Uses the provided `base_branch` as the branch to base the worktree on.
- If the base branch does not exist locally, tries `origin/<base_branch>`.
- If neither the local base branch nor `origin/<base_branch>` exists, the command fails.
- Validates `feature_name` conservatively and rejects unsafe or unsupported names.
- Keeps the git branch name as provided, but uses a flattened filesystem-safe directory name for the worktree path.
- Fails early if the target sibling directory already exists.
- On any failure, stops immediately and shows an error message.
- After successful worktree creation, opens a new Neovim tab.
- Stores the feature name in a tab variable for future tab-labeling behavior.
- Sets the new tab's local working directory to the newly created worktree directory.
- Opens Oil in the workspace window for that new tab.
- Opens opencode on the right using the same behavior as the existing `<leader>ot` flow.

## TODO

- Organize worktrees according to the structure described here:
  - https://www.meziantou.net/git-worktree-managing-multiple-working-directories.htm
  - Note: first do this manually to understand exactly the structure and how it works before updating the plugin to support it.
  - The plugin should also verify that the expected structure is in place and fail with an error instead of continuing when it is not.
