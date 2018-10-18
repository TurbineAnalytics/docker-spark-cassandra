#!/bin/bash
echo "`date --iso-8601=seconds` Started full repair on all nodes."
nodetool repair -full -seq
echo "`date --iso-8601=seconds`  Finished full repair."
