# plonk toolbox for REAPER

Effect plugins brought to you by [plonk.studio](http://plonk.studio).

## Installation

The URL to import in ReaPack is <https://raw.githubusercontent.com/studioplonk/reaplonk/refs/heads/main/index.xml>

## Updating the index

Install the indexer with 

```sh
gem install reapack-index
```

if it is not already available.
After committing package changes, run 
`reapack-index --no-commit` 
from the repository root to scan changes since the commit recorded in `index.xml` and update the index without creating a Git commit.

Review the result with 
```sh
git diff -- index.xml
``` 
and 
```sh
git diff --check
```
before committing the generated index.

The optional 
```sh
reapack-index --check
``` 
command validates all files in the working tree, including untracked files, so local REAPER projects may produce metadata errors even when index generation succeeds.

Complete the process by committing the updated `index.xml` to the repository with a meaningful commit message.


## License

Plugins are individually licensed (mostly LGPL-3). 
See their respective sources for details.
