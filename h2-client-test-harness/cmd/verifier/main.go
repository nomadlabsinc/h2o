package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
	_ "github.com/nomadlabsinc/h2-client-test-harness/verifier/cases/generic"
	_ "github.com/nomadlabsinc/h2-client-test-harness/verifier/cases/hpack"
	_ "github.com/nomadlabsinc/h2-client-test-harness/verifier/cases/http2"
)

func main() {
	testCaseID := flag.String("test", "", "The ID of the test case to run (e.g., '6.5/1')")
	flag.Parse()

	if *testCaseID == "" {
		fmt.Println("Usage: go run ./cmd/verifier --test=<test_case_id>")
		verifier.PrintAllTests()
		os.Exit(1)
	}

	testFunc, ok := verifier.GetTest(*testCaseID)
	if !ok {
		log.Fatalf("Test case '%s' not found.", *testCaseID)
	}

	log.Printf("Running verifier for test case: %s", *testCaseID)
	if err := testFunc(); err != nil {
		log.Fatalf("Verifier failed for test case %s: %v", *testCaseID, err)
	}

	log.Printf("Verifier passed for test case: %s", *testCaseID)
}