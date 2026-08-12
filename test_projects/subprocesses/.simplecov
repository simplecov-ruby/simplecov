SimpleCov.merge_subprocesses true
# different versions of ruby were tracking different numbers of files. idk why.
# lets only worry about one file.
SimpleCov.skip /command/
SimpleCov.skip /spawn/
