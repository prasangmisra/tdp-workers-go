#!/bin/bash

set -e


# execute tests with coverage profile and junit report format depending on service type
go test ./${TEST_DIR}/... -v -coverprofile /test_results/coverprofile.txt 2>&1 | go-junit-report -set-exit-code -iocopy -out /test_results/testreport.xml

# convert coverage profile into html
go tool cover -html=/test_results/coverprofile.txt -o /test_results/testcoverage.html

# convert coverage profile into xml
gocov convert /test_results/coverprofile.txt | gocov-xml > /test_results/testcoverage.xml

# get total coverage from report
go tool cover -func /test_results/coverprofile.txt | grep total | grep -Eo '[0-9]+\.[0-9]+' > /test_results/totalcoverage.txt
