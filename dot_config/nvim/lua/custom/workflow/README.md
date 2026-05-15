# Workflow Commands

## `:NewWorktree`

Creates a new worktree from the bare `repo.git` that lives inside the project root. The new worktree directory is created as a sibling of `repo.git`, using the feature branch name with `/` flattened to `-` for the directory name.

If the current tab is at the project root, the command reuses that tab and turns it into the new workspace. If the current tab is already inside a worktree, it opens the new worktree in a fresh tab. In both cases it sets the tab-local directory to the target worktree, opens Oil for that directory, and opens opencode beside it in the normal workflow layout.

## `:OpenWorktree`

Opens an existing sibling worktree directory that lives next to `repo.git`. It validates that the current directory matches the expected project layout before switching tabs or directories.

If the current tab is at the project root, the command reuses that tab for the selected worktree. If the current tab is already in a worktree, it opens the selected worktree in a new tab. The target tab is then set up the same way as `:NewWorktree`: tab-local directory changed to the worktree, Oil opened for that directory, and opencode opened in the standard side-by-side workflow layout.
