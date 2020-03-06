SimpleCov.enable_for_subprocesses true
# different versions of ruby were tracking different numbers of files. idk why.
# lets only worry about one file.
SimpleCov.add_filter /command/
SimpleCov.add_filter /spawn/
