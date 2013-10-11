#!/bin/bash

erl -pa ebin -name $1@127.0.0.1 -setcookie nrpc
