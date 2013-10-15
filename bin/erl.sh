#!/bin/bash

erl $( find . -iname ebin -type d | while read D; do echo " -pa $D "; done ) -name $1@127.0.0.1 -setcookie nrpc
