#!/bin/bash
echo "`date --iso-8601=seconds` Started incremental repair on all nodes."
nodetool repair -seq
echo "`date --iso-8601=seconds` Finished incremental repair."
