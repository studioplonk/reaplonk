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

### Commit your changes

Make sure to also bump the version number in the plugin metadata.


### Checking the index
This optional command validates all files in the working tree, including untracked files, so local REAPER projects may produce metadata errors even when index generation succeeds:

```sh
reapack-index --check
``` 
 
### Updating the index

After committing package changes, run 
```sh
reapack-index --no-commit
```
from the repository root to scan changes since the commit recorded in `index.xml` and update the index without creating a Git commit.

### Reviewing the index

Review the result with 
```sh
git diff -- index.xml
``` 
and 
```sh
git diff --check
```
before committing the generated index.


### Committing the index

Complete the process by committing the updated `index.xml` to the repository with a meaningful commit message.


## License

Plugins are individually licensed (mostly LGPL-3). 
See their respective sources for details.
