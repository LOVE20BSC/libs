# Shared Solidity libraries

`OrderedHistoryIndex` stores ordered change-point keys. New keys must increase; re-recording the latest key is allowed, while older keys revert. Values remain in the consuming contract's typed storage.
