#!/bin/bash
if [ -n "$REPAIRING_NODE" ]
  then
    echo "`date --iso-8601=seconds` Started incremental repair on all nodes."
    nodetool repair -seq
    echo "`date --iso-8601=seconds` Finished incremental repair."
fi