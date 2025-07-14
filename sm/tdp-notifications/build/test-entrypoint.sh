#!/bin/bash

set -e 

# give RabbitMQ time to start up
sleep 5

echo "Running tests with coverage profile"
go test -tags=integration  ./...  -v -coverpkg=./... -coverprofile /test_results/coverprofile.txt 2>&1

echo "Converting coverage profile into JUnit compatible XML report"
go-junit-report -in /test_results/coverprofile.txt -iocopy -out /test_results/testreport.xml 2>&1

echo "Converting coverage profile into html"
go tool cover -html=/test_results/coverprofile.txt -o /test_results/testcoverage.html 2>&1

echo "Converting coverage profile into xml"
gocov convert /test_results/coverprofile.txt | gocov-xml > /test_results/testcoverage.xml 2>&1

echo "Getting total coverage from report"
go tool cover -func /test_results/coverprofile.txt | grep total | grep -Eo '[0-9]+\.[0-9]+' > /test_results/totalcoverage.txt
